import XCTest
@testable import YujiCore

final class LedgerBrowsingTests: XCTestCase {
    func testTransactionLookupInvalidatesAfterAddEditDeleteAndPurge() throws {
        let store = LedgerStore()
        let day = Day(year: 2026, month: 10, day: 8)
        let ledger = try store.createLedger(name: "索引", startDay: day)
        let account = try XCTUnwrap(store.accounts(in: ledger.id).first)
        let leaf = try XCTUnwrap(store.categories(in: ledger.id, kind: .expense).first { $0.isLeaf })
        let transaction = Transaction(ledgerID: ledger.id, kind: .expense, amountCents: 100, date: day, accountID: account.id, categoryID: leaf.id)
        XCTAssertNil(store.transaction(transaction.id))
        try store.addTransaction(transaction)
        XCTAssertEqual(store.transaction(transaction.id)?.amountCents, 100)
        try store.updateTransaction(transaction.id) { $0.amountCents = 200 }
        XCTAssertEqual(store.transaction(transaction.id)?.amountCents, 200)
        try store.deleteTransaction(transaction.id)
        XCTAssertFalse(try XCTUnwrap(store.transaction(transaction.id)).isActive)
        try store.restoreTransaction(transaction.id)
        XCTAssertTrue(try XCTUnwrap(store.transaction(transaction.id)).isActive)
        try store.deleteTransaction(transaction.id)
        try store.purgeTransaction(transaction.id)
        XCTAssertNil(store.transaction(transaction.id))
    }
    func testAsOfBalanceGatesFutureOpeningsAndEveryTransactionKind() throws {
        let store = LedgerStore()
        let today = Day(year: 2026, month: 10, day: 8)
        let tomorrow = Day(year: 2026, month: 10, day: 9)
        let ledger = try store.createLedger(name: "余额边界", startDay: today)
        let cash = try XCTUnwrap(store.accounts(in: ledger.id).first)
        let future = try store.createAccount(ledgerID: ledger.id, name: "明日起点", openingBalanceCents: 10_000, startDay: tomorrow)
        let leaf = try XCTUnwrap(store.categories(in: ledger.id, kind: .expense).first { $0.isLeaf })
        let income = try XCTUnwrap(store.categories(in: ledger.id, kind: .income).first { $0.isLeaf })
        let expense = try store.addTransaction(Transaction(ledgerID: ledger.id, kind: .expense, amountCents: 1_000, date: today, accountID: cash.id, categoryID: leaf.id))
        _ = try store.addTransaction(Transaction(ledgerID: ledger.id, kind: .income, amountCents: 5_000, date: today, accountID: cash.id, categoryID: income.id))
        _ = try store.addTransaction(Transaction(ledgerID: ledger.id, kind: .expense, amountCents: 2_000, date: tomorrow, accountID: cash.id, categoryID: leaf.id))
        _ = try store.addTransaction(Transaction(ledgerID: ledger.id, kind: .income, amountCents: 3_000, date: tomorrow, accountID: cash.id, categoryID: income.id))
        _ = try store.addTransaction(Transaction(ledgerID: ledger.id, kind: .refund, amountCents: 500, date: tomorrow, accountID: cash.id, originalExpenseID: expense.id))
        _ = try store.addTransaction(Transaction(ledgerID: ledger.id, kind: .transfer, amountCents: 600, date: tomorrow, accountID: cash.id, transferToAccountID: future.id))
        XCTAssertEqual(store.balance(accountID: cash.id, upTo: today), 4_000)
        XCTAssertEqual(store.balance(accountID: future.id, upTo: today), 0)
        XCTAssertEqual(store.overview(in: ledger.id, through: today).balance, 4_000)
        XCTAssertEqual(store.balance(accountID: cash.id, upTo: tomorrow), 4_900)
        XCTAssertEqual(store.balance(accountID: future.id, upTo: tomorrow), 10_600)
        XCTAssertEqual(store.overview(in: ledger.id, through: tomorrow).balance, 15_500)
        let restored = LedgerStore(data: try BackupService.validate(backup: BackupService.makeBackup(from: store)))
        XCTAssertEqual(restored.balance(accountID: cash.id, upTo: today), 4_000)
    }
    private func fixture() throws -> LedgerStore {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/stats-500.json")
        return LedgerStore(data: try XCTUnwrap(JSONFileRepository(url: url).load()))
    }
    func testBatchedBudgetsPreserveIndividualRuleResultsAndReplacementPreview() throws {
        let store = try fixture()
        let day = Day(year: 2026, month: 9, day: 10)
        let nodes = store.categories(in: "stress", kind: .expense, includeArchived: false)
            .filter { store.category($0.parentID)?.archived != true }
        try store.setCategoryBudgets(ledgerID: "stress", limits: nodes.flatMap { node in
            [BudgetPeriod.month, .year].map { CategoryBudgetLimit(period: $0, categoryID: node.id, limit: 100_000) }
        }, effective: day)
        for preview in [BudgetEntryPreview?.none, .some(.init(kind: .expense, cents: 9_999, date: day, replacingID: "tx-003", categoryID: "stress-food-1"))] {
            let snapshots = store.categoryBudgets(in: "stress", containing: day, through: day, preview: preview)
            XCTAssertEqual(snapshots.count, nodes.count * 2)
            for row in snapshots {
                let individual = store.budget(in: "stress", period: row.period, containing: day, through: day, preview: preview, categoryID: row.categoryID)
                XCTAssertEqual(row.snapshot.spent, individual.spent, row.id)
                XCTAssertEqual(row.snapshot.limit, individual.limit, row.id)
            }
        }
    }
    func testCumulativeOverviewIncludesAllYearsAndOpeningBalances() throws {
        let store = try fixture()
        let overview = store.overview(in: "stress", through: Day(year: 2026, month: 9, day: 10))
        XCTAssertEqual(overview.totals.expense, 28_240_494)
        XCTAssertEqual(overview.totals.refund, 1_924_112)
        XCTAssertEqual(overview.totals.income, 75_427_621)
        XCTAssertEqual(overview.totals.surplus, 49_111_239)
        XCTAssertEqual(overview.recordCount, 470)
        XCTAssertEqual(overview.firstRecord, Day(year: 2022, month: 1, day: 1))
        XCTAssertEqual(overview.lastRecord, Day(year: 2026, month: 9, day: 10))
        XCTAssertEqual(overview.balance, 49_621_239)
        XCTAssertEqual(overview.balances.reduce(0) { $0 + $1.cents }, overview.balance)
        XCTAssertEqual(overview.balance - overview.totals.surplus, 510_000)
    }
    func testOverviewExcludesFutureAndKeepsArchivedAccountHistory() throws {
        let store = try fixture()
        let day = Day(year: 2024, month: 2, day: 29)
        let before = store.overview(in: "stress", through: day)
        let account = try XCTUnwrap(store.accounts(in: "stress").first)
        try store.archiveAccount(account.id, archived: true)
        let after = store.overview(in: "stress", through: day)
        XCTAssertEqual(after.totals, before.totals)
        XCTAssertEqual(after.balance, before.balance)
        XCTAssertLessThan(after.recordCount, 470)
        XCTAssertTrue(try XCTUnwrap(after.lastRecord) <= day)
        let future = try store.createAccount(ledgerID: "stress", name: "未来账户", openingBalanceCents: 900_000, startDay: Day(year: 2027, month: 1, day: 1))
        XCTAssertFalse(store.overview(in: "stress", through: day).balances.contains { $0.account.id == future.id })
        XCTAssertEqual(store.overview(in: "stress", through: day).balance, before.balance)
    }
    func testDateRangeIsInclusiveAndComposesWithCategoryAndQuery() throws {
        let store = try fixture()
        var query = TransactionFilter()
        query.range = Day(year: 2026, month: 9, day: 6)...Day(year: 2026, month: 9, day: 10)
        query.categoryID = "stress-food-1"
        query.query = "咖啡"
        let records = store.transactions(in: "stress", matching: query)
        XCTAssertEqual(records.map(\.id.raw), ["tx-003", "tx-170"])
        XCTAssertEqual(TransactionTotals(records).netExpense, 13_990)
        query.range = Day(year: 2026, month: 9, day: 7)...Day(year: 2026, month: 9, day: 9)
        XCTAssertTrue(store.transactions(in: "stress", matching: query).isEmpty)
    }
    func testLeapMonthEmptyMonthAndLedgerIsolation() throws {
        let store = try fixture()
        var query = TransactionFilter()
        query.range = MonthKey(year: 2024, month: 2).fullRange
        XCTAssertTrue(store.transactions(in: "stress", matching: query).contains { $0.id == "tx-002" })
        query.range = MonthKey(year: 2023, month: 2).fullRange
        XCTAssertTrue(store.transactions(in: "stress", matching: query).isEmpty)
        let ledger = try store.createLedger(name: "空账本")
        XCTAssertTrue(store.transactions(in: ledger.id).isEmpty)
        let empty = store.overview(in: ledger.id, through: Day(from: Date()))
        XCTAssertEqual(empty.balance, 0); XCTAssertEqual(empty.recordCount, 0)
        XCTAssertNil(empty.firstRecord); XCTAssertNil(empty.lastRecord)
    }
}
