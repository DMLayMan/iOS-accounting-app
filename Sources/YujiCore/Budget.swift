import Foundation

public enum BudgetPeriod: String, Codable, Hashable, Sendable {
    case month, year
    public func range(containing day: Day) -> ClosedRange<Day> {
        switch self {
        case .month: return day.monthKey.fullRange
        case .year: return Day(year: day.year, month: 1, day: 1)...Day(year: day.year, month: 12, day: 31)
        }
    }
}

/// A recurring allowance effective from a calendar period. Nil explicitly ends it.
public struct BudgetRule: Codable, Hashable, Sendable {
    public var period: BudgetPeriod
    public var effectiveFrom: Day
    public var limit: Int64?
    /// Nil is the whole-ledger allowance; a category may be a parent or a leaf.
    public var categoryID: EntityID?
    public init(period: BudgetPeriod, effectiveFrom: Day, limit: Int64?, categoryID: EntityID? = nil) {
        self.period = period; self.effectiveFrom = period.range(containing: effectiveFrom).lowerBound; self.limit = limit
        self.categoryID = categoryID
    }
    public func validate() throws {
        guard (1...9999).contains(effectiveFrom.year), (1...12).contains(effectiveFrom.month), effectiveFrom.day == 1,
              period != .year || effectiveFrom.month == 1 else { throw DomainError.restoreBlocked("预算生效日期无效") }
        if let limit, !(0...Money.maxProductCents).contains(limit) { throw DomainError.invalidAmount("预算需为 0～999,999,999.99 元") }
    }
}

public struct BudgetEntryPreview {
    public let kind: TransactionKind
    public let cents: Int64
    public let date: Day
    public let replacingID: EntityID?
    public let categoryID: EntityID?
    public init(kind: TransactionKind, cents: Int64, date: Day, replacingID: EntityID? = nil, categoryID: EntityID? = nil) {
        self.kind = kind; self.cents = cents; self.date = date; self.replacingID = replacingID
        self.categoryID = categoryID
    }
}

public struct CategoryBudgetLimit: Equatable, Sendable {
    public let period: BudgetPeriod
    public let categoryID: EntityID
    public let limit: Int64
    public init(period: BudgetPeriod, categoryID: EntityID, limit: Int64) {
        self.period = period; self.categoryID = categoryID; self.limit = limit
    }
}

public struct CategoryBudgetSnapshot: Identifiable {
    public let period: BudgetPeriod
    public let categoryID: EntityID
    public let title: String
    public let snapshot: BudgetSnapshot
    public var id: String { "\(period.rawValue):\(categoryID.raw)" }
    public var overrun: Int64 { max(0, -(snapshot.remaining ?? 0)) }
}

public struct BudgetSnapshot {
    public let range: ClosedRange<Day>
    public let limit: Int64?
    public let spent: Int64
    public var remaining: Int64? { limit.map { $0 - spent } }
    public var progress: Double {
        guard let limit else { return 0 }
        guard limit > 0 else { return spent > 0 ? 1 : 0 }
        return min(1, max(0, Double(spent) / Double(limit)))
    }
}

public enum BudgetInput {
    public static func parse(_ input: String) throws -> Int64? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        guard text.range(of: "^[0-9]+(?:\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              value <= Decimal(Money.maxProductCents) / 100 else {
            throw DomainError.invalidAmount("请输入 0～999,999,999.99 元，最多两位小数")
        }
        return Money(yuan: value).cents
    }
}

extension LedgerStore {
    public func budgetLimit(in ledgerID: EntityID, period: BudgetPeriod, containing day: Day, categoryID: EntityID? = nil) -> Int64? {
        ledger(ledgerID)?.budgetRules?.filter { $0.period == period && $0.categoryID == categoryID && $0.effectiveFrom <= period.range(containing: day).lowerBound }
            .max { $0.effectiveFrom < $1.effectiveFrom }?.limit
    }
    public func budget(in ledgerID: EntityID, period: BudgetPeriod, containing day: Day, through cutoff: Day,
                       preview: BudgetEntryPreview? = nil, categoryID: EntityID? = nil) -> BudgetSnapshot {
        let range = period.range(containing: day)
        let records = activeTransactions(in: ledgerID).filter { transaction in
            range.contains(transaction.date) && transaction.date <= cutoff && transaction.id != preview?.replacingID
                && (categoryID.map { matchesCategory(transaction, id: $0) } ?? true)
        }
        var spent = TransactionTotals(records).netExpense
        if let preview, range.contains(preview.date), preview.date <= cutoff,
           categoryID == nil || preview.categoryID == categoryID || category(preview.categoryID)?.parentID == categoryID {
            if preview.kind == .expense { spent += preview.cents }
            if preview.kind == .refund { spent -= preview.cents }
        }
        return BudgetSnapshot(range: range, limit: budgetLimit(in: ledgerID, period: period, containing: day, categoryID: categoryID), spent: spent)
    }

    public func categoryBudgetLimits(in ledgerID: EntityID, containing day: Day) -> [CategoryBudgetLimit] {
        let ids = Set(ledger(ledgerID)?.budgetRules?.compactMap(\.categoryID) ?? [])
        return [BudgetPeriod.month, .year].flatMap { period in
            ids.sorted { $0.raw < $1.raw }.compactMap { id in
                budgetLimit(in: ledgerID, period: period, containing: day, categoryID: id)
                    .map { CategoryBudgetLimit(period: period, categoryID: id, limit: $0) }
            }
        }
    }

    public func categoryBudgets(in ledgerID: EntityID, period: BudgetPeriod? = nil, containing day: Day,
                                through cutoff: Day, preview: BudgetEntryPreview? = nil,
                                matching selectedCategoryID: EntityID? = nil) -> [CategoryBudgetSnapshot] {
        categoryBudgetLimits(in: ledgerID, containing: day).filter { rule in
            (period == nil || rule.period == period) && (selectedCategoryID == nil || rule.categoryID == selectedCategoryID || category(selectedCategoryID)?.parentID == rule.categoryID)
        }.map { rule in
            CategoryBudgetSnapshot(period: rule.period, categoryID: rule.categoryID, title: categoryPath(rule.categoryID),
                                   snapshot: budget(in: ledgerID, period: rule.period, containing: day, through: cutoff, preview: preview, categoryID: rule.categoryID))
        }.sorted {
            if $0.overrun != $1.overrun { return $0.overrun > $1.overrun }
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.id < $1.id
        }
    }
}
