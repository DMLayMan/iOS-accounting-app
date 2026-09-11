import Foundation

extension LedgerStore {
    public func setBudgets(ledgerID: EntityID, monthly: Int64?, yearly: Int64?, effective day: Day) throws {
        guard let i = data.ledgers.firstIndex(where: { $0.id == ledgerID }) else { throw DomainError.notFound("账本") }
        guard !data.ledgers[i].archived else { throw DomainError.archivedLedgerNoNewTransactions }
        let updates = [BudgetRule(period: .month, effectiveFrom: day, limit: monthly), BudgetRule(period: .year, effectiveFrom: day, limit: yearly)]
        for rule in updates { try rule.validate() }
        var rules = data.ledgers[i].budgetRules ?? []
        for rule in updates {
            if budgetLimit(in: ledgerID, period: rule.period, containing: day) == rule.limit { continue }
            rules.removeAll { $0.categoryID == nil && $0.period == rule.period && $0.effectiveFrom == rule.effectiveFrom }
            rules.append(rule)
        }
        data.ledgers[i].budgetRules = rules.isEmpty ? nil : rules
        data.schemaVersion = LedgerData.currentSchemaVersion
    }

    /// Replace the current category plan atomically; removals end at this period, preserving history.
    public func setCategoryBudgets(ledgerID: EntityID, limits: [CategoryBudgetLimit], effective day: Day) throws {
        guard let index = data.ledgers.firstIndex(where: { $0.id == ledgerID }) else { throw DomainError.notFound("账本") }
        guard !data.ledgers[index].archived else { throw DomainError.archivedLedgerNoNewTransactions }
        var keys = Set<String>()
        for item in limits {
            try BudgetRule(period: item.period, effectiveFrom: day, limit: item.limit).validate()
            guard let node = category(item.categoryID), node.ledgerID == ledgerID, node.kind == .expense else {
                throw DomainError.invalidParent("请选择本账本的支出分类")
            }
            if node.archived || category(node.parentID)?.archived == true {
                guard budgetLimit(in: ledgerID, period: item.period, containing: day, categoryID: node.id) != nil else { throw DomainError.categoryArchived }
            }
            guard keys.insert("\(item.period.rawValue):\(item.categoryID.raw)").inserted else { throw DomainError.invalidAmount("同一分类每月、每年各可设置一条预算") }
        }
        let existing = categoryBudgetLimits(in: ledgerID, containing: day)
        var rules = data.ledgers[index].budgetRules ?? []
        let updates = limits.map { BudgetRule(period: $0.period, effectiveFrom: day, limit: $0.limit, categoryID: $0.categoryID) }
            + existing.filter { old in !limits.contains { $0.period == old.period && $0.categoryID == old.categoryID } }
                .map { BudgetRule(period: $0.period, effectiveFrom: day, limit: nil, categoryID: $0.categoryID) }
        for rule in updates {
            if budgetLimit(in: ledgerID, period: rule.period, containing: day, categoryID: rule.categoryID) == rule.limit { continue }
            rules.removeAll { $0.categoryID == rule.categoryID && $0.period == rule.period && $0.effectiveFrom == rule.effectiveFrom }
            rules.append(rule)
        }
        data.ledgers[index].budgetRules = rules.isEmpty ? nil : rules
        data.schemaVersion = LedgerData.currentSchemaVersion
    }

}
