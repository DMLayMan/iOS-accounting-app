import Foundation

public struct TransactionFilter: Equatable {
    public var query: String?
    public var kind: TransactionKind?
    public var accountID: EntityID?
    public var categoryID: EntityID?
    public var range: ClosedRange<Day>?
    public var minCents: Int64?
    public var maxCents: Int64?
    public init() {}
}

public struct TransactionTotals: Equatable {
    public var expense: Int64 = 0
    public var refund: Int64 = 0
    public var income: Int64 = 0
    public var netExpense: Int64 { expense - refund }
    public var surplus: Int64 { income - netExpense }
    public init(_ records: [Transaction]) {
        for record in records {
            switch record.kind {
            case .expense: expense += record.amountCents
            case .refund: refund += record.amountCents
            case .income: income += record.amountCents
            case .transfer: break
            }
        }
    }
}

public struct LedgerOverview {
    public struct AccountBalance: Identifiable {
        public let account: Account
        public let cents: Int64
        public var id: EntityID { account.id }
    }
    public let totals: TransactionTotals
    public let balances: [AccountBalance]
    public let recordCount: Int
    public let recordedDays: Int
    public let firstRecord: Day?
    public let lastRecord: Day?
    public var balance: Int64 { balances.reduce(0) { $0 + $1.cents } }
}

extension LedgerStore {
    public func transactions(in ledgerID: EntityID, matching filter: TransactionFilter = .init()) -> [Transaction] {
        activeTransactions(in: ledgerID).filter { t in
            if let range = filter.range, !range.contains(t.date) { return false }
            if let kind = filter.kind, t.kind != kind { return false }
            if let account = filter.accountID, t.accountID != account, t.transferToAccountID != account { return false }
            if let category = filter.categoryID, !matchesCategory(t, id: category) { return false }
            if let min = filter.minCents, t.amountCents < min { return false }
            if let max = filter.maxCents, t.amountCents > max { return false }
            if let query = filter.query, !matchesCategoryQuery(t, query: query) { return false }
            return true
        }.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.raw < $1.id.raw
        }
    }

    /// Cumulative cash flow excludes openings/transfers. Account balance includes
    /// openings and both sides of transfers, including archived account history.
    public func overview(in ledgerID: EntityID, through day: Day) -> LedgerOverview {
        let records = activeTransactions(in: ledgerID).filter { $0.date <= day }
        let balances = accounts(in: ledgerID).filter { $0.startDay <= day }.map {
            LedgerOverview.AccountBalance(account: $0, cents: balance(accountID: $0.id, upTo: day))
        }
        return LedgerOverview(totals: TransactionTotals(records), balances: balances,
                              recordCount: records.count, recordedDays: Set(records.map(\.date)).count,
                              firstRecord: records.map(\.date).min(), lastRecord: records.map(\.date).max())
    }
}
