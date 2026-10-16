import XCTest
import YujiCore
#if canImport(YujiAppState)
@testable import YujiAppState
#else
@testable import Yuji
#endif

@MainActor
final class RecordSupportInvitationTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("yuji-invitation-test-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testExactly100UniqueCreationsAndOneConsumptionSurviveRestart() throws {
        let url = try directory()
        let gate = RecordSupportInvitation(directory: url)
        for index in 0..<99 { gate.recordCreated("record-\(index)") }
        gate.recordCreated("record-1")
        XCTAssertEqual(gate.count, 99); XCTAssertFalse(gate.eligible)
        let restarted = RecordSupportInvitation(directory: url)
        XCTAssertEqual(restarted.count, 99)
        restarted.recordCreated("record-99")
        XCTAssertTrue(restarted.eligible)
        XCTAssertTrue(restarted.consume())
        XCTAssertFalse(restarted.consume())
        let shown = RecordSupportInvitation(directory: url)
        for index in 100..<500 { shown.recordCreated("record-\(index)") }
        XCTAssertEqual(shown.count, 100); XCTAssertFalse(shown.eligible)
        XCTAssertFalse(shown.consume())
    }

    func testThresholdWaitsUntilSafePresentationAndDoesNotRequireAnotherRecord() throws {
        let url = try directory()
        let gate = RecordSupportInvitation(directory: url)
        for index in 0..<150 { gate.recordCreated("record-\(index)") }
        XCTAssertTrue(gate.eligible); XCTAssertEqual(gate.count, 100)
        XCTAssertTrue(RecordSupportInvitation(directory: url).eligible)
    }

    func testCorruptAndForeignJournalsStayUntouchedAndNeverInvite() throws {
        let url = try directory()
        let file = url.appendingPathComponent("record-invitation.json")
        let corrupt = Data("{broken".utf8)
        try corrupt.write(to: file)
        let gate = RecordSupportInvitation(directory: url)
        gate.recordCreated("new")
        XCTAssertNotNil(gate.issue); XCTAssertFalse(gate.consume())
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
        try FileManager.default.removeItem(at: file)
        RecordSupportInvitation(directory: url, scope: "another-app").recordCreated("new")
        let bytes = try Data(contentsOf: file)
        let wrongScope = RecordSupportInvitation(directory: url)
        XCTAssertNotNil(wrongScope.issue); XCTAssertFalse(wrongScope.eligible)
        wrongScope.recordCreated("another")
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testFailedConsumptionCannotShowOrResetPersistedCount() throws {
        let url = try directory()
        let original = RecordSupportInvitation(directory: url)
        for index in 0..<100 { original.recordCreated("record-\(index)") }
        let bytes = try Data(contentsOf: url.appendingPathComponent("record-invitation.json"))
        let blocked = RecordSupportInvitation(directory: url, write: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        XCTAssertFalse(blocked.consume()); XCTAssertNotNil(blocked.issue); XCTAssertFalse(blocked.eligible)
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("record-invitation.json")), bytes)
        XCTAssertTrue(RecordSupportInvitation(directory: url).eligible)
    }

    func testLedgerCountsOnlySuccessfulLocalCreateCommands() throws {
        let repository = AppStateTests.Repository()
        let state = AppState(repository: repository)
        let ledger = try XCTUnwrap(state.activeLedger)
        let account = try XCTUnwrap(state.store.accounts(in: ledger.id).first)
        let category = try XCTUnwrap(state.store.categories(in: ledger.id, kind: .expense).first(where: { $0.isLeaf }))
        let secondAccount = try state.store.createAccount(ledgerID: ledger.id, name: "转入", startDay: state.today)
        var created: [EntityID] = []
        state.onRecordCreated = { id in
            XCTAssertTrue(repository.saved?.transactions.contains(where: { $0.id == id }) == true)
            created.append(id)
        }
        func expense() -> Bool {
            state.addExpense(expression: "10", date: state.today, accountID: account.id,
                             categoryID: category.id, tagIDs: [], note: "", ledgerID: ledger.id,
                             kind: .expense, amountCents: 1_000)
        }
        repository.fails = true
        XCTAssertFalse(expense()); XCTAssertTrue(created.isEmpty)
        repository.fails = false
        XCTAssertTrue(expense()); XCTAssertEqual(created.count, 1)
        let expenseID = try XCTUnwrap(created.first)
        XCTAssertTrue(state.update(expenseID) { $0.note = "编辑不计数" })
        XCTAssertTrue(state.addRefund(amountCents: 100, date: state.today, accountID: account.id,
                                      original: expenseID, note: "", ledgerID: ledger.id))
        XCTAssertTrue(state.addTransfer(amountCents: 100, date: state.today, from: account.id,
                                        to: secondAccount.id, note: "", ledgerID: ledger.id))
        XCTAssertEqual(created.count, 3)
        let refund = try XCTUnwrap(state.store.data.transactions.first(where: { $0.kind == .refund }))
        state.delete(refund); state.restore(refund.id)
        XCTAssertTrue(state.reloadFromDisk())
        XCTAssertTrue(state.perform { }) // restore/import/sync use generic commits, not create commands.
        XCTAssertEqual(created.count, 3)
    }

    func testInvitationWriteFailureNeverRollsBackSuccessfulAccounting() throws {
        let gate = RecordSupportInvitation(directory: try directory(), write: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        let repository = AppStateTests.Repository()
        let state = AppState(repository: repository)
        state.onRecordCreated = { gate.recordCreated($0.raw) }
        let ledger = try XCTUnwrap(state.activeLedger)
        let account = try XCTUnwrap(state.store.accounts(in: ledger.id).first)
        let category = try XCTUnwrap(state.store.categories(in: ledger.id, kind: .expense).first(where: { $0.isLeaf }))
        XCTAssertTrue(state.addExpense(expression: "10", date: state.today, accountID: account.id,
                                      categoryID: category.id, tagIDs: [], note: "", ledgerID: ledger.id,
                                      kind: .expense, amountCents: 1_000))
        XCTAssertEqual(repository.saved?.transactions.count, 1)
        XCTAssertNil(state.alertError); XCTAssertNotNil(gate.issue)
    }
}
