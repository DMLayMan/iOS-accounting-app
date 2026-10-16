import CloudKit
import CryptoKit
import XCTest
import YujiCore
@testable import Yuji

/// Opt-in real Production member checks against an already accepted, explicitly named QA book.
/// The normal Mac database and every baseline transaction must remain unchanged.
@MainActor final class LiveCloudReleaseTests: XCTestCase {
    private struct Context: Codable {
        let run: String
        let acceptanceRun: String
        let ownerID: String
        let memberID: String
        let ownerAddress: CloudAddress
        let ledgerID: EntityID
        let invitation: URL?
    }

    private final class Scoped: CloudTransport {
        let live: CloudKitTransport
        let address: CloudAddress
        let identity: String
        let ledgerID: EntityID
        var loseAcknowledgement = false
        var configuration: CloudAddress { live.configuration }
        init(_ live: CloudKitTransport, _ address: CloudAddress, _ identity: String, _ ledgerID: EntityID) {
            self.live = live; self.address = address; self.identity = identity; self.ledgerID = ledgerID
        }
        func check(_ target: CloudAddress) async throws {
            guard target == address, try await live.accountID() == identity else {
                throw CloudSyncError.invalid("验收账号或范围改变，已停止")
            }
        }
        func accountID() async throws -> String { try await check(address); return identity }
        func addresses() async throws -> [CloudAddress] { try await check(address); return [address] }
        func fetch(_ target: CloudAddress) async throws -> CloudRemote? {
            try await check(target); return try await live.fetch(target)
        }
        func save(_ book: CloudLedgerSnapshot, at target: CloudAddress, version: Data?) async throws -> CloudRemote {
            try await check(target)
            guard book.ledger.id == ledgerID else { throw CloudSyncError.invalid("账本身份不符") }
            let saved = try await live.save(book, at: target, version: version)
            if loseAcknowledgement { loseAcknowledgement = false; throw CloudSyncError.offline }
            return saved
        }
        func leave(_ target: CloudAddress) async throws { try await check(target); try await live.leave(target) }
    }

