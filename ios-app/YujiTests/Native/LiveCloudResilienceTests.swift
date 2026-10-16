import CloudKit
import CryptoKit
import XCTest
import YujiCore
@testable import Yuji

/// Explicit opt-in. Uses one real CloudKit identity and two independent disk clients.
/// Fault injection is labelled separately from real server compare-and-swap checks.
@MainActor
final class LiveCloudResilienceTests: XCTestCase {
    private final class Repository: LedgerRepository {
        let file: JSONFileRepository
        var rejectWrites = false
        init(_ url: URL) { file = JSONFileRepository(url: url) }
        func load() throws -> LedgerData? { try file.load() }
        func save(_ data: LedgerData) throws {
            if rejectWrites { throw CocoaError(.fileWriteOutOfSpace) }
            try file.save(data)
        }
    }

    /// Never enumerate another book, even when AppState performs automatic discovery.
    private final class ScopedTransport: CloudTransport {
        let live: CloudKitTransport
        let address: CloudAddress
        let account: String
        var offline = false
        var loseAcknowledgement = false
        var afterSave: (() -> Void)?
        var configuration: CloudAddress { live.configuration }
        init(_ live: CloudKitTransport, address: CloudAddress, account: String) {
            self.live = live; self.address = address; self.account = account
        }
        func check(_ target: CloudAddress) async throws {
            guard target == address, try await live.accountID() == account else {
                throw CloudSyncError.invalid("验收范围或真实账号发生变化，已停止")
            }
            if offline { throw CloudSyncError.offline }
        }
        func accountID() async throws -> String {
            let current = try await live.accountID()
            guard current == account else { throw CloudSyncError.notSignedIn }
            return current
        }
        func addresses() async throws -> [CloudAddress] { try await check(address); return [address] }
        func fetch(_ target: CloudAddress) async throws -> CloudRemote? {
            try await check(target); return try await live.fetch(target)
        }
        func save(_ snapshot: CloudLedgerSnapshot, at target: CloudAddress, version: Data?) async throws -> CloudRemote {
            try await check(target)
            let saved = try await live.save(snapshot, at: target, version: version)
            let callback = afterSave; afterSave = nil; callback?()
            if loseAcknowledgement { loseAcknowledgement = false; throw CloudSyncError.offline }
            return saved
        }
        func leave(_ target: CloudAddress) async throws {
            throw CloudSyncError.invalid("此用例不允许删除 zone 或改变成员关系")
        }
    }

