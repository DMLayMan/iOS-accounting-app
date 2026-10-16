import XCTest
@testable import YujiCore

final class StatsAuthorTests: XCTestCase {
    private let current = MonthKey(year: 2026, month: 10)
    private let today = Day(year: 2026, month: 10, day: 15)

    private func fixture() throws -> (LedgerStore, EntityID) {
        let store = LedgerStore()
        let book = try store.createLedger(name: "按记账人", startDay: Day(year: 2024, month: 1, day: 1))
        let account = try XCTUnwrap(store.accounts(in: book.id).first)
        let expense = try XCTUnwrap(store.categories(in: book.id, kind: .expense).first { $0.isLeaf })
        let income = try XCTUnwrap(store.categories(in: book.id, kind: .income).first { $0.isLeaf })
        func record(_ id: EntityID, _ author: String?, _ cents: Int64, month: Int = 10,
                    kind: TransactionKind = .expense, original: EntityID? = nil) throws {
            var t = Transaction(id: id, ledgerID: book.id, kind: kind, amountCents: cents,
                date: Day(year: 2026, month: month, day: 5), accountID: account.id,
                categoryID: kind == .refund ? nil : (kind == .income ? income.id : expense.id),
                originalExpenseID: original)
            t.authorID = author
            t.lastEditorID = author == "a" ? "b" : "a"
            try store.addTransaction(t)
        }
        try record("a", "a", 10000)
        try record("b", "b", 6000)
        try record("legacy", nil, 4000)
        try record("refund", "b", 2000, kind: .refund, original: "a")
        try record("income-a", "a", 5000, kind: .income)
        try record("income-b", "b", 2000, kind: .income)
        try record("prior-a", "a", 5000, month: 9)
        try record("prior-b", "b", 3000, month: 9)
        try record("prior-legacy", nil, 1000, month: 9)
        try record("deleted-a", "a", 99999)
        try store.deleteTransaction("deleted-a")
        return (store, book.id)
    }

    func testSummaryPartitionsCreatorsAndPreservesUnknown() throws {
        let (store, book) = try fixture()
        let a = StatsEngine(store: store, ledgerID: book, authorFilter: .person("a")).monthSummary(current)
        let b = StatsEngine(store: store, ledgerID: book, authorFilter: .person("b")).monthSummary(current)
        let unknown = StatsEngine(store: store, ledgerID: book, authorFilter: .unknown).monthSummary(current)
        let all = StatsEngine(store: store, ledgerID: book).monthSummary(current)
        XCTAssertEqual(a.netExpense, 10000); XCTAssertEqual(a.income, 5000)
        XCTAssertEqual(b.netExpense, 4000); XCTAssertEqual(b.income, 2000)
        XCTAssertEqual(unknown.netExpense, 4000)
        XCTAssertEqual(all.netExpense, a.netExpense + b.netExpense + unknown.netExpense)
        XCTAssertEqual(all.income, a.income + b.income + unknown.income)
        XCTAssertEqual(all.surplus, a.surplus + b.surplus + unknown.surplus)
    }

    func testRefundUsesItsCreatorAndOriginalCategoryAcrossPeople() throws {
        let (store, book) = try fixture()
        let stats = StatsEngine(store: store, ledgerID: book, authorFilter: .person("b"))
        let rows = stats.categoryGroups(range: current.fullRange)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.expense }, 6000)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.refund }, 2000)
        let parent = try XCTUnwrap(rows.first?.id)
        XCTAssertEqual(Set(stats.categoryTransactions(range: current.fullRange, kind: .expense, categoryID: parent).map(\.id)), ["b", "refund"])
        XCTAssertEqual(stats.categoryTransactions(range: current.fullRange, kind: .income).map(\.id), ["income-b"])
    }

    func testComparisonsChartsAndDrilldownUseSamePersonInBothPeriods() throws {
        let (store, book) = try fixture()
        let stats = StatsEngine(store: store, ledgerID: book, authorFilter: .person("a"))
        let comparison = stats.momComparison(for: current, today: today)
        XCTAssertEqual(comparison.current, 10000); XCTAssertEqual(comparison.base, 5000)
        XCTAssertEqual(comparison.percent, 100)
        let changes = stats.categoryChanges(currentRange: try XCTUnwrap(comparison.currentRange), baseRange: try XCTUnwrap(comparison.baseRange))
        XCTAssertEqual(changes.reduce(0) { $0 + $1.delta }, comparison.delta)
        let year = stats.yearSummary(2026, today: today)
        XCTAssertEqual(year.total.netExpense, 15000)
        XCTAssertEqual(year.months[current]?.netExpense, 10000)
        XCTAssertEqual(year.months[current.previous]?.netExpense, 5000)
        XCTAssertEqual(year.yoy.current, 15000)
        XCTAssertEqual(year.yoy.status, .baseZero)
    }

    func testSelectionUsesImmutableCreatorNotEditorOrNickname() throws {
        let (store, book) = try fixture()
        let stats = StatsEngine(store: store, ledgerID: book, authorFilter: .person("a"))
        _ = try store.updateTransaction("a") { $0.lastEditorID = "third-person"; $0.note = "他人编辑" }
        XCTAssertEqual(stats.categoryTransactions(range: current.fullRange, kind: .expense).map(\.id), ["a"])
        XCTAssertNil(store.transaction("legacy")?.authorID)
        let empty = StatsEngine(store: store, ledgerID: book, authorFilter: .person("no-records"))
        XCTAssertEqual(empty.summary(range: current.fullRange).netExpense, 0)
        XCTAssertTrue(empty.categoryGroups(range: current.fullRange).isEmpty)
        XCTAssertTrue(empty.categoryTransactions(range: current.fullRange, kind: .expense).isEmpty)
    }
}
