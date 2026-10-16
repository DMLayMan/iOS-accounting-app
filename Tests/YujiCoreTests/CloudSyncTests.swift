import XCTest
@testable import YujiCore

final class CloudSyncTests: XCTestCase {
    let day = Day(year: 2026, month: 10, day: 8)
    func fixture() throws -> CloudLedgerSnapshot {
        let s = LedgerStore(); let ledger = try s.createLedger(name: "家庭", startDay: day)
        let account = s.accounts(in: ledger.id)[0]
        let category = try XCTUnwrap(s.categories(in: ledger.id, kind: .expense).first { $0.isLeaf })
        _ = try s.addTransaction(Transaction(ledgerID: ledger.id, kind: .expense, amountCents: 10_000, date: day, accountID: account.id, categoryID: category.id))
        return try CloudLedgerSnapshot(data: s.data, ledgerID: ledger.id)
    }
    func testIndependentEntriesMergeWithoutDuplicates() throws {
        let base = try fixture(); var a = base; var b = base
        var x = base.transactions[0]; x.id = .new(); x.operationID = UUID().uuidString; x.amountCents = 1200; a.transactions.append(x)
        x.id = .new(); x.operationID = UUID().uuidString; x.amountCents = 3400; b.transactions.append(x)
        let result = try CloudLedgerMerge.merge(base: base, local: a, remote: b)
        XCTAssertTrue(result.conflicts.isEmpty); XCTAssertEqual(result.snapshot.transactions.count, 3)
        XCTAssertEqual(result.snapshot.transactions.reduce(0) { $0 + $1.amountCents }, 14_600)
        let retry = try CloudLedgerMerge.merge(base: base, local: result.snapshot, remote: result.snapshot)
        XCTAssertEqual(retry.snapshot.transactions.count, 3)
    }
    func testDifferentFieldsMergeButSameAmountConflictIsVisible() throws {
        let base = try fixture(); var a = base; var b = base
        a.transactions[0].note = "早餐"; b.transactions[0].amountCents = 9000
        let ok = try CloudLedgerMerge.merge(base: base, local: a, remote: b)
        XCTAssertTrue(ok.conflicts.isEmpty); XCTAssertEqual(ok.snapshot.transactions[0].note, "早餐"); XCTAssertEqual(ok.snapshot.transactions[0].amountCents, 9000)
        a.transactions[0].amountCents = 8000
        let conflict = try CloudLedgerMerge.merge(base: base, local: a, remote: b)
        XCTAssertFalse(conflict.conflicts.isEmpty)
    }
    func testConcurrentRefundsCannotExceedOriginalExpense() throws {
        let base = try fixture(); var a = base; var b = base; let original = base.transactions[0]
        a.transactions.append(Transaction(ledgerID: base.ledger.id, kind: .refund, amountCents: 8000, date: day, accountID: original.accountID, originalExpenseID: original.id))
        b.transactions.append(Transaction(ledgerID: base.ledger.id, kind: .refund, amountCents: 8000, date: day, accountID: original.accountID, originalExpenseID: original.id))
        let result = try CloudLedgerMerge.merge(base: base, local: a, remote: b)
        XCTAssertFalse(result.conflicts.isEmpty); XCTAssertTrue(result.conflicts.joined().contains("退款"))
    }
    func testDeleteVersusEditCannotResurrectSilently() throws {
        let base = try fixture(); var a = base; var b = base
        a.transactions.removeAll(); b.transactions[0].note = "修改"
        XCTAssertFalse(try CloudLedgerMerge.merge(base: base, local: a, remote: b).conflicts.isEmpty)
        a = base; a.transactions[0].deletedAt = Date()
        XCTAssertFalse(try CloudLedgerMerge.merge(base: base, local: a, remote: b).conflicts.isEmpty)
    }
    func testWireRoundTripNeverIncludesPersonalDraftOrTheme() throws {
        let base = try fixture(); let bytes = try base.encoded()
        XCTAssertEqual(try CloudLedgerSnapshot.decode(bytes).encoded(), bytes)
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(text.contains("drafts")); XCTAssertFalse(text.contains("settings"))
    }
    func testRefreshingActiveCloudBookDoesNotSwitchToAnotherLedger() throws {
        let book = try fixture()
        let local = LedgerStore()
        _ = try local.createLedger(name: "纯本地", startDay: day)
        var data = local.data
        data.cloudLinks = [CloudLink(accountID: "owner", address: CloudAddress(container: "test", zoneName: "book"), cached: book)]
        try CloudWorkspace.install(book, in: &data)
        data.activeLedgerID = book.ledger.id
        try CloudWorkspace.install(book, in: &data)
        XCTAssertEqual(data.activeLedgerID, book.ledger.id)
        XCTAssertEqual(data.ledgers.count, 2)
    }
}

