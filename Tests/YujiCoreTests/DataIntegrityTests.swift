import XCTest
@testable import YujiCore

final class DataIntegrityTests: XCTestCase {
    private let day = Day(year: 2026, month: 9, day: 10)
    private func sample() throws -> LedgerStore {
        let store = LedgerStore()
        let ledger = try store.createLedger(name: "校验", startDay: day)
        try store.addTransaction(Transaction(ledgerID: ledger.id, kind: .expense, amountCents: 10_000, date: day,
            accountID: store.accounts(in: ledger.id)[0].id, categoryID: store.categories(in: ledger.id, kind: .expense).first(where: \.isLeaf)!.id))
        return store
    }
    private func rejected(_ change: (inout BackupService.BackupFile) -> Void, file: StaticString = #filePath, line: UInt = #line) throws {
        var backup = try BackupService.makeBackup(from: sample())
        change(&backup)
        XCTAssertThrowsError(try BackupService.validate(backup: backup), file: file, line: line)
    }
    func testBackupRejectsDuplicateIdentityAndOperationEvenWithMatchingCounts() throws {
        try rejected { b in b.data.accounts.append(b.data.accounts[0]); b.checksum.accountCount += 1 }
        try rejected { b in
            var transaction = b.data.transactions[0]; transaction.id = .new()
            b.data.transactions.append(transaction)
            b.checksum.transactionCount += 1; b.checksum.activeTransactionCount += 1; b.checksum.sumExpenseCents += transaction.amountCents
        }
        try rejected { b in b.data.transactions[0].operationID = "" }
    }
    func testBackupRejectsCrossLedgerReferencesAndMalformedHierarchy() throws {
        try rejected { b in b.data.accounts[0].ledgerID = "missing" }
        try rejected { b in b.data.categories[0].parentID = b.data.categories[0].id }
        try rejected { b in b.data.activeLedgerID = "missing" }
        try rejected { b in b.data.transactions[0].categoryID = nil }
        try rejected { b in b.data.tags[0].parentID = "missing" }
        try rejected { b in b.data.accounts[0].name = " \n " }
        try rejected { b in b.data.categories[0].name = "" }
        try rejected { b in b.data.tags[0].name = " " }
    }
    func testBackupRejectsInvalidDateAndTrashChecksum() throws {
        try rejected { b in b.data.transactions[0].date = Day(year: 2026, month: 2, day: 30) }
        try rejected { b in b.data.accounts[0].startDay = Day(year: 2027, month: 1, day: 1) }
        try rejected { b in b.checksum.trashedTransactionCount = 1 }
    }
    func testArchivedHistoryStillBacksUpAndRefundRelationsAreChecked() throws {
        let store = try sample(), expense = try XCTUnwrap(store.data.transactions.first)
        let refund = try store.addTransaction(Transaction(ledgerID: expense.ledgerID, kind: .refund, amountCents: 2_000,
            date: day, accountID: expense.accountID, originalExpenseID: expense.id))
        try store.archiveAccount(expense.accountID, archived: true)
        try store.archiveCategory(try XCTUnwrap(expense.categoryID), archived: true)
        var backup = try BackupService.makeBackup(from: store)
        XCTAssertNoThrow(try BackupService.validate(backup: backup))
        backup.data.transactions[0].deletedAt = Date()
        backup.checksum.activeTransactionCount -= 1; backup.checksum.trashedTransactionCount += 1
        backup.checksum.sumExpenseCents = 0
        XCTAssertThrowsError(try BackupService.validate(backup: backup))
        XCTAssertEqual(refund.originalExpenseID, expense.id)
    }
    func testDomainRejectsDuplicateIDAndInvalidOpeningBalance() throws {
        let store = try sample()
        var duplicate = store.data.transactions[0]; duplicate.operationID = UUID().uuidString
        XCTAssertThrowsError(try store.addTransaction(duplicate))
        XCTAssertThrowsError(try store.createAccount(ledgerID: duplicate.ledgerID, name: "无效", openingBalanceCents: Int64.max, startDay: day))
        XCTAssertEqual(store.data.transactions.count, 1)
    }
    func testLastLedgerAndDraftAccountCannotBeRemoved() throws {
        let store = try sample(), expense = store.data.transactions[0]
        XCTAssertThrowsError(try store.archiveLedger(expense.ledgerID, archived: true))
        let unused = store.accounts(in: expense.ledgerID)[1]
        store.saveDraft(Draft(ledgerID: expense.ledgerID, date: day, accountID: unused.id))
        XCTAssertThrowsError(try store.deleteAccount(unused.id))
    }
    func testPurgeRequiresTrashAndProtectsAllRefundReferences() throws {
        let store = try sample(), expense = store.data.transactions[0]
        XCTAssertThrowsError(try store.purgeTransaction(expense.id))
        let refund = try store.addTransaction(Transaction(ledgerID: expense.ledgerID, kind: .refund, amountCents: 100,
            date: day, accountID: expense.accountID, originalExpenseID: expense.id))
        try store.deleteTransaction(refund.id); try store.deleteTransaction(expense.id)
        XCTAssertThrowsError(try store.purgeTransaction(expense.id))
        try store.purgeTransaction(refund.id); try store.purgeTransaction(expense.id)
        XCTAssertTrue(store.data.transactions.isEmpty)
        XCTAssertNoThrow(try BackupService.validate(backup: BackupService.makeBackup(from: store)))
    }
    func testTransferDoesNotEraseAnUnrelatedExpenseDraft() throws {
        // Covered at AppState level too; store draft identity is per ledger, not per entry point.
        let store = try sample(), expense = store.data.transactions[0]
        let draft = Draft(ledgerID: expense.ledgerID, expression: "42", date: day, accountID: expense.accountID)
        store.saveDraft(draft)
        try store.addTransaction(Transaction(ledgerID: expense.ledgerID, kind: .transfer, amountCents: 100,
            date: day, accountID: expense.accountID, transferToAccountID: store.accounts(in: expense.ledgerID)[1].id))
        XCTAssertEqual(store.draft(for: expense.ledgerID), draft)
    }
}
