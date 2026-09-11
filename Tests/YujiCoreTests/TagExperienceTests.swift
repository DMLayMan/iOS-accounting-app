import XCTest
@testable import YujiCore

final class TagExperienceTests: XCTestCase {
    func testDeleteUnusedTagPreservesOtherTags() throws {
        let store = LedgerStore()
        let ledger = try store.createLedger(name: "测试")
        let removed = try store.createQuickTag(ledgerID: ledger.id, name: "临时")
        let retained = try store.createQuickTag(ledgerID: ledger.id, name: "保留")
        try store.deleteTag(removed.id)
        XCTAssertNil(store.tag(removed.id))
        XCTAssertEqual(store.tag(retained.id), retained)
        XCTAssertNotNil(store.tag(retained.parentID))
    }

    func testQuickCreationReusesNormalizedName() throws {
        let store = LedgerStore()
        let ledger = try store.createLedger(name: "测试")
        let first = try store.createQuickTag(ledgerID: ledger.id, name: "  Trip  ")
        let second = try store.createQuickTag(ledgerID: ledger.id, name: "trip")
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.name, "Trip")
        XCTAssertTrue(first.isLeaf)
    }

    func testRenameKeepsDraftReferenceAndRejectsDuplicates() throws {
        let store = LedgerStore()
        let ledger = try store.createLedger(name: "测试")
        let first = try store.createQuickTag(ledgerID: ledger.id, name: "出差")
        _ = try store.createQuickTag(ledgerID: ledger.id, name: "旅行")
        store.saveDraft(Draft(ledgerID: ledger.id, date: Day(from: Date()), tagIDs: [first.id]))
        try store.renameTag(first.id, name: "  工作出行 \n")
        XCTAssertEqual(store.tag(first.id)?.name, "工作出行")
        XCTAssertEqual(store.draft(for: ledger.id)?.tagIDs, [first.id])
        XCTAssertThrowsError(try store.renameTag(first.id, name: "旅行"))
    }

    func testDeletingGroupReferencedByDraftIsAtomic() throws {
        let store = LedgerStore()
        let ledger = try store.createLedger(name: "测试")
        let tag = try store.createQuickTag(ledgerID: ledger.id, name: "出差")
        store.saveDraft(Draft(ledgerID: ledger.id, date: Day(from: Date()), tagIDs: [tag.id]))
        let before = store.data.tags
        XCTAssertThrowsError(try store.deleteTag(try XCTUnwrap(tag.parentID)))
        XCTAssertEqual(store.data.tags, before)
        XCTAssertThrowsError(try store.deleteTag(tag.id))
    }

    func testArchiveHidesSuggestionsAndCanRestoreWithoutNewID() throws {
        let store = LedgerStore()
        let ledger = try store.createLedger(name: "测试")
        let tag = try store.createQuickTag(ledgerID: ledger.id, name: "旅行")
        try store.archiveTag(tag.id, archived: true)
        XCTAssertFalse(store.suggestedTags(in: ledger.id).contains { $0.id == tag.id })
        let restored = try store.createQuickTag(ledgerID: ledger.id, name: "旅行")
        XCTAssertEqual(restored.id, tag.id)
        XCTAssertFalse(restored.archived)
    }

    func testSuggestionRankingIsScopedAndRecent() throws {
        let store = LedgerStore()
        let ledger = try store.createLedger(name: "测试")
        let other = try store.createLedger(name: "其他")
        let tag = try store.createQuickTag(ledgerID: ledger.id, name: "旅行")
        let foreign = try store.createQuickTag(ledgerID: other.id, name: "工作")
        let account = try XCTUnwrap(store.accounts(in: ledger.id).first)
        let category = try XCTUnwrap(store.categories(in: ledger.id, kind: .expense).first { $0.isLeaf })
        try store.addTransaction(Transaction(ledgerID: ledger.id, kind: .expense, amountCents: 100,
            date: account.startDay, accountID: account.id, categoryID: category.id, tagIDs: [tag.id]))
        XCTAssertEqual(store.suggestedTags(in: ledger.id).first?.id, tag.id)
        XCTAssertFalse(store.suggestedTags(in: ledger.id).contains { $0.id == foreign.id })
    }
}
