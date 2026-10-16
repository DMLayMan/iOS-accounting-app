import XCTest
@testable import YujiCore

final class CloudSnapshotComparisonTests: XCTestCase {
    private func fixture() throws -> CloudLedgerSnapshot {
        let store = LedgerStore()
        let day = Day(year: 2026, month: 10, day: 16)
        let book = try store.createLedger(name: "差异验收", startDay: Day(year: 2022, month: 1, day: 1))
        let account = try XCTUnwrap(store.accounts(in: book.id).first)
        let category = try XCTUnwrap(store.categories(in: book.id, kind: .expense).first { $0.isLeaf })
        for index in 0..<12 {
            _ = try store.addTransaction(Transaction(id: EntityID("row-\(index)"), ledgerID: book.id, kind: .expense,
                amountCents: 100, date: index == 0 ? Day(year: 2022, month: 1, day: 1) : day,
                accountID: account.id, categoryID: category.id, note: "原备注"))
        }
        return try CloudLedgerSnapshot(data: store.data, ledgerID: book.id)
    }
    func testOldNoteOnlyChangeIsNotHiddenByRecentRowsOrEqualTotals() throws {
        let local = try fixture(); var remote = local
        let index = try XCTUnwrap(remote.transactions.firstIndex { $0.id.raw == "row-0" })
        remote.transactions[index].note = "四年前漏看的改动"
        let changes = try CloudSnapshotComparison(local: local, remote: remote).changes
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].id, "transactions:row-0")
        XCTAssertEqual(changes[0].title, "2022-01-01 · 支出 ¥1.00")
        XCTAssertEqual(changes[0].fields.map(\.id), ["note"])
        XCTAssertEqual(changes[0].fields[0].remote, "四年前漏看的改动")
    }
    func testRemovalSoftDeleteAndAmountAreExplicitAndDoNotMutateSnapshots() throws {
        let local = try fixture(); var remote = local
        remote.transactions[0].amountCents = 2200
        remote.transactions[1].deletedAt = Date()
        remote.transactions.removeLast()
        let before = try local.encoded(), remoteBefore = try remote.encoded()
        let changes = try CloudSnapshotComparison(local: local, remote: remote).changes
        XCTAssertEqual(changes.count, 3)
        XCTAssertTrue(changes.flatMap(\.fields).contains { $0.title == "金额" && $0.remote == "¥22.00" })
        XCTAssertTrue(changes.flatMap(\.fields).contains { $0.id == "deletedAt" && $0.local == "有效记录" && $0.remote == "已移到最近删除" })
        XCTAssertTrue(changes.flatMap(\.fields).contains { $0.id == "presence" && $0.remote == "不存在" })
        XCTAssertEqual(try local.encoded(), before); XCTAssertEqual(try remote.encoded(), remoteBefore)
    }
    func testBookBudgetCategoryAccountAndLongNoteDifferencesAreRetained() throws {
        let local = try fixture(); var remote = local
        remote.ledger.budgetRules = [.init(period: .month, effectiveFrom: Day(year: 2026, month: 10, day: 1), limit: 10000)]
        remote.accounts[0].name = "另一账户"
        remote.categories[0].symbolName = "cup.and.saucer"
        remote.transactions[0].note = String(repeating: "长备注", count: 100)
        let changes = try CloudSnapshotComparison(local: local, remote: remote).changes
        XCTAssertEqual(changes.count, 4)
        XCTAssertTrue(changes.flatMap(\.fields).contains { $0.id == "budgetRules" && $0.remote.contains("¥100.00") })
        XCTAssertTrue(changes.contains { $0.title == "全账本 · 月预算 · 2026-10-01 起" })
        XCTAssertEqual(changes.flatMap(\.fields).first { $0.id == "note" }?.remote.count, 300)
    }
    func testTechnicalRevisionNoiseIsHiddenButSameNamedDifferentAuthorsAreNot() throws {
        let local = try fixture(); var remote = local
        remote.transactions[0].revision += 1; remote.transactions[0].updatedAt = Date().addingTimeInterval(60)
        remote.transactions[0].lastEditorID = "b"
        XCTAssertTrue(try CloudSnapshotComparison(local: local, remote: remote).changes.isEmpty)
        var authored = local; authored.transactions[0].authorID = "a"; remote.transactions[0].authorID = "b"
        let field = try XCTUnwrap(CloudSnapshotComparison(local: authored, remote: remote, personName: { _ in "同名" }).changes.first?.fields.first)
        XCTAssertEqual(field.id, "authorID"); XCTAssertNotEqual(field.local, field.remote)
    }
}
