import XCTest
import YujiCore
#if canImport(YujiAppState)
@testable import YujiAppState
#else
@testable import Yuji
#endif

@MainActor final class CloudPeopleStateTests: XCTestCase {
    final class Repository: LedgerRepository {
        var data: LedgerData?
        var fails = false
        func load() throws -> LedgerData? { data }
        func save(_ value: LedgerData) throws { if fails { throw CocoaError(.fileWriteOutOfSpace) }; data = value }
    }
    final class Server {
        var own: [String: CloudPerson] = [:]
        var members: [String: CloudPerson] = [:]
    }
    final class Transport: CloudTransport {
        let configuration = CloudAddress(container: "iCloud.test", zoneName: "")
        var supportsPeople: Bool { true }
        var user = "a"; var offline = false; var publishes = 0
        var failingZone: String?
        var afterLoad: (() -> Void)?; var afterSave: (() -> Void)?
        var duringLoad: (() async -> Void)?
        let server: Server
        init(_ server: Server) { self.server = server }
        func accountID() async throws -> String { user }
        func addresses() async throws -> [CloudAddress] { [] }
        func fetch(_ address: CloudAddress) async throws -> CloudRemote? { nil }
        func save(_ snapshot: CloudLedgerSnapshot, at address: CloudAddress, version: Data?) async throws -> CloudRemote { throw CloudSyncError.unavailable }
        func leave(_ address: CloudAddress) async throws {}
        func myPerson() async throws -> CloudPerson {
            if offline { throw CloudSyncError.offline }
            let result = server.own[user] ?? CloudPerson(accountID: user, cloudName: "云姓名", revision: "default")
            let suspended = duringLoad; duringLoad = nil; await suspended?()
            let callback = afterLoad; afterLoad = nil; callback?(); return result
        }
        func saveMyPerson(_ person: CloudPerson) async throws {
            if offline { throw CloudSyncError.offline }
            server.own[user] = person
            let callback = afterSave; afterSave = nil; callback?()
        }
        func people(at address: CloudAddress) async throws -> [CloudPerson] {
            if address.zoneName == failingZone { throw CloudSyncError.offline }
            return Array(server.members.values)
        }
        func publishMyPerson(_ person: CloudPerson, at address: CloudAddress) async throws { publishes += 1; server.members[user] = person }
    }
    let day = Day(year: 2026, month: 10, day: 15)
    func make(_ transport: Transport, repository: Repository = Repository(), writable: Bool = true) async throws -> AppState {
        let state = AppState(repository: repository, clockDay: day)
        state.configureCloud(transport); await state.refreshCloudAccount()
        let id = try XCTUnwrap(state.activeLedgerID)
        let snapshot = try CloudLedgerSnapshot(data: state.store.data, ledgerID: id)
        let address = CloudAddress(container: "iCloud.test", scope: .shared, zoneName: "yuji-book-test", ownerName: "owner")
        var data = state.store.data
        data.cloudLinks = [.init(accountID: transport.user, address: address, cached: snapshot, base: snapshot, writable: writable)]
        XCTAssertTrue(state.commitCloudData(data)); return state
    }
    func testGlobalNicknameCrossDeviceAndSharedResolutionReset() async throws {
        let server = Server()
        // Both devices use one private profile store; B reads the shared member projection.
        let first = Transport(server), second = Transport(server)
        let a = try await make(first), sameAccount = try await make(second)
        await a.synchronizePeople(force: true)
        XCTAssertEqual(a.myNicknameSummary, "云姓名")
        XCTAssertTrue(a.setMyNickname("  小余  ")); await a.synchronizePeople(force: true)
        await sameAccount.synchronizePeople(force: true)
        XCTAssertEqual(sameAccount.myNicknameSummary, "小余")
        let tb = Transport(server); tb.user = "b"
        let b = try await make(tb); await b.synchronizePeople(force: true)
        XCTAssertEqual(b.personName("a", ledgerID: try XCTUnwrap(b.activeLedgerID)), "小余")
        XCTAssertTrue(a.setMyNickname("")); await a.synchronizePeople(force: true)
        XCTAssertEqual(a.myNicknameSummary, "云姓名")
        XCTAssertNil(server.own["a"]?.nickname)
    }
    func testOfflinePendingDurableAndNoFinancialMutation() async throws {
        let transport = Transport(Server()), repository = Repository()
        let state = try await make(transport, repository: repository)
        let id = try XCTUnwrap(state.activeLedgerID)
        let before = try CloudLedgerSnapshot(data: state.store.data, ledgerID: id).encoded()
        transport.offline = true
        XCTAssertTrue(state.setMyNickname("离线昵称")); await state.synchronizePeople(force: true)
        XCTAssertTrue(try XCTUnwrap(repository.data?.cloudPeople?.own.first).pending)
        XCTAssertEqual(before, try CloudLedgerSnapshot(data: state.store.data, ledgerID: id).encoded())
        XCTAssertNotNil(state.cloudPeopleIssue)
        let relaunched = AppState(repository: repository, clockDay: day)
        relaunched.configureCloud(transport); await relaunched.refreshCloudAccount()
        transport.offline = false; await relaunched.synchronizePeople(force: true)
        XCTAssertEqual(relaunched.myNicknameSummary, "离线昵称")
        XCTAssertFalse(try XCTUnwrap(relaunched.myCloudPerson).pending)
    }
    func testReadOnlyNeverProjectsButPrivatePreferenceSaves() async throws {
        let transport = Transport(Server())
        let readOnly = try await make(transport, writable: false)
        XCTAssertTrue(readOnly.setMyNickname("只读成员")); await readOnly.synchronizePeople(force: true)
        XCTAssertEqual(transport.publishes, 0)
        XCTAssertEqual(transport.server.own["a"]?.nickname, "只读成员")
        XCTAssertTrue(readOnly.cloudPeopleIssue?.contains("只读") == true)
    }
    func testStaleLoadCannotOverwriteNewEditOrSwitchAccount() async throws {
        let transport = Transport(Server())
        let current = try await make(transport)
        transport.afterLoad = { XCTAssertTrue(current.setMyNickname("新昵称")) }
        await current.synchronizePeople(force: true)
        XCTAssertEqual(current.myNicknameSummary, "新昵称"); XCTAssertTrue(current.myCloudPerson?.pending == true)
        await current.synchronizePeople(force: true)
        transport.afterLoad = { current.invalidateCloudAccount() }
        await current.synchronizePeople(force: true)
        XCTAssertNil(current.cloudAccountID); XCTAssertEqual(current.myNicknameSummary, "未设置")
    }
    func testConcurrentNewEditDuringSaveRemainsPending() async throws {
        let transport = Transport(Server())
        let current = try await make(transport)
        XCTAssertTrue(current.setMyNickname("第一版"))
        transport.afterSave = { XCTAssertTrue(current.setMyNickname("第二版")) }
        await current.synchronizePeople(force: true)
        XCTAssertEqual(current.myNicknameSummary, "第二版"); XCTAssertTrue(current.myCloudPerson?.pending == true)
        await current.synchronizePeople(force: true)
        XCTAssertEqual(transport.server.own["a"]?.nickname, "第二版")
    }
    func testExplicitSaveWhileRefreshIsRunningGetsAnotherSyncPass() async throws {
        let transport = Transport(Server())
        let state = try await make(transport)
        transport.duringLoad = {
            XCTAssertTrue(state.setMyNickname("同步中修改"))
            await state.synchronizePeople(force: true)
        }
        await state.synchronizePeople(force: true)
        for _ in 0..<100 where state.myCloudPerson?.pending == true { await Task.yield() }
        XCTAssertEqual(transport.server.own["a"]?.nickname, "同步中修改")
        XCTAssertEqual(state.myCloudPerson?.pending, false)
    }
    func testPersistenceFailureDoesNotPublishName() async throws {
        let transport = Transport(Server()), repository = Repository()
        let state = try await make(transport, repository: repository)
        let status = state.cloudStatus
        repository.fails = true
        XCTAssertFalse(state.setMyNickname("不应上传")); await state.synchronizePeople(force: true)
        XCTAssertNil(transport.server.own["a"]); XCTAssertEqual(transport.publishes, 0)
        XCTAssertEqual(state.cloudStatus, status)
    }
    func testOneUnavailableBookDoesNotBlockOtherBookNames() async throws {
        let transport = Transport(Server())
        let state = try await make(transport)
        let isolated = LedgerStore(data: state.store.data)
        let other = try isolated.createLedger(name: "第二本", startDay: day)
        var data = isolated.data
        var link = try XCTUnwrap(data.cloudLinks?.first)
        transport.failingZone = link.address.zoneName
        link.address.zoneName = "yuji-book-other"
        link.cached = try CloudLedgerSnapshot(data: data, ledgerID: other.id)
        link.base = link.cached
        data.cloudLinks?.append(link)
        XCTAssertTrue(state.commitCloudData(data))
        XCTAssertTrue(state.setMyNickname("继续同步")); await state.synchronizePeople(force: true)
        XCTAssertEqual(transport.publishes, 1)
        XCTAssertTrue(state.cloudPeopleIssue?.contains("部分账本") == true)
        XCTAssertEqual(transport.server.own["a"]?.nickname, "继续同步")
    }
    func testUnnamedMembersHaveDifferentLabelsAndUnknownAuthorIsExplicit() async throws {
        let transport = Transport(Server())
        transport.server.members = ["b": CloudPerson(accountID: "b"), "c": CloudPerson(accountID: "c")]
        let state = try await make(transport)
        await state.synchronizePeople(force: true)
        let id = try XCTUnwrap(state.activeLedgerID)
        XCTAssertNotEqual(state.personName("b", ledgerID: id), state.personName("c", ledgerID: id))
        XCTAssertEqual(state.personName(nil, ledgerID: id), "未知记账人")
        XCTAssertEqual(state.personName("a", ledgerID: id), "云姓名")
    }
    func testCreatorRemainsImmutableAndLegacyUnknownStaysUnknown() async throws {
        let transport = Transport(Server())
        let current = try await make(transport)
        let id = try XCTUnwrap(current.activeLedgerID), account = try XCTUnwrap(current.store.accounts(in: id).first)
        let category = try XCTUnwrap(current.store.categories(in: id, kind: .expense).first { $0.isLeaf })
        var previous = current.store.data
        var legacy = Transaction(ledgerID: id, kind: .expense, amountCents: 100, date: day, accountID: account.id, categoryID: category.id)
        var authored = legacy; authored.id = .new(); authored.authorID = "b"
        previous.transactions = [legacy, authored]
        var updated = previous
        updated.transactions[0].note = "编辑未知记录"; updated.transactions[1].authorID = "a"
        legacy.id = .new(); updated.transactions.append(legacy)
        current.stampCloudChanges(&updated, previous: previous)
        XCTAssertNil(updated.transactions[0].authorID)
        XCTAssertEqual(updated.transactions[0].lastEditorID, "a")
        XCTAssertEqual(updated.transactions[1].authorID, "b")
        XCTAssertEqual(updated.transactions[1].lastEditorID, "a")
        XCTAssertEqual(updated.transactions[2].authorID, "a")
    }
}