    private func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw CloudSyncError.invalid(message) }
    }

    func testExistingProductionAbnormalPhase() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["YUJI_RELEASE_CLOUD"] == "1")
        #if !targetEnvironment(macCatalyst)
        throw XCTSkip("Only the authorized Mac Production member may run this test")
        #endif
        try require(env["YUJI_TEST_CLOUD_MODE"] == "signedOut" && UUID(uuidString: env["YUJI_STRESS_SESSION"] ?? "") != nil, "宿主未隔离")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let context = try decoder.decode(Context.self, from: Data(try XCTUnwrap(env["YUJI_RELEASE_CONTEXT"]).utf8))
        try require(UUID(uuidString: context.acceptanceRun) != nil && context.ownerID != context.memberID, "批次或账号不符")
        let phase = try XCTUnwrap(env["YUJI_RELEASE_PHASE"])
        try require(["baseline", "readback", "holdAdd", "release", "holdEdit", "conflict", "resolve", "lostAck", "recoverAck", "readOnly", "readWrite", "writeRestored", "captureAccepted", "revoked", "accept", "leave"].contains(phase), "未知阶段")
        let live = try XCTUnwrap(CloudKitTransport.configured())
        let identity = try await live.accountID()
        try require(live.identifier == "iCloud.com.dmlayman.yuji" && live.environment == "Production" && identity == context.memberID, "真实 Production B 身份不符")
        let accepted = FileManager.default.temporaryDirectory.appendingPathComponent("yuji-distribution-peer-" + context.run).appendingPathComponent("member-address.json")
        let address = try decoder.decode(CloudAddress.self, from: Data(contentsOf: accepted))
        try require(address.container == live.identifier && address.environment == "Production" && address.scope == .shared && address.zoneName == context.ownerAddress.zoneName, "已接受共享范围不符")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yuji-release-" + context.acceptanceRun)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let normal = JSONFileRepository.defaultURL()
        let normalBefore = try? Data(contentsOf: normal)
        defer { XCTAssertEqual(try? Data(contentsOf: normal), normalBefore, "正常 Mac 账本发生变化") }
        let baselineURL = directory.appendingPathComponent("baseline.json")
        let repository = JSONFileRepository(url: directory.appendingPathComponent("workspace.json"))
        let today = Day(year: 2026, month: 10, day: 15)
        let heldOperation = "release-" + context.acceptanceRun + "-B-held"
        let receiptOperation = "release-" + context.acceptanceRun + "-B-ack"
        func preserve(_ book: CloudLedgerSnapshot, _ name: String) throws {
            try encoder.encode(book).write(to: directory.appendingPathComponent(name + ".json"), options: .atomic)
        }
        if phase == "accept" {
            let invitation: URL
            if let provided = context.invitation { invitation = provided }
            else {
                let saved = try String(contentsOf: directory.appendingPathComponent("existing-private-invitation.txt"), encoding: .utf8)
                invitation = try XCTUnwrap(URL(string: saved))
            }
            let metadata = try await live.container.shareMetadata(for: invitation)
            try require(metadata.containerIdentifier == live.identifier && metadata.share.recordID.zoneID == live.zoneID(address) && metadata.share.publicPermission == .none, "重新邀请范围不符")
            try await live.accept(metadata)
        }
        if phase == "baseline" {
            try require(!FileManager.default.fileExists(atPath: baselineURL.path) && (try repository.load()) == nil, "已有基线，不覆盖")
            let fetched = try await live.fetch(address)
            let remote = try XCTUnwrap(fetched)
            try require(remote.snapshot.ledger.id == context.ledgerID && remote.snapshot.ledger.name == "QA 1015 " + context.run.prefix(8), "不是登记的 QA 账本")
            let expected = Set(try XCTUnwrap(env["YUJI_RELEASE_BASELINE_IDS"]).split(separator: ",").map(String.init))
            try require(Set(remote.snapshot.transactions.map { $0.id.raw }) == expected, "远端记录与手机基线不符，停止")
            try preserve(remote.snapshot, "baseline")
            var data = remote.snapshot.materialized(); data.activeCloudAccountID = identity
            data.cloudLinks = [.init(accountID: identity, address: address, cached: remote.snapshot, base: remote.snapshot, version: remote.version, writable: remote.writable)]
            try repository.save(data)
        }
        let baseline = try decoder.decode(CloudLedgerSnapshot.self, from: Data(contentsOf: baselineURL))
        let transport = Scoped(live, address, identity, context.ledgerID)
        let state = AppState(repository: repository, clockDay: today)
        state.configureCloud(transport); await state.refreshCloudAccount()
        defer { state.cloudDebounce?.cancel() }
        func sync() async { state.cloudDebounce?.cancel(); await state.synchronizeCloud(forceLedgerID: context.ledgerID); state.cloudDebounce?.cancel() }
        func settled() throws {
            let link = try XCTUnwrap(state.cloudLink(for: context.ledgerID))
            try require(!link.pending && link.incoming == nil && link.issue == nil, link.issue ?? "同步未完成")
        }
        func add(_ operation: String, cents: Int64, note: String) throws {
            try require(!state.store.data.appliedOperations.contains(operation), "操作已落盘，不重复新增；改用回读阶段")
            let account = try XCTUnwrap(state.store.accounts(in: context.ledgerID).first)
            let category = try XCTUnwrap(state.store.categories(in: context.ledgerID, kind: .expense).first { $0.isLeaf })
            try require(state.perform { _ = try state.store.addTransaction(Transaction(ledgerID: context.ledgerID, operationID: operation, kind: .expense, amountCents: cents, date: today, accountID: account.id, categoryID: category.id, note: note)) }, "本机保存失败")
            state.cloudDebounce?.cancel()
        }
        switch phase {
        case "holdAdd":
            await sync(); try settled(); state.setCloudPaused(context.ledgerID, paused: true)
            try add(heldOperation, cents: 333, note: "云异常 B " + context.acceptanceRun.prefix(8))
            let restarted = AppState(repository: repository, clockDay: today)
            try require(restarted.store.data.cloudLinks?.first?.pending == true && restarted.store.data.appliedOperations.contains(heldOperation), "重启丢失待上传记录")
        case "holdEdit":
            await sync(); try settled(); state.setCloudPaused(context.ledgerID, paused: true)
            let entry = try XCTUnwrap(state.store.data.transactions.first { $0.operationID == heldOperation })
            try require(entry.note == "云异常 B " + context.acceptanceRun.prefix(8), "此记录已编辑，禁止重复阶段")
            try require(state.perform { _ = try state.store.updateTransaction(entry.id) { $0.note = "B并发版本 " + context.acceptanceRun.prefix(8) } }, "待同步编辑保存失败")
            state.cloudDebounce?.cancel()
        case "conflict":
            await sync()
            try require(state.cloudLink(for: context.ledgerID)?.incoming != nil, "真实冲突未保留")
            let restarted = AppState(repository: repository, clockDay: today)
            try require(restarted.store.data.cloudLinks?.first?.incoming != nil, "重启丢失冲突")
        case "resolve":
            try require(state.resolveCloudConflict(context.ledgerID), "没有待解决的冲突")
            let copy = try XCTUnwrap(state.store.data.ledgers.first { $0.name.hasSuffix("（未同步副本）") })
            try require(state.store.activeTransactions(in: copy.id).contains { $0.note == "B并发版本 " + context.acceptanceRun.prefix(8) }, "B 本地版本未保留")
            await sync(); try settled()
        case "lostAck":
            await sync(); try settled()
            try add(receiptOperation, cents: 555, note: "云异常 回执 " + context.acceptanceRun.prefix(8))
            transport.loseAcknowledgement = true; await sync()
            try require(state.cloudLink(for: context.ledgerID)?.pending == true, "注入丢回执后没有保留 outbox")
            let fetched = try await live.fetch(address)
            let remote = try XCTUnwrap(fetched)
            try require(remote.snapshot.transactions.filter { $0.operationID == receiptOperation }.count == 1, "服务端没有恰好保存一次")
        case "recoverAck":
            await sync(); try settled()
            try require(state.store.data.transactions.filter { $0.operationID == receiptOperation }.count == 1, "回执恢复重复或丢失交易")
        case "readOnly":
            await sync(); try settled(); try require(!state.canEditLedger(context.ledgerID), "只读未生效")
            let before = try encoder.encode(state.store.data)
            try require(!state.perform { try state.store.renameLedger(context.ledgerID, name: "不应生效") }, "只读写入未拦截")
            try require(try encoder.encode(state.store.data) == before, "只读拦截改变业务数据")
        case "readWrite":
            await sync(); try settled(); try require(state.canEditLedger(context.ledgerID), "编辑权限未恢复")
        case "writeRestored":
            await sync(); try settled(); try require(state.canEditLedger(context.ledgerID), "编辑权限未恢复")
            let entry = try XCTUnwrap(state.store.data.transactions.first { $0.operationID == receiptOperation })
            try require(entry.note == "云异常 回执 " + context.acceptanceRun.prefix(8), "恢复写入阶段已执行，不重复修改")
            try require(state.perform { _ = try state.store.updateTransaction(entry.id) { $0.note = "权限恢复后写入 " + context.acceptanceRun.prefix(8) } }, "恢复后本地写入失败")
            await sync(); try settled()
            let share = try await live.share(at: address)
            try require(share.publicPermission == .none && share.currentUserParticipant?.acceptanceStatus == .accepted, "不是当前已接受的私有共享")
            let invitation = try XCTUnwrap(share.url)
            try Data(invitation.absoluteString.utf8).write(to: directory.appendingPathComponent("existing-private-invitation.txt"), options: .atomic)
        case "captureAccepted":
            await sync(); try settled()
            let share = try await live.share(at: address)
            try require(share.publicPermission == .none && share.currentUserParticipant?.acceptanceStatus == .accepted, "当前账号尚未接受私有邀请")
            let invitation = try XCTUnwrap(share.url)
            let path = directory.appendingPathComponent("reaccepted-private-invitation-20261016.txt")
            try require(!FileManager.default.fileExists(atPath: path.path), "已保存本轮新邀请，不覆盖")
            try Data(invitation.absoluteString.utf8).write(to: path, options: .atomic)
        case "revoked":
            await sync()
            try require(!state.canEditLedger(context.ledgerID) && state.cloudLink(for: context.ledgerID)?.issue != nil, "撤销后未冻结写入")
            try require(state.preserveCloudCopy(context.ledgerID), "撤销后未保存本地副本")
        case "leave":
            await sync(); try settled()
            let existingIDs = Set(state.store.data.ledgers.map(\.id))
            let before = state.store.activeTransactions(in: context.ledgerID)
            let result = await state.leaveCloudBook(context.ledgerID)
            try require(result && state.cloudLink(for: context.ledgerID) == nil, "成员退出失败：" + state.cloudStatus)
            let copy = try XCTUnwrap(state.store.data.ledgers.first { !existingIDs.contains($0.id) && $0.name.hasSuffix("（本地副本）") })
            let copied = state.store.activeTransactions(in: copy.id)
            try require(copied.count == before.count && copied.reduce(Int64(0)) { $0 + $1.amountCents } == before.reduce(Int64(0)) { $0 + $1.amountCents }, "退出副本记录或金额不一致")
            do {
                _ = try await live.fetch(address)
                XCTFail("退出后仍能读取共享账本")
            } catch {
                XCTAssertEqual(error as? CloudSyncError, .revoked)
            }
        default:
            await sync(); try settled()
        }
        if !["revoked", "leave"].contains(phase) {
            let fetched = try await live.fetch(address)
            let remote = try XCTUnwrap(fetched)
            for original in baseline.transactions {
                try require(remote.snapshot.transactions.first { $0.id == original.id } == original, "既有流水变化，停止验收")
            }
            if ["resolve", "lostAck", "recoverAck", "readOnly", "readWrite", "writeRestored", "captureAccepted", "accept"].contains(phase) {
                let edited = try XCTUnwrap(remote.snapshot.transactions.first { $0.operationID == heldOperation })
                try require(edited.authorID == context.memberID && edited.lastEditorID == context.ownerID && edited.note == "A并发版本 " + context.acceptanceRun.prefix(8), "编辑后原始记账人或最终版本错误")
            }
            if phase == "writeRestored" {
                try require(remote.snapshot.transactions.first { $0.operationID == receiptOperation }?.note == "权限恢复后写入 " + context.acceptanceRun.prefix(8), "恢复写入未到达真实云端")
            }
            try preserve(remote.snapshot, phase + "-remote")
        }
        let link = state.cloudLink(for: context.ledgerID)
        let records = state.store.activeTransactions(in: context.ledgerID)
        let result: [String: Any] = ["phase": phase, "realCloudEnvironment": "Production", "identity": "authorized distinct member B", "records": records.count, "expenseCents": records.reduce(Int64(0)) { $0 + $1.amountCents }, "pending": link?.pending ?? false, "conflict": link?.incoming != nil, "writable": link?.writable ?? false, "hasIssue": link?.issue != nil, "normalMacFileUnchanged": (try? Data(contentsOf: normal)) == normalBefore, "radioOfflineTested": false, "pausedClientPhase": ["holdAdd", "holdEdit"].contains(phase), "injectedLostAcknowledgement": phase == "lostAck"]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent(phase + "-summary.json"), options: .atomic)
        print("RELEASE_CLOUD_PHASE " + String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
