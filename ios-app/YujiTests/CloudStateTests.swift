import XCTest
import YujiCore
#if canImport(YujiAppState)
@testable import YujiAppState
#else
@testable import Yuji
#endif

@MainActor final class CloudStateTests: XCTestCase {
    func testReadOnlyMemberCannotAdjustAccountStartForBackdatedEntry() async throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let (_, b, _, transport, _, _, id) = try await pair()
        transport.readOnly = true
        await b.synchronizeCloud()
        let account = try XCTUnwrap(b.store.accounts(in: id).first)
        let before = try encoder.encode(b.store.data)
        XCTAssertFalse(b.perform {
            try b.store.updateAccountOpening(account.id, openingCents: account.openingBalanceCents, startDay: Day(year: 2020, month: 1, day: 1))
        })
        XCTAssertEqual(try encoder.encode(b.store.data), before)
    }
    final class Repository: LedgerRepository {
        var data: LedgerData?; var fails = false
        func load() throws -> LedgerData? { data }
        func save(_ value: LedgerData) throws { if fails { throw CocoaError(.fileWriteOutOfSpace) }; data = value }
    }
    final class Server { var books: [String: CloudRemote] = [:]; var saves = 0 }
    final class Transport: CloudTransport {
        let configuration = CloudAddress(container: "iCloud.test", zoneName: "")
        var user: String; let server: Server; var offline = false; var revoked = false; var readOnly = false
        var afterSave: (() -> Void)?; var loseAcknowledgement = false; var forceConflictOnce = false
        var left = Set<String>()
        var accountUnavailable = false
        init(_ user: String, server: Server) { self.user = user; self.server = server }
        func accountID() async throws -> String { if accountUnavailable { throw CloudSyncError.offline }; if user.isEmpty { throw CloudSyncError.notSignedIn }; return user }
        func addresses() async throws -> [CloudAddress] {
            if offline { throw CloudSyncError.offline }
            return server.books.keys.filter { !left.contains($0) }.sorted().map { CloudAddress(container: configuration.container, scope: user == "a" ? .private : .shared, zoneName: $0, ownerName: user == "a" ? "__defaultOwner__" : "a") }
        }
        func fetch(_ address: CloudAddress) async throws -> CloudRemote? {
            if offline { throw CloudSyncError.offline }; if revoked { throw CloudSyncError.revoked }
            var value = server.books[address.zoneName]; value?.writable = !readOnly; return value
        }
        func save(_ value: CloudLedgerSnapshot, at address: CloudAddress, version: Data?) async throws -> CloudRemote {
            if offline { throw CloudSyncError.offline }; if revoked || readOnly { throw CloudSyncError.revoked }
            if forceConflictOnce { forceConflictOnce = false; throw CloudSyncError.conflict }
            guard server.books[address.zoneName]?.version == version else { throw CloudSyncError.conflict }
            let remote = CloudRemote(snapshot: value, version: Data(UUID().uuidString.utf8))
            server.books[address.zoneName] = remote; server.saves += 1
            let callback = afterSave; afterSave = nil; callback?()
            if loseAcknowledgement { loseAcknowledgement = false; throw CloudSyncError.offline }
            return remote
        }
        func leave(_ address: CloudAddress) async throws { if offline { throw CloudSyncError.offline }; left.insert(address.zoneName) }
    }
    let today = Day(year: 2026, month: 10, day: 8)
    func state(_ repository: Repository, _ transport: Transport) -> AppState {
        let value = AppState(repository: repository, clockDay: today); value.configureCloud(transport); return value
    }
    func pair() async throws -> (AppState, AppState, Transport, Transport, Repository, Repository, EntityID) {
        let server = Server(), ra = Repository(), rb = Repository()
        let ta = Transport("a", server: server), tb = Transport("b", server: server)
        let a = state(ra, ta), b = state(rb, tb); let id = try XCTUnwrap(a.activeLedger?.id)
        await a.enableCloud(for: id); await b.refreshCloudAccount(); await b.synchronizeCloud()
        XCTAssertNotNil(b.cloudLink(for: id)); return (a, b, ta, tb, ra, rb, id)
    }
    func record(_ state: AppState, _ ledger: EntityID, _ amount: Int64) throws {
        let account = try XCTUnwrap(state.store.accounts(in: ledger).first)
        let category = try XCTUnwrap(state.store.categories(in: ledger, kind: .expense).first { $0.isLeaf })
        XCTAssertTrue(state.perform { _ = try state.store.addTransaction(Transaction(ledgerID: ledger, kind: .expense, amountCents: amount, date: today, accountID: account.id, categoryID: category.id)) })
    }
    func testTwoDifferentAccountsOfflineEntriesConvergeAfterRelaunch() async throws {
        let (a,b,ta,tb,ra,rb,id) = try await pair()
        ta.offline = true; tb.offline = true
        try record(a,id,1200); try record(b,id,3400)
        await a.synchronizeCloud(); await b.synchronizeCloud()
        XCTAssertTrue(try XCTUnwrap(a.cloudLink(for:id)).pending)
        let relaunched = state(rb,tb); XCTAssertNil(relaunched.store.ledger(id))
        await relaunched.refreshCloudAccount(); XCTAssertEqual(relaunched.store.activeTransactions(in:id).count,1)
        ta.offline = false; tb.offline = false
        await a.synchronizeCloud(); await relaunched.synchronizeCloud(); await a.synchronizeCloud()
        XCTAssertEqual(a.store.activeTransactions(in:id).count,2)
        XCTAssertEqual(relaunched.store.activeTransactions(in:id).reduce(0) { $0 + $1.amountCents },4600)
        XCTAssertFalse(try XCTUnwrap(a.cloudLink(for:id)).pending)
        XCTAssertEqual(ra.data?.cloudLinks?.first?.base?.transactions.count,2)
        a.cloudDebounce?.cancel(); b.cloudDebounce?.cancel(); relaunched.cloudDebounce?.cancel()
    }
    func testSameAccountSecondDeviceDiscoversOnlySelectedBook() async throws {
        let (a,_,ta,_,_,_,id) = try await pair()
        XCTAssertTrue(a.createAndSwitchLedger(name:"不共享的私人账本"))
        let other = state(Repository(), Transport("a", server: ta.server))
        await other.refreshCloudAccount(); await other.synchronizeCloud()
        XCTAssertNotNil(other.store.ledger(id)); XCTAssertFalse(other.store.data.ledgers.contains { $0.name == "不共享的私人账本" })
    }
    func testRelaunchRestoresSelectedSharedBookOnlyAfterSameAccountIsVerified() async throws {
        let (_, b, _, tb, _, rb, id) = try await pair()
        XCTAssertTrue(b.switchLedger(id))
        let relaunched = state(rb, tb)
        XCTAssertNil(relaunched.store.ledger(id), "Unverified cloud identity must stay hidden")
        await relaunched.refreshCloudAccount()
        XCTAssertEqual(relaunched.activeLedgerID, id)
        XCTAssertEqual(rb.data?.activeLedgerID, id)
        b.cloudDebounce?.cancel(); relaunched.cloudDebounce?.cancel()
    }
    func testChoosingLocalBookDuringAccountCheckOverridesStartupSelection() async throws {
        let (_, b, _, tb, _, rb, id) = try await pair()
        XCTAssertTrue(b.switchLedger(id))
        let relaunched = state(rb, tb)
        let localID = try XCTUnwrap(relaunched.activeLedgerID)
        XCTAssertNotEqual(localID, id)
        XCTAssertTrue(relaunched.switchLedger(localID))
        await relaunched.refreshCloudAccount()
        XCTAssertEqual(relaunched.activeLedgerID, localID)
        b.cloudDebounce?.cancel(); relaunched.cloudDebounce?.cancel()
    }
    func testDiskRereadReactivatesSameAccountAndRestoresSelectedBook() async throws {
        let (_, b, _, _, _, rb, id) = try await pair()
        XCTAssertTrue(b.switchLedger(id))
        XCTAssertTrue(b.reloadFromDisk())
        XCTAssertNil(b.store.ledger(id))
        await b.refreshCloudAccount()
        XCTAssertNotNil(b.store.ledger(id))
        XCTAssertEqual(b.activeLedgerID, id)
        XCTAssertEqual(rb.data?.activeLedgerID, id)
        b.cloudDebounce?.cancel()
    }
    func testAccountSwitchHidesPreviousCacheAndDoesNotUploadIt() async throws {
        let (_,b,_,tb,_,rb,id) = try await pair()
        try record(b,id,2000); let saves = tb.server.saves
        b.invalidateCloudAccount(); tb.user = "c"
        // c has no membership; discovery must not see a/b's zones.
        tb.offline = true
        await b.refreshCloudAccount()
        // A cache is only activated by the exact persisted user identity.
        XCTAssertNil(b.store.ledger(id)); XCTAssertEqual(tb.server.saves,saves)
        XCTAssertEqual(rb.data?.cloudLinks?.first?.accountID,"b")
        XCTAssertEqual(rb.data?.cloudLinks?.first?.cached.transactions.count,1)
        b.cloudDebounce?.cancel()
    }
    func testReadOnlyGuardBlocksAllBusinessWritesButAllowsPersonalDraft() async throws {
        let (_,b,_,tb,_,_,id) = try await pair(); tb.readOnly = true; await b.synchronizeCloud()
        XCTAssertFalse(b.canEditLedger(id))
        XCTAssertFalse(b.perform { try b.store.renameLedger(id,name:"偷偷改名") })
        XCTAssertNotEqual(b.store.ledger(id)?.name,"偷偷改名")
        XCTAssertTrue(b.saveDraft(Draft(ledgerID:id,expression:"12",date:today)))
        b.cloudDebounce?.cancel()
    }
    func testLostAcknowledgementRetryDoesNotDuplicateTransaction() async throws {
        let (a,_,ta,_,_,_,id) = try await pair(); try record(a,id,1234)
        ta.loseAcknowledgement = true; await a.synchronizeCloud()
        XCTAssertTrue(try XCTUnwrap(a.cloudLink(for:id)).pending)
        await a.synchronizeCloud()
        XCTAssertEqual(ta.server.books.values.first?.snapshot.transactions.count,1)
        XCTAssertFalse(try XCTUnwrap(a.cloudLink(for:id)).pending); a.cloudDebounce?.cancel()
    }
    func testCompareAndSwapRetryAndInFlightLocalWriteArePreserved() async throws {
        let (a,_,ta,_,_,_,id) = try await pair(); try record(a,id,1000)
        ta.forceConflictOnce = true
        ta.afterSave = { try? self.record(a,id,2000) }
        await a.synchronizeCloud()
        XCTAssertEqual(a.store.activeTransactions(in:id).count,2)
        XCTAssertTrue(try XCTUnwrap(a.cloudLink(for:id)).pending)
        await a.synchronizeCloud()
        XCTAssertEqual(ta.server.books.values.first?.snapshot.transactions.count,2); a.cloudDebounce?.cancel()
    }
    func testConflictPersistsAndResolutionKeepsBothVersions() async throws {
        let (a,b,_,_,_,rb,id) = try await pair(); try record(a,id,1000); await a.synchronizeCloud(); await b.synchronizeCloud()
        let transaction = try XCTUnwrap(a.store.activeTransactions(in:id).first)
        XCTAssertTrue(a.perform { _ = try a.store.updateTransaction(transaction.id) { $0.amountCents = 2000 } })
        XCTAssertTrue(b.perform { _ = try b.store.updateTransaction(transaction.id) { $0.amountCents = 3000 } })
        await a.synchronizeCloud(); await b.synchronizeCloud()
        XCTAssertNotNil(b.cloudLink(for:id)?.incoming); XCTAssertNotNil(rb.data?.cloudLinks?.first?.incoming)
        XCTAssertTrue(b.resolveCloudConflict(id))
        XCTAssertEqual(b.store.transaction(transaction.id)?.amountCents,2000)
        let copy = try XCTUnwrap(b.store.data.ledgers.first { $0.name.hasSuffix("（未同步副本）") })
        XCTAssertEqual(b.store.activeTransactions(in:copy.id).first?.amountCents,3000)
        XCTAssertNil(b.cloudLink(for:copy.id)); a.cloudDebounce?.cancel(); b.cloudDebounce?.cancel()
    }
    func testRevocationFreezesPendingWorkAndPreservesLocalCopy() async throws {
        let (_,b,_,tb,_,_,id) = try await pair(); try record(b,id,1200); tb.revoked = true
        await b.synchronizeCloud(); XCTAssertFalse(b.canEditLedger(id)); XCTAssertTrue(try XCTUnwrap(b.cloudLink(for:id)).pending)
        XCTAssertTrue(b.preserveCloudCopy(id)); XCTAssertEqual(b.store.activeTransactions(in:try XCTUnwrap(b.activeLedger?.id)).count,1)
        b.cloudDebounce?.cancel()
    }
    func testDiskFailureDoesNotAdvanceAncestorOrLoseOutbox() async throws {
        let (a,_,ta,_,ra,_,id) = try await pair(); try record(a,id,1000)
        let before = try XCTUnwrap(a.cloudLink(for:id)?.base).encoded()
        ta.afterSave = { ra.fails = true }
        await a.synchronizeCloud()
        XCTAssertEqual(try a.cloudLink(for:id)?.base?.encoded(),before)
        XCTAssertTrue(try XCTUnwrap(a.cloudLink(for:id)).pending)
        ra.fails = false; await a.synchronizeCloud(); XCTAssertFalse(try XCTUnwrap(a.cloudLink(for:id)).pending)
        a.cloudDebounce?.cancel()
    }
    func testOldAccountResponseCannotBeInstalledAfterIdentityChanges() async throws {
        let (a,_,ta,_,_,_,id) = try await pair(); try record(a,id,1000)
        ta.afterSave = { a.invalidateCloudAccount() }
        await a.synchronizeCloud()
        XCTAssertNil(a.cloudAccountID); XCTAssertNil(a.store.ledger(id)); XCTAssertNotNil(a.store.data.cloudLinks?.first?.cached)
        a.cloudDebounce?.cancel()
    }
    func testPortableBackupDoesNotReactivateCloudBindingsOrExportOtherAccountCache() async throws {
        let (a,_,_,_,_,_,id) = try await pair(); try record(a,id,1000)
        let backup = try BackupService.makeBackup(from:a.store)
        XCTAssertNil(backup.data.cloudLinks)
        let restored = try BackupService.validate(backup:backup); XCTAssertNil(restored.cloudLinks)
        XCTAssertNotNil(restored.ledgers.first { $0.id == id }); a.cloudDebounce?.cancel()
    }
}

