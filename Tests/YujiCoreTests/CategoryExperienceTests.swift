import XCTest
@testable import YujiCore

final class CategoryExperienceTests: XCTestCase {
    private let today = Day(year: 2026, month: 9, day: 10)

    func testSiblingOrderPersistsWithoutChangingTransactionsOrOtherGroups() throws {
        let store = LedgerStore(); let ledger = try store.createLedger(name: "排序", startDay: today)
        let first = store.categories(in: ledger.id, kind: .expense).first { !$0.isLeaf }!
        let children = store.categories(in: ledger.id, kind: .expense).filter { $0.parentID == first.id }
        let outside = store.data.categories.filter { $0.parentID != first.id }
        let transaction = Transaction(ledgerID: ledger.id, kind: .expense, amountCents: 3600,
            date: today, accountID: store.accounts(in: ledger.id)[0].id, categoryID: children[0].id)
        try store.addTransaction(transaction)
        let reversed = children.reversed().map(\.id)
        try store.reorderCategories(ledgerID: ledger.id, kind: .expense, parentID: first.id, orderedIDs: reversed)
        let restored = LedgerStore(data: try JSONDecoder().decode(LedgerData.self, from: JSONEncoder().encode(store.data)))
        XCTAssertEqual(restored.categories(in: ledger.id, kind: .expense).filter { $0.parentID == first.id }.map(\.id), reversed)
        XCTAssertEqual(store.data.categories.filter { $0.parentID != first.id }, outside)
        XCTAssertEqual(store.transaction(transaction.id), transaction)
    }

    func testInvalidOrStaleReorderIsAtomic() throws {
        let store = LedgerStore(); let ledger = try store.createLedger(name: "排序", startDay: today)
        let parents = store.categories(in: ledger.id, kind: .expense).filter { !$0.isLeaf }
        let ids = parents.map(\.id); let before = store.data
        for invalid in [Array(ids.dropLast()), [ids[0]] + Array(ids.dropLast()), ids + [EntityID.new()]] {
            XCTAssertThrowsError(try store.reorderCategories(ledgerID: ledger.id, kind: .expense, parentID: nil, orderedIDs: invalid))
            XCTAssertEqual(store.data.categories, before.categories)
        }
        XCTAssertThrowsError(try store.reorderCategories(ledgerID: ledger.id, kind: .income, parentID: nil, orderedIDs: ids))
        try store.reorderCategories(ledgerID: ledger.id, kind: .expense, parentID: nil, orderedIDs: Array(ids.reversed()))
        XCTAssertEqual(store.categories(in: ledger.id, kind: .expense).filter { !$0.isLeaf }.map(\.id), Array(ids.reversed()))
    }

    func testLegacyCategoryDecodesWithoutPin() throws {
        let node = try JSONDecoder().decode(CategoryNode.self, from: Data("""
        {"id":{"raw":"c"},"ledgerID":{"raw":"l"},"kind":"expense","name":"餐饮","archived":false,"sortOrder":0}
        """.utf8))
        XCTAssertNil(node.pinnedOrder)
        XCTAssertNil(node.symbolName)
    }

    func testCustomIconSurvivesRenameMoveAndReloadAndRejectsUnknownIcon() throws {
        let store = LedgerStore(); let ledger = try store.createLedger(name: "图标")
        let parents = store.categories(in: ledger.id, kind: .expense).filter { !$0.isLeaf }
        let child = try store.createCategory(ledgerID: ledger.id, kind: .expense, parentID: parents[0].id, name: "早午餐")
        try store.setCategorySymbol(child.id, symbolName: "cup.and.saucer")
        try store.editCategory(child.id, name: "周末", parentID: parents[1].id)
        let backup = try BackupService.makeBackup(from: store)
        let restored = LedgerStore(data: try BackupService.validate(backup: BackupService.decode(BackupService.encode(backup))))
        XCTAssertEqual(restored.category(child.id)?.symbolName, "cup.and.saucer")
        XCTAssertEqual(restored.category(child.id)?.parentID, parents[1].id)
        XCTAssertThrowsError(try restored.setCategorySymbol(child.id, symbolName: "unknown-symbol"))
        XCTAssertEqual(restored.category(child.id)?.symbolName, "cup.and.saucer")
        try restored.setCategorySymbol(child.id, symbolName: nil)
        XCTAssertNil(restored.category(child.id)?.symbolName)
    }