extension CloudSyncTests {
    func testIndependentBudgetRulesMergeAndSameScopeConflicts() throws {
        let base = try fixture(); var a = base; var b = base
        a.ledger.budgetRules = [.init(period: .month, effectiveFrom: day, limit: 10000)]
        b.ledger.budgetRules = [.init(period: .year, effectiveFrom: day, limit: 120000)]
        let result = try CloudLedgerMerge.merge(base: base, local: a, remote: b)
        XCTAssertTrue(result.conflicts.isEmpty); XCTAssertEqual(result.snapshot.ledger.budgetRules?.count,2)
        b.ledger.budgetRules = [.init(period: .month, effectiveFrom: day, limit: 20000)]
        XCTAssertFalse(try CloudLedgerMerge.merge(base: base, local: a, remote: b).conflicts.isEmpty)
    }
    func testVersionThreeDecodesAndReencodesWithoutCloudBinding() throws {
        let base = try fixture(); var data = base.materialized(); data.schemaVersion = 3
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let bytes = try e.encode(data); let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let decoded = try d.decode(LedgerData.self, from:bytes)
        XCTAssertNil(decoded.cloudLinks); XCTAssertNil(decoded.transactions.first?.authorID)
        try LedgerValidation.validate(decoded)
        XCTAssertEqual(decoded.transactions.first?.amountCents,10000)
    }
    func testLocalCopyRemapsAllRelationshipsIncludingRefundAndBudget() throws {
        var base = try fixture(); let expense = base.transactions[0]
        base.transactions.append(Transaction(ledgerID:base.ledger.id,kind:.refund,amountCents:1000,date:day,accountID:expense.accountID,originalExpenseID:expense.id))
        base.ledger.budgetRules = [.init(period:.month,effectiveFrom:day,limit:5000,categoryID:expense.categoryID)]
        let copy = try CloudWorkspace.localCopy(base,name:"保留副本")
        XCTAssertNotEqual(copy.ledger.id,base.ledger.id); XCTAssertNotEqual(copy.transactions[0].operationID,expense.operationID)
        XCTAssertEqual(copy.transactions[1].originalExpenseID,copy.transactions[0].id)
        XCTAssertEqual(copy.ledger.budgetRules?.first?.categoryID,copy.transactions[0].categoryID)
        try copy.validate()
    }
    func testDuplicateIDsAreRejectedBeforeMergeInsteadOfTrapping() throws {
        let base = try fixture(); var bad = base; bad.accounts.append(bad.accounts[0])
        XCTAssertThrowsError(try CloudLedgerMerge.merge(base:base,local:bad,remote:base))
        var names = base
        let leaf = try XCTUnwrap(names.categories.firstIndex { $0.isLeaf })
        names.categories[leaf].name = "COFFEE"
        var duplicate = names.categories[leaf]; duplicate.id = .new(); duplicate.name = "coffee"
        names.categories.append(duplicate)
        XCTAssertThrowsError(try names.validate())
    }
    func testFiveHundredEntriesOverFiveYearsMergeWithIndependentOracle() throws {
        let base = try fixture(); var a = base; var b = base
        a.transactions.removeAll(); b.transactions.removeAll()
        var total: Int64 = 0
        for i in 0..<500 {
            var t = base.transactions[0]; t.id = .new(); t.operationID = "cloud-stress-\(i)"; t.amountCents = Int64(i + 1)
            t.date = Day(year:2022 + i / 100,month:(i % 12) + 1,day:1)
            // The fixture account starts later; use a legitimate historical starting point.
            if i % 2 == 0 { a.transactions.append(t) } else { b.transactions.append(t) }
            total += t.amountCents
        }
        var ancestor = base; ancestor.transactions.removeAll()
        ancestor.accounts = ancestor.accounts.map { var value = $0; value.startDay = Day(year:2022,month:1,day:1); return value }
        a.accounts = ancestor.accounts; b.accounts = ancestor.accounts
        let result = try CloudLedgerMerge.merge(base:ancestor,local:a,remote:b)
        XCTAssertTrue(result.conflicts.isEmpty); XCTAssertEqual(result.snapshot.transactions.count,500)
        XCTAssertEqual(result.snapshot.transactions.reduce(0) { $0 + $1.amountCents },total)
        XCTAssertEqual(total,125250)
        XCTAssertEqual(Set(result.snapshot.transactions.map { $0.date.year }),[2022,2023,2024,2025,2026])
    }
}
