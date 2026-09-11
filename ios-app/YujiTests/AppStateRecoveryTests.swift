import XCTest
import YujiCore
#if canImport(YujiAppState)
@testable import YujiAppState
#else
@testable import Yuji
#endif

@MainActor
final class AppStateRecoveryTests: XCTestCase {
    private func withRepository(_ body: (JSONFileRepository) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(JSONFileRepository(url: folder.appendingPathComponent("ledger.json")))
    }
    func testUnreadableFileBlocksWritesAndCanBeRetriedWithoutRenamingIt() throws {
        try withRepository { repository in
            let original = Data("{unreadable original".utf8)
            try original.write(to: repository.url)
            let state = AppState(repository: repository)
            XCTAssertNotNil(state.storageFailure)
            var called = false
            XCTAssertFalse(state.perform { called = true })
            XCTAssertFalse(called)
            XCTAssertEqual(try Data(contentsOf: repository.url), original)
            XCTAssertNil(state.exportBackup())
            let repaired = LedgerStore(); try repaired.createLedger(name: "已修复")
            try repository.save(repaired.data)
            XCTAssertTrue(state.reloadFromDisk())
            XCTAssertNil(state.storageFailure)
            XCTAssertEqual(state.activeLedger?.name, "已修复")
        }
    }
    func testRecoveryPreservesUnreadableOriginalBeforeReplacingIt() throws {
        try withRepository { repository in
            let original = Data("invalid file must remain recoverable".utf8)
            try original.write(to: repository.url)
            let state = AppState(repository: repository)
            let source = LedgerStore(); try source.createLedger(name: "备份账本")
            let bytes = try BackupService.encode(BackupService.makeBackup(from: source))
            XCTAssertTrue(state.restoreBackup(bytes))
            XCTAssertNil(state.storageFailure)
            XCTAssertEqual(state.activeLedger?.name, "备份账本")
            let savedFiles = try FileManager.default.contentsOfDirectory(at: XCTUnwrap(state.recoveryDirectory), includingPropertiesForKeys: nil)
            XCTAssertTrue(try savedFiles.contains { try Data(contentsOf: $0) == original })
            XCTAssertEqual(try repository.load()?.ledgers.first?.name, "备份账本")
        }
    }
    func testTransferKeepsExpenseDraftAndThemeFailureRollsBack() throws {
        try withRepository { repository in
            let state = AppState(repository: repository)
            let ledger = try XCTUnwrap(state.activeLedger), accounts = state.store.accounts(in: ledger.id)
            let draft = Draft(ledgerID: ledger.id, expression: "42", date: state.today, accountID: accounts[0].id)
            XCTAssertTrue(state.saveDraft(draft))
            XCTAssertTrue(state.addTransfer(amountCents: 100, date: state.today, from: accounts[0].id, to: accounts[1].id, note: "", ledgerID: ledger.id))
            XCTAssertEqual(state.store.draft(for: ledger.id), draft)
            let folder = repository.url.deletingLastPathComponent()
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
            XCTAssertFalse(state.perform { state.store.updateSettings { $0.accentTheme = .rose } })
            XCTAssertEqual(state.store.data.settings.accentTheme, .sage)
            XCTAssertEqual(try repository.load()?.settings.accentTheme, .sage)
        }
    }
}