    func testRealServerConflictAndDurableOutboxRecovery() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["YUJI_LIVE_RESILIENCE"] == "1")
        let run = try XCTUnwrap(env["YUJI_LIVE_RUN"])
        let uuid = try XCTUnwrap(UUID(uuidString: run))
        let expectedEnvironment = try XCTUnwrap(env["YUJI_LIVE_ENVIRONMENT"])
        try require(["Development", "Production"].contains(expectedEnvironment), "必须明确云环境")
        try require(env["YUJI_TEST_CLOUD_MODE"] == "signedOut", "宿主的自动同步必须关闭")
        try require(UUID(uuidString: env["YUJI_STRESS_SESSION"] ?? "") != nil, "宿主必须使用隔离目录")
        #if targetEnvironment(simulator)
        try require(expectedEnvironment == "Development", "模拟器不能证明 Production")
        #endif
        let live = try XCTUnwrap(CloudKitTransport.configured())
        try require(live.identifier == "iCloud.com.dmlayman.yuji" && live.environment == expectedEnvironment, "安装包云配置不符")
        let identity = try await live.accountID()
        let address = CloudAddress(container: live.identifier, environment: expectedEnvironment,
                                   zoneName: "yuji-book-" + uuid.uuidString)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yuji-resilience-" + uuid.uuidString)
        let resuming = FileManager.default.fileExists(atPath: directory.path)
        try require(!resuming || env["YUJI_LIVE_RESUME"] == "1", "已存在此批次；先回读，禁止盲目重跑")
        if !resuming { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false) }
        let normalURL = JSONFileRepository.defaultURL()
        let normalBefore = try fingerprint(normalURL)
        let today = Day(year: 2026, month: 10, day: 15)
        struct Manifest: Codable {
            let accountID: String
            let address: CloudAddress
            let initial: CloudLedgerSnapshot
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        observeErrors(live, in: directory)
        let initial: CloudLedgerSnapshot
        if resuming {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(Manifest.self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
            try require(manifest.accountID == identity && manifest.address == address, "恢复批次的身份不符")
            initial = manifest.initial
        } else {
            let store = LedgerStore()
            let ledger = try store.createLedger(name: "云恢复验收 " + String(run.prefix(8)), startDay: today)
            initial = try CloudLedgerSnapshot(data: store.data, ledgerID: ledger.id)
            try encoder.encode(Manifest(accountID: identity, address: address, initial: initial))
                .write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        }
        let ledger = initial.ledger
        let fetched = try await live.fetch(address)
        let first: CloudRemote
        if let fetched {
            try require(resuming && fetched.snapshot.matches(initial), "云端已有增量，禁止从头重跑")
            first = fetched
        } else { first = try await live.save(initial, at: address, version: nil) }
        let ta = ScopedTransport(live, address: address, account: identity)
        let tb = ScopedTransport(CloudKitTransport(identifier: live.identifier, environment: live.environment), address: address, account: identity)
        let ra = Repository(directory.appendingPathComponent("client-a.json"))
        let rb = Repository(directory.appendingPathComponent("client-b.json"))
        for repository in [ra, rb] {
            var data = initial.materialized()
            data.activeCloudAccountID = identity
            data.cloudLinks = [CloudLink(accountID: identity, address: address, cached: initial, base: initial, version: first.version)]
            try repository.save(data)
        }
        func client(_ repository: Repository, _ transport: ScopedTransport) async -> AppState {
            let state = AppState(repository: repository, clockDay: today)
            state.configureCloud(transport); await state.refreshCloudAccount(); return state
        }
        let a = await client(ra, ta), b = await client(rb, tb)
        var clients = [a, b]
        defer { clients.forEach { $0.cloudDebounce?.cancel() } }
        func add(_ state: AppState, cents: Int64) throws {
            let account = try XCTUnwrap(state.store.accounts(in: ledger.id).first)
            let category = try XCTUnwrap(state.store.categories(in: ledger.id, kind: .expense).first { $0.isLeaf })
            try require(state.perform {
                _ = try state.store.addTransaction(Transaction(ledgerID: ledger.id, kind: .expense, amountCents: cents,
                                                              date: today, accountID: account.id, categoryID: category.id))
            }, state.alertError ?? "本机保存失败")
            state.cloudDebounce?.cancel()
        }
        func sync(_ state: AppState) async { state.cloudDebounce?.cancel(); await state.synchronizeCloud(); state.cloudDebounce?.cancel() }
        func remote() async throws -> CloudRemote {
            let fetched = try await live.fetch(address)
            return try XCTUnwrap(fetched)
        }
        func settled(_ state: AppState) throws {
            let link = try XCTUnwrap(state.cloudLink(for: ledger.id))
            try require(!link.pending && link.issue == nil && link.incoming == nil, link.issue ?? state.cloudStatus)
        }

        // Real server merge after a durable offline outbox; the outage is client fault injection.
        tb.offline = true
        try add(a, cents: 1000); try add(b, cents: 2000)
        await sync(a); try settled(a); await sync(b)
        try require(b.cloudLink(for: ledger.id)?.pending == true, "断连修改未保留")
        let restartedB = await client(rb, tb); clients.append(restartedB)
        try require(restartedB.store.activeTransactions(in: ledger.id).count == 1, "重启丢失待同步数据")
        tb.offline = false; await sync(restartedB); await sync(a)
        try settled(a); try settled(restartedB)
        try require(a.store.activeTransactions(in: ledger.id).count == 2, "合并后记录数量不符")

        // Genuine CloudKit stale server change-tag rejection, without mocking the server.
        do {
            _ = try await live.save(initial, at: address, version: first.version)
            XCTFail("真实服务接受了陈旧版本"); return
        } catch { try require((error as? CloudSyncError) == .conflict, "真实服务未返回版本冲突：\(error)") }

        try add(a, cents: 3000); ta.loseAcknowledgement = true
        await sync(a)
        try require(a.cloudLink(for: ledger.id)?.pending == true, "丢失回执后提前清除了 outbox")
        try require(try await remote().snapshot.transactions.count == 3, "真实服务器未收到记录")
        await sync(a); try settled(a)
        try require(try await remote().snapshot.transactions.count == 3, "重试产生重复记录")

        // Concurrent edits against the same actual server version require a preserved local copy.
        await sync(restartedB)
        let transaction = try XCTUnwrap(a.store.activeTransactions(in: ledger.id).first { $0.amountCents == 1000 })
        try require(a.perform { _ = try a.store.updateTransaction(transaction.id) { $0.amountCents = 1100 } }, "A 编辑失败")
        a.cloudDebounce?.cancel()
        try require(restartedB.perform { _ = try restartedB.store.updateTransaction(transaction.id) { $0.amountCents = 1200 } }, "B 编辑失败")
        restartedB.cloudDebounce?.cancel()
        await sync(a); await sync(restartedB)
        try require(restartedB.cloudLink(for: ledger.id)?.incoming != nil, "同笔冲突被静默覆盖")
        let conflictB = await client(rb, tb); clients.append(conflictB)
        try require(conflictB.cloudLink(for: ledger.id)?.incoming != nil, "重启丢失冲突")
        try require(conflictB.resolveCloudConflict(ledger.id), "冲突解决失败")
        let copy = try XCTUnwrap(conflictB.store.data.ledgers.first { $0.name.hasSuffix("（未同步副本）") })
        try require(conflictB.store.activeTransactions(in: copy.id).contains { $0.amountCents == 1200 }, "本地冲突版本丢失")
        try require(conflictB.store.transaction(transaction.id)?.amountCents == 1100, "云端版本未采用")
        await sync(conflictB); try settled(conflictB)

        // Server accepts the write, local disk then fails: retry must reconcile without duplication.
        try add(a, cents: 4000)
        ta.afterSave = { ra.rejectWrites = true }
        await sync(a)
        try require(a.cloudLink(for: ledger.id)?.pending == true, "落盘失败丢失待同步标识")
        ra.rejectWrites = false
        await sync(a); try settled(a)
        let final = try await remote()
        try require(final.snapshot.transactions.count == 4, "最终记录数量不符")
        try require(final.snapshot.transactions.reduce(Int64(0)) { $0 + $1.amountCents } == 10100, "最终金额不符")
        try require(try fingerprint(normalURL) == normalBefore, "正常账本文件发生变化")
        let summary: [String: Any] = [
            "environment": live.environment, "run": run, "realCloudKitServer": true,
            "identityCount": 1, "independentDiskClients": 2, "staleChangeTagRejected": true,
            "injectedOfflineRestartMerge": true, "injectedLostAcknowledgementIdempotent": true,
            "realConcurrentEditConflictAndCopy": true, "injectedDiskFailureRecovery": true,
            "finalTransactionCount": 4, "finalExpenseCents": 10100, "normalFileUnchanged": true,
            "radioOfflineTested": false, "fixtureRetainedForExplicitCleanup": true
        ]
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("summary.json"), options: .atomic)
    }

    private func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CloudSyncError.invalid(message) }
    }

    private func observeErrors(_ transport: CloudKitTransport, in directory: URL) {
        #if DEBUG
        transport.errorObserver = { error in
            var current: NSError? = error as NSError
            var rows: [[String: Any]] = []
            for _ in 0..<5 {
                guard let value = current else { break }
                var row: [String: Any] = ["domain": value.domain, "code": value.code]
                if let url = value.userInfo[NSURLErrorFailingURLErrorKey] as? URL { row["host"] = url.host }
                rows.append(row)
                current = value.userInfo[NSUnderlyingErrorKey] as? NSError
            }
            // No descriptions, headers, full URLs, payloads, tokens or user identities.
            if let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: directory.appendingPathComponent("last-error-codes.json"), options: .atomic)
                print("LIVE_CLOUD_DIAGNOSTIC " + String(decoding: data, as: UTF8.self))
            }
        }
        #endif
    }

    private struct PairContext: Codable {
        var run: String
        var environment: String
        var ownerID: String
        var memberID: String
        var ownerAddress: CloudAddress
        var memberAddress: CloudAddress?
        var ledgerID: EntityID
        var invitation: URL
    }

    /// Phased real owner/member checks. The coordinator copies only this run's private
    /// context between the two authorized devices, never normal ledgers or credentials.
    func testPairedCloudPhase() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["YUJI_LIVE_PAIR"] == "1")
        let run = try XCTUnwrap(env["YUJI_LIVE_RUN"])
        let uuid = try XCTUnwrap(UUID(uuidString: run))
        let phase = try XCTUnwrap(env["YUJI_LIVE_PHASE"])
        let actor = try XCTUnwrap(env["YUJI_LIVE_ACTOR"])
        let environment = try XCTUnwrap(env["YUJI_LIVE_ENVIRONMENT"])
        try require(["A", "B"].contains(actor) && ["Development", "Production"].contains(environment), "验收角色或环境无效")
        try require(env["YUJI_TEST_CLOUD_MODE"] == "signedOut" && UUID(uuidString: env["YUJI_STRESS_SESSION"] ?? "") != nil, "宿主未隔离")
        #if targetEnvironment(simulator)
        try require(environment == "Development", "模拟器不能证明 Production")
        #endif
        let live = try XCTUnwrap(CloudKitTransport.configured())
        try require(live.identifier == "iCloud.com.dmlayman.yuji" && live.environment == environment, "实际云配置不符")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yuji-pair-\(uuid.uuidString)-\(actor)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        observeErrors(live, in: directory)
        let identity = try await live.accountID()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let normalURL = JSONFileRepository.defaultURL(), normalBefore = try fingerprint(JSONFileRepository.defaultURL())
        func summary(_ values: [String: Any]) throws {
            var output = values
            output["phase"] = phase; output["actor"] = actor; output["run"] = run; output["environment"] = environment
            try require(try fingerprint(normalURL) == normalBefore, "正常账本文件变化，停止验收")
            output["normalFileUnchanged"] = true
            try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("\(phase)-summary.json"), options: .atomic)
        }
        if phase == "identity" {
            try encoder.encode(["identity": identity, "environment": environment])
                .write(to: directory.appendingPathComponent("identity.json"), options: .atomic)
            try summary(["realIdentityRead": true]); return
        }
        let repository = Repository(directory.appendingPathComponent("workspace.json"))
        let today = Day(year: 2026, month: 10, day: 15)
        func saveWorkspace(_ remote: CloudRemote, address: CloudAddress) throws {
            var data = remote.snapshot.materialized(); data.activeCloudAccountID = identity
            data.cloudLinks = [CloudLink(accountID: identity, address: address, cached: remote.snapshot,
                                        base: remote.snapshot, version: remote.version, writable: remote.writable)]
            try repository.save(data)
        }
        var context: PairContext
        if phase == "invite" {
            try require(actor == "A" && (try repository.load()) == nil, "只允许新建拥有者验收 workspace")
            let member = try XCTUnwrap(env["YUJI_LIVE_PEER_ID"])
            try require(member.hasPrefix(live.identifier + "|" + environment + "|") && member != identity, "必须是同容器/环境的不同真实账号")
            let store = LedgerStore()
            let ledger = try store.createLedger(name: "双账号验收 " + String(run.prefix(8)), startDay: today)
            let snapshot = try CloudLedgerSnapshot(data: store.data, ledgerID: ledger.id)
            let address = CloudAddress(container: live.identifier, environment: environment, zoneName: "yuji-book-" + uuid.uuidString)
            try encoder.encode(snapshot).write(to: directory.appendingPathComponent("initial.json"), options: .atomic)
            let existing = try await live.fetch(address)
            try require(existing == nil, "已存在验收 zone，不重复创建")
            let remote = try await live.save(snapshot, at: address, version: nil)
            let link = CloudLink(accountID: identity, address: address, cached: snapshot, base: snapshot, version: remote.version)
            let share = try await live.prepareShare(link)
            let participant = try await live.container.shareParticipant(forUserRecordID: CKRecord.ID(recordName: String(member.split(separator: "|").last!)))
            participant.permission = .readWrite; share.addParticipant(participant)
            let savedRecord = try await live.container.privateCloudDatabase.save(share)
            let saved = try XCTUnwrap(savedRecord as? CKShare)
            try require(saved.publicPermission == .none && saved.participants.count == 2, "邀请范围不符")
            context = PairContext(run: run, environment: environment, ownerID: identity, memberID: member,
                                  ownerAddress: address, ledgerID: ledger.id, invitation: try XCTUnwrap(saved.url))
            try saveWorkspace(remote, address: address)
        } else {
            if let input = env["YUJI_LIVE_PAIR_CONTEXT"] {
                context = try decoder.decode(PairContext.self, from: Data(input.utf8))
            } else {
                context = try decoder.decode(PairContext.self, from: Data(contentsOf: directory.appendingPathComponent("context.json")))
            }
        }
        try require(context.run == run && context.environment == environment && context.ownerID != context.memberID &&
                    context.ownerAddress == CloudAddress(container: live.identifier, environment: environment, zoneName: "yuji-book-" + uuid.uuidString) &&
                    identity == (actor == "A" ? context.ownerID : context.memberID), "验收上下文/账号不匹配")
        if phase == "accept" {
            try require(actor == "B", "只允许成员接受")
            let metadata = try await live.container.shareMetadata(for: context.invitation)
            try require(metadata.containerIdentifier == live.identifier && metadata.share.recordID.zoneID.zoneName == context.ownerAddress.zoneName, "邀请目标不符")
            try await live.accept(metadata)
            context.memberAddress = CloudAddress(container: live.identifier, environment: environment, scope: .shared,
                                                 zoneName: metadata.share.recordID.zoneID.zoneName, ownerName: metadata.share.recordID.zoneID.ownerName)
            let fetched = try await live.fetch(try XCTUnwrap(context.memberAddress))
            let remote = try XCTUnwrap(fetched)
            try require(remote.snapshot.ledger.id == context.ledgerID, "成员读到其他账本")
            // Re-invitation must not discard a previously durable member outbox.
            if try repository.load() == nil { try saveWorkspace(remote, address: try XCTUnwrap(context.memberAddress)) }
        }
        try encoder.encode(context).write(to: directory.appendingPathComponent("context.json"), options: .atomic)
        if ["invite", "accept"].contains(phase) { try summary(["privateShare": true, "distinctAccounts": true]); return }

        let address = actor == "A" ? context.ownerAddress : try XCTUnwrap(context.memberAddress)
        let transport = ScopedTransport(live, address: address, account: identity)
        let state = AppState(repository: repository, clockDay: today)
        state.configureCloud(transport); await state.refreshCloudAccount()
        defer { state.cloudDebounce?.cancel() }
        try require(state.store.ledger(context.ledgerID)?.name == "双账号验收 " + String(run.prefix(8)), "不是此批次验收账本")
        func sync() async { state.cloudDebounce?.cancel(); await state.synchronizeCloud(); state.cloudDebounce?.cancel() }
        func settled() throws {
            let link = try XCTUnwrap(state.cloudLink(for: context.ledgerID))
            try require(!link.pending && link.incoming == nil && link.issue == nil, link.issue ?? state.cloudStatus)
        }
        switch phase {
        case "offlineAdd", "offlineAddBeforeRevoke", "radioOfflineAdd":
            if phase == "radioOfflineAdd" {
                try require(env["YUJI_RADIO_OFFLINE"] == "CONFIRMED_BY_HUMAN", "尚未由本人关闭无线网络")
                try settled()
            } else {
                await sync(); try settled(); transport.offline = true
            }
            let account = try XCTUnwrap(state.store.accounts(in: context.ledgerID).first)
            let category = try XCTUnwrap(state.store.categories(in: context.ledgerID, kind: .expense).first { $0.isLeaf })
            let operation = run + "-" + actor + "-" + phase
            try require(!state.store.data.appliedOperations.contains(operation), "此阶段已执行，禁止重复记账")
            try require(state.perform {
                _ = try state.store.addTransaction(Transaction(ledgerID: context.ledgerID, operationID: operation, kind: .expense,
                                                              amountCents: phase == "offlineAdd" ? (actor == "A" ? 1000 : 2000) : 3000,
                                                              date: today, accountID: account.id, categoryID: category.id, note: "pair-" + actor))
            }, "离线本机保存失败")
            await sync()
            try require(state.cloudLink(for: context.ledgerID)?.pending == true, "缺少离线 outbox")
            if phase == "radioOfflineAdd" { try require(state.cloudLink(for: context.ledgerID)?.issue != nil, "无线关闭后仍收到云端成功，需检查实际网络") }
            let restored = AppState(repository: repository, clockDay: today)
            restored.configureCloud(transport); await restored.refreshCloudAccount(); defer { restored.cloudDebounce?.cancel() }
            try require(restored.cloudLink(for: context.ledgerID)?.pending == true && restored.store.data.appliedOperations.contains(operation), "重启未保留离线记录")
        case "sync", "verifyMerged":
            await sync(); try settled()
            if phase == "verifyMerged" {
                let records = state.store.activeTransactions(in: context.ledgerID)
                try require(records.count == 2 && records.reduce(Int64(0)) { $0 + $1.amountCents } == 3000, "双账号离线合并结果不符")
            }
        case "offlineEdit":
            await sync(); try settled(); transport.offline = true
            let transaction = try XCTUnwrap(state.store.activeTransactions(in: context.ledgerID).first { $0.note == "pair-A" })
            try require(state.perform { _ = try state.store.updateTransaction(transaction.id) { $0.amountCents = actor == "A" ? 1100 : 1200 } }, "编辑失败")
            state.cloudDebounce?.cancel()
        case "expectConflict":
            await sync()
            try require(state.cloudLink(for: context.ledgerID)?.incoming != nil, "真实双账号冲突未保留")
            let restored = AppState(repository: repository, clockDay: today)
            restored.configureCloud(transport); await restored.refreshCloudAccount(); defer { restored.cloudDebounce?.cancel() }
            try require(restored.cloudLink(for: context.ledgerID)?.incoming != nil, "重启丢失冲突")
        case "resolve":
            try require(state.cloudLink(for: context.ledgerID)?.incoming != nil && state.resolveCloudConflict(context.ledgerID), "没有待解决冲突")
            try require(state.store.data.ledgers.contains { $0.name.hasSuffix("（未同步副本）") }, "缺少未同步副本")
            await sync(); try settled()
            try require(state.store.activeTransactions(in: context.ledgerID).reduce(Int64(0)) { $0 + $1.amountCents } == 3100, "采用云端版本后的金额不符")
        case "readOnly", "readWrite", "revoke", "reinvite", "stopSharing":
            try require(actor == "A", "只有拥有者调整共享")
            let share = try await live.share(at: context.ownerAddress)
            try require(share.publicPermission == .none && share.currentUserParticipant?.role == .owner, "不是私有拥有者共享")
            let recordName = String(context.memberID.split(separator: "|").last!)
            if phase == "stopSharing" {
                _ = try await live.container.privateCloudDatabase.deleteRecord(withID: share.recordID)
            } else {
                if phase == "reinvite" {
                    try require(share.participants.count == 1, "仍有成员，不重复邀请")
                    let participant = try await live.container.shareParticipant(forUserRecordID: CKRecord.ID(recordName: recordName))
                    participant.permission = .readWrite; share.addParticipant(participant)
                } else {
                    let participant = try XCTUnwrap(share.participants.first { $0.userIdentity.userRecordID?.recordName == recordName })
                    if phase == "revoke" { share.removeParticipant(participant) }
                    else { participant.permission = phase == "readOnly" ? .readOnly : .readWrite }
                }
                _ = try await live.container.privateCloudDatabase.save(share)
                let readback = try await live.share(at: context.ownerAddress)
                let member = readback.participants.first { $0.userIdentity.userRecordID?.recordName == recordName }
                if phase == "revoke" { try require(member == nil, "撤销未生效") }
                else { try require(member?.permission == (phase == "readOnly" ? .readOnly : .readWrite), "权限回读不符") }
            }
        case "verifyReadOnly":
            await sync(); try settled()
            try require(!state.canEditLedger(context.ledgerID), "只读仍可编辑")
            let before = try encoder.encode(state.store.data)
            try require(!state.perform { try state.store.renameLedger(context.ledgerID, name: "不应生效") }, "只读写入未拦截")
            try require(try encoder.encode(state.store.data) == before, "只读拦截改变数据")
        case "verifyReadWrite":
            await sync(); try settled(); try require(state.canEditLedger(context.ledgerID), "编辑权限未恢复")
        case "verifyRevoked":
            await sync()
            try require(!state.canEditLedger(context.ledgerID) && state.cloudLink(for: context.ledgerID)?.issue != nil, "撤销未冻结")
            try require(state.preserveCloudCopy(context.ledgerID), "撤销后未保留独立副本")
        case "leave":
            try require(actor == "B", "拥有者不能退出成员")
            let result = await state.leaveCloudBook(context.ledgerID)
            try require(result && state.cloudLink(for: context.ledgerID) == nil, "真实成员退出失败")
            try require(state.store.data.ledgers.contains { $0.name.hasSuffix("（本地副本）") }, "退出缺少本地副本")
        default: throw CloudSyncError.invalid("未知验收阶段，未执行")
        }
        let link = state.cloudLink(for: context.ledgerID)
        let records = state.store.activeTransactions(in: context.ledgerID)
        try summary(["completed": true, "distinctAccounts": true, "records": records.count,
                     "expenseCents": records.reduce(Int64(0)) { $0 + $1.amountCents },
                     "pending": link?.pending ?? false, "conflict": link?.incoming != nil,
                     "writable": link?.writable ?? false, "injectedOffline": phase.hasPrefix("offline"),
                     "radioOfflineTested": phase == "radioOfflineAdd"])
    }
    private struct DistributionFixture: Codable {
        let run: String
        let ownerID: String
        let memberID: String
        let ownerAddress: CloudAddress
        let ledgerID: EntityID
        let originalTransactionID: EntityID
        let invitation: URL?
    }

    /// A real Production member of the exact fixture created by the installed
    /// TestFlight app. Never runs on the owner's phone or discovers other books.
    func testExistingTestFlightSharePhase() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["YUJI_TESTFLIGHT_PEER"] == "1")
        #if !targetEnvironment(macCatalyst)
        throw XCTSkip("This phase belongs only to the authorized Mac peer")
        #endif
        try require(env["YUJI_TEST_CLOUD_MODE"] == "signedOut" && UUID(uuidString: env["YUJI_STRESS_SESSION"] ?? "") != nil,
                    "宿主未隔离")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let fixture = try decoder.decode(DistributionFixture.self, from: Data(try XCTUnwrap(env["YUJI_TESTFLIGHT_CONTEXT"]).utf8))
        let run = try XCTUnwrap(UUID(uuidString: fixture.run))
        let name = "QA 1015 " + fixture.run.prefix(8)
        let phase = try XCTUnwrap(env["YUJI_TESTFLIGHT_PHASE"])
        try require(["probe", "accept", "sync", "add", "edit", "readOnly", "readWrite", "revoked"].contains(phase), "未知阶段")
        let live = try XCTUnwrap(CloudKitTransport.configured())
        try require(live.identifier == fixture.ownerAddress.container && live.environment == "Production" &&
                    fixture.ownerAddress.environment == "Production" && fixture.ownerAddress.scope == .private &&
                    fixture.ownerAddress.zoneName.hasPrefix("yuji-book-") && fixture.ownerID != fixture.memberID,
                    "不是指定 Production 验收范围")
        let identity = try await live.accountID()
        try require(identity == fixture.memberID && identity.hasPrefix(live.identifier + "|Production|"), "B 账号不符")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yuji-distribution-peer-" + run.uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        observeErrors(live, in: directory)
        let normal = JSONFileRepository.defaultURL(), before = try fingerprint(JSONFileRepository.defaultURL())
        let repository = Repository(directory.appendingPathComponent("workspace.json"))
        let addressFile = directory.appendingPathComponent("member-address.json")
        func preserveVerifiedReadback(_ remote: CloudRemote, at address: CloudAddress) throws {
            try require(remote.snapshot.ledger.id == fixture.ledgerID && remote.snapshot.ledger.name == name, "云端账本不符")
            if try repository.load() == nil {
                var data = remote.snapshot.materialized(); data.activeCloudAccountID = identity
                var link = CloudLink(accountID: identity, address: address, cached: remote.snapshot,
                                     base: remote.snapshot, version: remote.version, writable: remote.writable)
                link.lastSync = Date(); data.cloudLinks = [link]; try repository.save(data)
            }
            try encoder.encode(address).write(to: addressFile, options: .atomic)
        }
        let address: CloudAddress
        if phase == "accept" {
            let metadata = try await live.container.shareMetadata(for: try XCTUnwrap(fixture.invitation))
            try require(metadata.containerIdentifier == live.identifier &&
                        metadata.share.recordID.zoneID.zoneName == fixture.ownerAddress.zoneName &&
                        metadata.share.publicPermission == .none &&
                        metadata.ownerIdentity.userRecordID?.recordName == String(fixture.ownerID.split(separator: "|").last!),
                        "邀请不是指定拥有者的私有验收账本")
            try await live.accept(metadata)
            address = CloudAddress(container: live.identifier, environment: "Production", scope: .shared,
                                   zoneName: metadata.share.recordID.zoneID.zoneName, ownerName: metadata.share.recordID.zoneID.ownerName)
            let fetched = try await live.fetch(address)
            let remote = try XCTUnwrap(fetched)
            try preserveVerifiedReadback(remote, at: address)
        } else if phase == "probe" {
            // Read only the exact known zone. AirDrop may already have accepted
            // at the OS level before the application's presentation crashed.
            address = CloudAddress(container: live.identifier, environment: "Production", scope: .shared,
                                   zoneName: fixture.ownerAddress.zoneName,
                                   ownerName: String(fixture.ownerID.split(separator: "|").last!))
            let fetched = try await live.fetch(address)
            try preserveVerifiedReadback(try XCTUnwrap(fetched), at: address)
        } else {
            address = try decoder.decode(CloudAddress.self, from: Data(contentsOf: addressFile))
        }
        try require(address.container == live.identifier && address.environment == "Production" &&
                    address.scope == .shared && address.zoneName == fixture.ownerAddress.zoneName, "成员范围不符")
        let transport = ScopedTransport(live, address: address, account: identity)
        let state = AppState(repository: repository, clockDay: Day(year: 2026, month: 10, day: 15))
        state.configureCloud(transport); await state.refreshCloudAccount()
        defer { state.cloudDebounce?.cancel() }
        try require(state.store.ledger(fixture.ledgerID)?.name == name, "本机不是此批次验收账本")
        func sync() async { state.cloudDebounce?.cancel(); await state.synchronizeCloud(); state.cloudDebounce?.cancel() }
        func settled() throws {
            let link = try XCTUnwrap(state.cloudLink(for: fixture.ledgerID))
            try require(!link.pending && link.issue == nil && link.incoming == nil, link.issue ?? "未完成同步")
        }
        await sync()
        if phase == "revoked" {
            try require(!state.canEditLedger(fixture.ledgerID) && state.cloudLink(for: fixture.ledgerID)?.issue != nil,
                        "撤销后仍可编辑或没有提示")
        } else {
            try settled()
            if phase == "add" {
                let operation = fixture.run + "-B-add"
                try require(!state.store.data.appliedOperations.contains(operation), "禁止重复增加此验收流水")
                let account = try XCTUnwrap(state.store.accounts(in: fixture.ledgerID).first)
                let category = try XCTUnwrap(state.store.categories(in: fixture.ledgerID, kind: .expense).first { $0.isLeaf })
                try require(state.perform {
                    _ = try state.store.addTransaction(Transaction(ledgerID: fixture.ledgerID, operationID: operation,
                        kind: .expense, amountCents: 2000, date: Day(year: 2026, month: 10, day: 15),
                        accountID: account.id, categoryID: category.id, note: "Production B 验收"))
                }, "B 新增失败")
                await sync(); try settled()
            } else if phase == "edit" {
                let transaction = try XCTUnwrap(state.store.activeTransactions(in: fixture.ledgerID).first { $0.id == fixture.originalTransactionID })
                try require(transaction.amountCents == 1234, "原记录已变化，不重复编辑")
                try require(state.perform { _ = try state.store.updateTransaction(transaction.id) { $0.amountCents = 1333 } }, "B 编辑失败")
                await sync(); try settled()
            } else if phase == "readOnly" {
                try require(!state.canEditLedger(fixture.ledgerID), "只读权限未生效")
                let unchanged = try encoder.encode(state.store.data)
                try require(!state.perform { try state.store.renameLedger(fixture.ledgerID, name: "不应生效") } &&
                            (try encoder.encode(state.store.data)) == unchanged, "只读写入未被完整阻止")
            } else if phase == "readWrite" {
                try require(state.canEditLedger(fixture.ledgerID), "编辑权限未恢复")
            }
            let fetched = try await live.fetch(address)
            let remote = try XCTUnwrap(fetched)
            let local = try XCTUnwrap(state.cloudLink(for: fixture.ledgerID))
            try require(remote.snapshot.matches(local.cached), "远端回读与本机不符")
        }
        let records = state.store.activeTransactions(in: fixture.ledgerID)
        try require(try fingerprint(normal) == before, "正常 Mac 数据变化，停止")
        let link = state.cloudLink(for: fixture.ledgerID)
        let summary: [String: Any] = ["run": fixture.run, "phase": phase, "environment": "Production",
            "distinctAccounts": true, "normalFileUnchanged": true, "records": records.count,
            "expenseCents": records.reduce(Int64(0)) { $0 + $1.amountCents }, "writable": state.canEditLedger(fixture.ledgerID),
            "pending": link?.pending ?? false, "conflict": link?.incoming != nil, "hasIssue": link?.issue != nil]
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent(phase + "-summary.json"), options: .atomic)
    }

    private func fingerprint(_ url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }
}
