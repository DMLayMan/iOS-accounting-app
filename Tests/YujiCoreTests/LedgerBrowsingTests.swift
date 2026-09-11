import XCTest
@testable import YujiCore

final class LedgerBrowsingTests: XCTestCase {
    private func fixture() throws -> LedgerStore {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/stats-500.json")
        return LedgerStore(data: try XCTUnwrap(JSONFileRepository(url: url).load()))
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
