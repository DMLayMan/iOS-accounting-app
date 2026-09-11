import Foundation

/// One integrity boundary for local reads, backup restores and committed app mutations.
/// Historical references may be archived; that is distinct from eligibility for a new transaction.
public enum LedgerValidation {
    public static func validate(_ data: LedgerData) throws {
        guard (1...LedgerData.currentSchemaVersion).contains(data.schemaVersion) else {
            throw BackupService.RestoreError.unsupportedVersion(data.schemaVersion)
        }
        let ledgers = try index(data.ledgers, name: "账本")
        let accounts = try index(data.accounts, name: "账户")
        let categories = try index(data.categories, name: "分类")
        let tags = try index(data.tags, name: "历史标签")
        let transactions = try index(data.transactions, name: "交易")
        if let id = data.activeLedgerID { try require(ledgers[id] != nil, "当前账本不存在") }
        var magnitude: Int64 = 0
        func accumulate(_ cents: Int64) throws {
            let (sum, overflow) = magnitude.addingReportingOverflow(abs(cents))
            try require(!overflow && sum <= Int64.max / 4, "数据金额合计超出安全计算范围")
            magnitude = sum
        }
        for ledger in data.ledgers {
            try require(!ledger.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ledger.currencyCode == "CNY", "账本名称或币种无效")
            var keys = Set<BudgetKey>()
            for rule in ledger.budgetRules ?? [] {
                try rule.validate()
                if let id = rule.categoryID {
                    try require(categories[id]?.ledgerID == ledger.id && categories[id]?.kind == .expense, "分类预算引用无效")
                }
                try require(keys.insert(BudgetKey(categoryID: rule.categoryID, period: rule.period, day: rule.effectiveFrom)).inserted, "同一周期存在重复预算")
            }
        }
        for account in data.accounts {
            try require(!account.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "账户名称为空")
            try require(ledgers[account.ledgerID] != nil && account.startDay.isValid, "账户归属或起点日期无效")
            try require((-Money.maxProductCents...Money.maxProductCents).contains(account.openingBalanceCents), "账户期初超出金额范围")
            try accumulate(account.openingBalanceCents)
        }
        for node in data.categories {
            try require(!node.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "分类名称为空")
            try require(ledgers[node.ledgerID] != nil && (node.kind == .expense || node.kind == .income), "分类归属或类型无效")
            if let id = node.parentID {
                guard let parent = categories[id] else { throw invalid("分类分组缺失") }
                try require(parent.parentID == nil && parent.id != node.id && parent.ledgerID == node.ledgerID && parent.kind == node.kind, "分类必须为同一账本下的两级结构")
            }
        }
        for node in data.tags {
            try require(!node.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "历史标签名称为空")
            try require(ledgers[node.ledgerID] != nil, "历史标签归属无效")
            if let id = node.parentID {
                guard let parent = tags[id] else { throw invalid("历史标签分组缺失") }
                try require(parent.parentID == nil && parent.id != node.id && parent.ledgerID == node.ledgerID, "历史标签结构无效")
            }
        }
        var operations = Set<String>()
        var refunds: [EntityID: Int64] = [:]
        for transaction in data.transactions {
            let t = transaction
            try require(!t.operationID.isEmpty && operations.insert(t.operationID).inserted && t.revision > 0 && t.revision < Int.max, "交易操作标识或修订号无效")
            try require(ledgers[t.ledgerID] != nil && t.date.isValid, "交易归属或日期无效")
            try require((Money.minProductCents...Money.maxProductCents).contains(t.amountCents), "交易金额超出范围")
            try accumulate(t.amountCents)
            guard let account = accounts[t.accountID], account.ledgerID == t.ledgerID else { throw invalid("交易账户缺失或跨账本") }
            if t.isActive { try require(t.date >= account.startDay, "有效交易早于账户起点") }
            for id in t.tagIDs { try require(tags[id]?.ledgerID == t.ledgerID, "历史标签引用缺失或跨账本") }
            switch t.kind {
            case .expense, .income:
                guard let id = t.categoryID, let category = categories[id] else { throw invalid("交易分类缺失") }
                try require(category.isLeaf && category.ledgerID == t.ledgerID && category.kind == t.kind, "交易分类层级、账本或收支类型不符")
            case .transfer:
                guard let id = t.transferToAccountID, let target = accounts[id] else { throw invalid("转入账户缺失") }
                try require(target.id != account.id && target.ledgerID == t.ledgerID, "转账账户相同或跨账本")
                if t.isActive { try require(t.date >= target.startDay, "转账早于转入账户起点") }
            case .refund:
                guard let id = t.originalExpenseID, let original = transactions[id] else { throw invalid("退款原支出缺失") }
                try require(original.kind == .expense && original.ledgerID == t.ledgerID, "退款原记录类型或账本不符")
                if t.isActive {
                    try require(original.isActive && t.date >= original.date, "退款原支出已删除或日期关系无效")
                    let (sum, overflow) = (refunds[id] ?? 0).addingReportingOverflow(t.amountCents)
                    try require(!overflow && sum <= original.amountCents, "有效退款合计超出原支出")
                    refunds[id] = sum
                }
            }
        }
        var draftLedgers = Set<EntityID>()
        for draft in data.drafts {
            try require(ledgers[draft.ledgerID] != nil && draftLedgers.insert(draft.ledgerID).inserted && draft.date.isValid, "草稿归属、日期或数量无效")
            for id in [draft.accountID, draft.transferToAccountID].compactMap({ $0 }) {
                try require(accounts[id]?.ledgerID == draft.ledgerID, "草稿账户缺失或跨账本")
            }
            if let id = draft.categoryID { try require(categories[id]?.ledgerID == draft.ledgerID, "草稿分类缺失或跨账本") }
            for id in draft.tagIDs { try require(tags[id]?.ledgerID == draft.ledgerID, "草稿历史标签缺失或跨账本") }
            if let id = draft.originalExpenseID { try require(transactions[id]?.ledgerID == draft.ledgerID, "草稿原交易缺失或跨账本") }
        }
    }
    private struct BudgetKey: Hashable { let categoryID: EntityID?; let period: BudgetPeriod; let day: Day }
    private static func invalid(_ message: String) -> DomainError { .restoreBlocked(message) }
    private static func require(_ condition: Bool, _ message: String) throws { if !condition { throw invalid(message) } }
    private static func index<T: Identifiable>(_ records: [T], name: String) throws -> [EntityID: T] where T.ID == EntityID {
        var result: [EntityID: T] = [:]
        for record in records {
            try require(!record.id.raw.isEmpty && result[record.id] == nil, "\(name)标识为空或重复")
            result[record.id] = record
        }
        return result
    }
}