    func testCategoryEditingPreservesReferencesAndRejectsSiblingDuplicates() throws {
        let s = LedgerStore(); let l = try s.createLedger(name: "测试")
        let parents = s.categories(in: l.id, kind: .expense).filter { !$0.isLeaf }
        let c = try s.createCategory(ledgerID: l.id, kind: .expense, parentID: parents[0].id, name: "出差餐费")
        s.saveDraft(Draft(ledgerID: l.id, date: today, categoryID: c.id))
        try s.editCategory(c.id, name: "  工作餐 \n", parentID: parents[1].id)
        XCTAssertEqual(s.category(c.id)?.name, "工作餐")
        XCTAssertEqual(s.category(c.id)?.parentID, parents[1].id)
        XCTAssertEqual(s.draft(for: l.id)?.categoryID, c.id)
        XCTAssertThrowsError(try s.createCategory(ledgerID: l.id, kind: .expense, parentID: parents[1].id, name: "工作餐"))
        XCTAssertThrowsError(try s.editCategory(c.id, name: "工作餐", parentID: c.id))
        XCTAssertEqual(s.category(c.id)?.parentID, parents[1].id)
    }

    func testDeletingParentWithReferencedChildIsAtomic() throws {
        let s = LedgerStore(); let l = try s.createLedger(name: "测试")
        let c = s.categories(in: l.id, kind: .expense).first { $0.isLeaf }!
        s.saveDraft(Draft(ledgerID: l.id, date: today, categoryID: c.id))
        let before = s.data.categories
        XCTAssertThrowsError(try s.deleteCategory(c.parentID!))
        XCTAssertEqual(s.data.categories, before)
        XCTAssertThrowsError(try s.deleteCategory(c.id))
        let unused = try s.createCategory(ledgerID: l.id, kind: .expense, parentID: c.parentID, name: "临时")
        try s.deleteCategory(unused.id)
        XCTAssertNil(s.category(unused.id))
    }

    func testRecommendationUsesFrequencyAndPinsWithoutNotesOrAmounts() throws {
        let s = LedgerStore(); let l = try s.createLedger(name: "测试")
        let leaves = s.categories(in: l.id, kind: .expense).filter(\.isLeaf)
        var data = s.data
        for day in 7...9 {
            data.transactions.append(Transaction(ledgerID: l.id, kind: .expense, amountCents: 100,
                date: Day(year: 2026, month: 9, day: day), accountID: data.accounts[0].id,
                categoryID: leaves[3].id, note: leaves[6].name))
        }
        data.transactions.append(Transaction(ledgerID: l.id, kind: .expense, amountCents: 900000,
            date: today, accountID: data.accounts[0].id, categoryID: leaves[4].id))
        let store = LedgerStore(data: data)
        XCTAssertEqual(store.recommendedCategories(in: l.id, kind: .expense, today: today).first?.id, leaves[3].id)
        try store.setCategoryPinned(leaves[5].id, pinned: true)
        XCTAssertEqual(store.recommendedCategories(in: l.id, kind: .expense, today: today).first?.id, leaves[5].id)
        try store.archiveCategory(leaves[5].id, archived: true)
        XCTAssertFalse(store.recommendedCategories(in: l.id, kind: .expense, today: today).contains { $0.id == leaves[5].id })
    }

    func testRecommendationExcludesOtherLedgersFutureTrashAndRefunds() throws {
        let s = LedgerStore(); let l = try s.createLedger(name: "测试"); let foreign = try s.createLedger(name: "其他")
        let leaves = s.categories(in: l.id, kind: .expense).filter(\.isLeaf)
        var data = s.data
        for i in 0..<20 {
            var t = Transaction(ledgerID: i % 2 == 0 ? foreign.id : l.id, kind: .expense, amountCents: 100,
                date: today.nextDay, accountID: data.accounts[0].id, categoryID: leaves.last!.id)
            if i % 3 == 0 { t.deletedAt = Date() }; if i % 3 == 1 { t.kind = .refund }
            data.transactions.append(t)
        }
        let store = LedgerStore(data: data)
        XCTAssertEqual(store.recommendedCategories(in: l.id, kind: .expense, today: today).map(\.id), Array(leaves.prefix(6)).map(\.id))
    }