extension CloudStateTests {
    func testRestoredCloudSourceRequiresExplicitIndependentCopyWithoutOverwritingOriginal() async throws {
        let (a,_,ta,_,_,_,id) = try await pair(); try record(a,id,2500); await a.synchronizeCloud()
        let restored = try BackupService.validate(backup:BackupService.makeBackup(from:a.store))
        let repository = Repository(); repository.data = restored
        let local = state(repository,ta)
        let blocked = await local.enableCloud(for:id)
        guard case .requiresIndependentCopy = blocked else { return XCTFail("Original cloud identity must not be duplicated") }
        XCTAssertNil(local.cloudLink(for:id)); XCTAssertEqual(ta.server.books.count,1)
        let result = await local.enableCloud(for:id,independentCopy:true)
        guard case .enabled(let copyID) = result else { return XCTFail("Explicit copy should be enabled") }
        XCTAssertEqual(local.activeLedgerID, copyID)
        XCTAssertNotEqual(copyID,id); XCTAssertNotNil(local.store.ledger(id)); XCTAssertNil(local.cloudLink(for:id))
        XCTAssertEqual(local.store.activeTransactions(in:copyID).first?.amountCents,2500)
        XCTAssertEqual(Set(ta.server.books.values.map { $0.snapshot.ledger.id }).count,2)
        a.cloudDebounce?.cancel(); local.cloudDebounce?.cancel()
    }
    func testTwoAccountsOnOneDeviceKeepSeparatePendingCachesForTheSameSharedBook() async throws {
        let (a,_,ta,_,_,_,id) = try await pair()
        try record(a,id,1100); await a.synchronizeCloud()
        try record(a,id,2200); a.invalidateCloudAccount(); ta.user = "b"
        await a.refreshCloudAccount(); await a.synchronizeCloud()
        XCTAssertEqual(a.store.activeTransactions(in:id).map(\.amountCents),[1100])
        XCTAssertEqual(a.store.data.cloudLinks?.count,2)
        try record(a,id,3300); await a.synchronizeCloud()
        let ownerCache = try XCTUnwrap(a.store.data.cloudLinks?.first { $0.accountID == "a" })
        XCTAssertEqual(ownerCache.cached.transactions.reduce(0) { $0 + $1.amountCents },3300)
        a.invalidateCloudAccount(); ta.user = "a"; await a.refreshCloudAccount()
        XCTAssertEqual(a.store.activeTransactions(in:id).reduce(0) { $0 + $1.amountCents },3300)
        await a.synchronizeCloud()
        XCTAssertEqual(a.store.activeTransactions(in:id).count,3)
        XCTAssertEqual(a.store.activeTransactions(in:id).reduce(0) { $0 + $1.amountCents },6600)
        a.cloudDebounce?.cancel()
    }
    func testTemporarilyUnavailableAccountKeepsConfirmedCacheAndStopsNetworkWrites() async throws {
        let (a,_,ta,_,_,_,id) = try await pair(); let saves = ta.server.saves
        ta.accountUnavailable = true; await a.refreshCloudAccount()
        XCTAssertFalse(a.cloudAccountReady); XCTAssertNotNil(a.store.ledger(id))
        try record(a,id,1900); await a.synchronizeCloud()
        XCTAssertEqual(ta.server.saves,saves); XCTAssertTrue(a.cloudBookStatus(id).contains("暂不可用"))
        ta.accountUnavailable = false; await a.refreshCloudAccount(); await a.synchronizeCloud()
        XCTAssertFalse(try XCTUnwrap(a.cloudLink(for:id)).pending); a.cloudDebounce?.cancel()
    }
    func testLeaveSerializesAndPreservesUnsentCopyBeforeRemoteMembershipChanges() async throws {
        let (a,b,_,tb,_,rb,id) = try await pair(); try record(b,id,1700)
        b.cloudBusy = true
        let busyResult = await b.leaveCloudBook(id); XCTAssertFalse(busyResult)
        XCTAssertTrue(tb.left.isEmpty); b.cloudBusy = false
        rb.fails = true
        let diskResult = await b.leaveCloudBook(id); XCTAssertFalse(diskResult)
        XCTAssertTrue(tb.left.isEmpty); rb.fails = false
        tb.offline = true
        let offlineResult = await b.leaveCloudBook(id); XCTAssertFalse(offlineResult)
        XCTAssertNotNil(b.cloudLink(for:id)); XCTAssertNotNil(rb.data?.ledgers.first { $0.name.hasSuffix("（本地副本）") })
        tb.offline = false
        let success = await b.leaveCloudBook(id); XCTAssertTrue(success)
        XCTAssertNil(b.cloudLink(for:id)); XCTAssertNil(b.store.ledger(id)); XCTAssertNotNil(a.store.ledger(id))
        XCTAssertEqual(b.store.activeTransactions(in:try XCTUnwrap(b.activeLedger?.id)).first?.amountCents,1700)
        await b.synchronizeCloud(); XCTAssertNil(b.store.ledger(id))
        a.cloudDebounce?.cancel(); b.cloudDebounce?.cancel()
    }
    func testPauseStopsAutomaticSyncButExplicitRefreshStillWorks() async throws {
        let (a,_,ta,_,_,_,id) = try await pair(); a.setCloudPaused(id,paused:true)
        XCTAssertTrue(a.cloudBookStatus(id).contains("暂停"))
        let count = ta.server.saves; try record(a,id,1000)
        await a.synchronizeCloud(); XCTAssertEqual(ta.server.saves,count)
        await a.synchronizeCloud(forceLedgerID:id); XCTAssertEqual(ta.server.saves,count + 1)
        ta.offline = true; await a.synchronizeCloud(forceLedgerID:id)
        XCTAssertTrue(a.cloudBookStatus(id).contains("需要处理")); XCTAssertNotNil(a.cloudLink(for:id)?.issue)
        XCTAssertTrue(try XCTUnwrap(a.cloudLink(for:id)).paused); a.cloudDebounce?.cancel()
    }
    func testRemoteDeletionKeepsStaleDraftAndCopyPreservesItsText() async throws {
        let (a,b,_,_,_,_,id) = try await pair()
        let unused = try XCTUnwrap(b.store.categories(in:id,kind:.expense).first { $0.isLeaf })
        XCTAssertTrue(b.saveDraft(Draft(ledgerID:id,expression:"123",date:today,categoryID:unused.id,note:"尚未保存的文字")))
        XCTAssertTrue(a.perform { try a.store.deleteCategory(unused.id) }); await a.synchronizeCloud(); await b.synchronizeCloud()
        XCTAssertNotNil(b.cloudLink(for:id)?.unresolvedDraft)
        XCTAssertTrue(b.preserveCloudCopy(id))
        let draft = try XCTUnwrap(b.store.draft(for:try XCTUnwrap(b.activeLedger?.id)))
        XCTAssertEqual(draft.expression,"123"); XCTAssertEqual(draft.note,"尚未保存的文字")
        XCTAssertNil(draft.categoryID); a.cloudDebounce?.cancel(); b.cloudDebounce?.cancel()
    }
}