    func testNotesNeverMatchSearchAndParentMatchesChildren() throws {
        let s = LedgerStore(); let l = try s.createLedger(name: "测试")
        let c = s.categories(in: l.id, kind: .expense).first { $0.isLeaf }!
        let t = Transaction(ledgerID: l.id, kind: .expense, amountCents: 100, date: today,
            accountID: s.accounts(in: l.id)[0].id, categoryID: c.id, note: "独有备注词")
        XCTAssertFalse(s.matchesCategoryQuery(t, query: "独有备注词"))
        XCTAssertTrue(s.matchesCategoryQuery(t, query: s.category(c.parentID)!.name))
        XCTAssertTrue(s.matchesCategory(t, id: c.parentID!))
    }

    func testPinLimitAndPersistence() throws {
        let s = LedgerStore(); let l = try s.createLedger(name: "测试")
        let leaves = s.categories(in: l.id, kind: .expense).filter(\.isLeaf)
        for c in leaves.prefix(4) { try s.setCategoryPinned(c.id, pinned: true) }
        XCTAssertThrowsError(try s.setCategoryPinned(leaves[4].id, pinned: true))
        let restored = LedgerStore(data: try JSONDecoder().decode(LedgerData.self, from: JSONEncoder().encode(s.data)))
        XCTAssertEqual(restored.recommendedCategories(in: l.id, kind: .expense, today: today).prefix(4).map(\.id), Array(leaves.prefix(4)).map(\.id))
    }

    func testEditingDoesNotChangeRecommendationAndArchivedParentExcludesChildren() throws {
        let s = LedgerStore(); let l = try s.createLedger(name: "测试")
        let leaves = s.categories(in: l.id, kind: .expense).filter(\.isLeaf)
        var data = s.data
        data.transactions.append(Transaction(ledgerID: l.id, kind: .expense, amountCents: 100,
            date: today, accountID: data.accounts[0].id, categoryID: leaves[1].id))
        data.transactions.append(Transaction(ledgerID: l.id, kind: .expense, amountCents: 100,
            date: Day(year: 2025, month: 9, day: 10), accountID: data.accounts[0].id, categoryID: leaves.last!.id,
            note: "今天刚修改的旧备注"))
        let store = LedgerStore(data: data)
        XCTAssertEqual(store.recommendedCategories(in: l.id, kind: .expense, today: today).first?.id, leaves[1].id)
        try store.archiveCategory(leaves[1].parentID!, archived: true)
        XCTAssertFalse(store.recommendedCategories(in: l.id, kind: .expense, today: today).contains { $0.parentID == leaves[1].parentID })
    }

    func testHistoricalCategoryMoveKeepsTotalsAndLegacyInformation() throws {
        let s = LedgerStore(); let l = try s.createLedger(name: "测试")
        let leaves = s.categories(in: l.id, kind: .expense).filter(\.isLeaf)
        var data = s.data
        let tag = data.tags.first { $0.isLeaf }!
        let expense = Transaction(ledgerID: l.id, kind: .expense, amountCents: 3000, date: today,
            accountID: data.accounts[0].id, categoryID: leaves[0].id, tagIDs: [tag.id], note: "保留的个人信息")
        data.transactions.append(expense)
        let store = LedgerStore(data: data)
        try store.editCategory(leaves[0].id, name: "早餐开销", parentID: leaves.last!.parentID)
        XCTAssertEqual(store.transaction(expense.id), expense)
        XCTAssertTrue(store.matchesCategory(expense, id: leaves.last!.parentID!))
        XCTAssertFalse(store.matchesCategory(expense, id: leaves[0].parentID!))
        XCTAssertThrowsError(try store.deleteCategory(leaves.last!.parentID!))
        XCTAssertEqual(store.effectiveCategory(for: expense)?.name, "早餐开销")
    }
}
