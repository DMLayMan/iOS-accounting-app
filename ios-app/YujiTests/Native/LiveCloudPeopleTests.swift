import CloudKit
import CryptoKit
import XCTest
import YujiCore
@testable import Yuji

/// The real B account of the pre-existing Production QA share. Never discovers other books.
@MainActor final class LiveCloudPeopleTests: XCTestCase {
    private struct Fixture: Codable {
        let run: String
        let ownerID: String
        let memberID: String
        let ownerAddress: CloudAddress
        let ledgerID: EntityID
    }
    private struct Baseline: Codable {
        let identity: String
        let person: CloudPerson
        let book: CloudLedgerSnapshot
    }
    private final class Scoped: CloudTransport {
        let live: CloudKitTransport
        let address: CloudAddress
        let identity: String
        let ledgerID: EntityID
        var configuration: CloudAddress { live.configuration }
        var supportsPeople: Bool { true }
        init(_ live: CloudKitTransport, _ address: CloudAddress, _ identity: String, _ ledgerID: EntityID) {
            self.live = live; self.address = address; self.identity = identity; self.ledgerID = ledgerID
        }
        func check(_ target: CloudAddress) async throws {
            guard target == address, try await live.accountID() == identity else { throw CloudSyncError.invalid("验收范围改变，已停止") }
        }
        func accountID() async throws -> String { try await check(address); return identity }
        func addresses() async throws -> [CloudAddress] { try await check(address); return [address] }
        func fetch(_ target: CloudAddress) async throws -> CloudRemote? { try await check(target); return try await live.fetch(target) }
        func save(_ book: CloudLedgerSnapshot, at target: CloudAddress, version: Data?) async throws -> CloudRemote {
            try await check(target)
            guard book.ledger.id == ledgerID else { throw CloudSyncError.invalid("账本身份不符") }
            return try await live.save(book, at: target, version: version)
        }
        func leave(_ address: CloudAddress) async throws { throw CloudSyncError.invalid("此验收不允许退出或删除共享") }
        func myPerson() async throws -> CloudPerson { try await check(address); return try await live.myPerson() }
        func saveMyPerson(_ person: CloudPerson) async throws { try await check(address); try await live.saveMyPerson(person) }
        func people(at target: CloudAddress) async throws -> [CloudPerson] { try await check(target); return try await live.people(at: target) }
        func publishMyPerson(_ person: CloudPerson, at target: CloudAddress) async throws { try await check(target); try await live.publishMyPerson(person, at: target) }
    }
    private func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw CloudSyncError.invalid(message) }
    }
    private func fingerprint(_ url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return Data(SHA256.hash(data: try Data(contentsOf: url)))
    }
    func testProductionNicknamePhase() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["YUJI_LIVE_NICKNAME"] == "1")
        #if !targetEnvironment(macCatalyst)
        throw XCTSkip("The live B identity belongs only to the authorized Mac peer")
        #endif
        try require(env["YUJI_TEST_CLOUD_MODE"] == "signedOut" && UUID(uuidString: env["YUJI_STRESS_SESSION"] ?? "") != nil, "宿主必须隔离")
        let run = try XCTUnwrap(UUID(uuidString: env["YUJI_NICKNAME_RUN"] ?? ""))
        let phase = try XCTUnwrap(env["YUJI_NICKNAME_PHASE"])
        try require(["baseline", "probe", "setB", "renameB", "verifyNames", "restoreB", "readOnlyName", "recoverName", "addB", "editA"].contains(phase), "未知阶段")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let fixture = try decoder.decode(Fixture.self, from: Data(try XCTUnwrap(env["YUJI_TESTFLIGHT_CONTEXT"]).utf8))
        let live = try XCTUnwrap(CloudKitTransport.configured())
        let identity = try await live.accountID()
        try require(live.identifier == "iCloud.com.dmlayman.yuji" && live.environment == "Production" && identity == fixture.memberID && fixture.ownerID != identity, "真实 Production B 身份不符")
        try require(fixture.ownerAddress.environment == "Production" && fixture.ownerAddress.scope == .private &&
                    fixture.ownerAddress.zoneName.hasPrefix("yuji-book-"), "QA zone 不符")
        // The book zone and the QA run have different UUIDs. Reuse the accepted address,
        // never reconstruct its owner or assume either identifier is the other.
        let accepted = FileManager.default.temporaryDirectory.appendingPathComponent("yuji-distribution-peer-" + fixture.run)
            .appendingPathComponent("member-address.json")
        let address = try decoder.decode(CloudAddress.self, from: Data(contentsOf: accepted))
        try require(address.container == live.identifier && address.environment == "Production" &&
                    address.scope == .shared && address.zoneName == fixture.ownerAddress.zoneName, "已接受的成员地址不符")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yuji-nickname-" + run.uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let normal = JSONFileRepository.defaultURL(), before = try fingerprint(normal)
        defer { XCTAssertEqual(try? fingerprint(normal), before, "正常 Mac 账本不可改变") }
        let baselineURL = directory.appendingPathComponent("baseline.json")
        let fetched = try await live.fetch(address)
        let remote = try XCTUnwrap(fetched)
        try require(remote.snapshot.ledger.id == fixture.ledgerID && remote.snapshot.ledger.name == "QA 1015 " + fixture.run.prefix(8), "不是登记的验收账本")
        try encoder.encode(remote.snapshot).write(to: directory.appendingPathComponent(phase + "-before-book.json"), options: .atomic)
        if phase == "baseline" {
            try require(!FileManager.default.fileExists(atPath: baselineURL.path), "原始昵称已备份，禁止覆盖；换阶段继续")
            let expectedRecords = try XCTUnwrap(Int(env["YUJI_NICKNAME_BASELINE_COUNT"] ?? "2"))
            try require(remote.snapshot.transactions.count == expectedRecords && Set(remote.snapshot.transactions.compactMap(\.authorID)).count == 2, "初始记录数量或作者不符，先回读再继续")
            let person = try await live.myPerson()
            try encoder.encode(Baseline(identity: identity, person: person, book: remote.snapshot)).write(to: baselineURL, options: .atomic)
        }
        let baseline = try decoder.decode(Baseline.self, from: Data(contentsOf: baselineURL))
        try require(baseline.identity == identity && baseline.book.ledger.id == fixture.ledgerID, "备份身份不符")
        if phase == "probe" {
            let members = try await live.people(at: address)
            let share = try await live.share(at: address)
            let raw = Dictionary(uniqueKeysWithValues: share.participants.enumerated().map { index, p in
                (String(index), ["identity": p.userIdentity.userRecordID.map { live.identity($0.recordName) } ?? "missing",
                    "acceptance": String(p.acceptanceStatus.rawValue), "role": String(p.role.rawValue),
                    "current": p === share.currentUserParticipant ? "true" : "false"])
            })
            try JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("probe-participants.json"), options: .atomic)
            try encoder.encode(members).write(to: directory.appendingPathComponent("probe-people.json"), options: .atomic)
            let name = "member-" + SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
            let db = try live.database(address)
            let record = try await db.record(for: CKRecord.ID(recordName: name, zoneID: live.zoneID(address)))
            let asset = try XCTUnwrap(record["payload"] as? CKAsset)
            try Data(contentsOf: try XCTUnwrap(asset.fileURL)).write(to: directory.appendingPathComponent("probe-own-record.json"), options: .atomic)
            print("NICKNAME_PROBE matchedSelf=\(members.contains { $0.accountID == identity }) members=\(members.count) participants=\(share.participants.count)")
            return
        }
        var data = remote.snapshot.materialized(); data.activeCloudAccountID = identity
        data.cloudLinks = [.init(accountID: identity, address: address, cached: remote.snapshot, base: remote.snapshot, version: remote.version, writable: remote.writable)]
        let repository = JSONFileRepository(url: directory.appendingPathComponent("workspace.json"))
        try repository.save(data)
        let state = AppState(repository: repository, clockDay: Day(year: 2026, month: 10, day: 15))
        state.configureCloud(Scoped(live, address, identity, fixture.ledgerID)); await state.refreshCloudAccount()
        defer { state.cloudDebounce?.cancel() }
        func sync() async { state.cloudDebounce?.cancel(); await state.synchronizeCloud(); await state.synchronizePeople(force: true); state.cloudDebounce?.cancel() }
        await sync()
        if ["setB", "renameB", "restoreB", "readOnlyName"].contains(phase) {
            if phase == "readOnlyName" {
                try require(!remote.writable && state.myCloudPerson?.person.nickname == baseline.person.nickname, "只读权限或当前昵称与基线不符，停止")
            }
            if phase == "restoreB" {
                let current = state.myCloudPerson?.person.nickname
                try require(current == env["YUJI_NICKNAME_B"] || current == baseline.person.nickname, "昵称已被其他设备修改，停止自动恢复")
            }
            let nickname = phase == "restoreB" ? baseline.person.nickname ?? "" : try XCTUnwrap(env["YUJI_NICKNAME_B"])
            try require(state.setMyNickname(nickname), state.alertError ?? "昵称本机保存失败")
            await state.synchronizePeople(force: true)
            try require(state.myCloudPerson?.pending == false, "私有昵称未完成同步")
            if phase == "readOnlyName" {
                try require(state.cloudPeopleIssue?.contains("只读账本") == true, "缺少只读昵称延迟说明")
            } else { try require(state.cloudPeopleIssue == nil, state.cloudPeopleIssue ?? "共享昵称未完成同步") }
            let saved = try await live.myPerson()
            let normalized = try CloudPerson.normalizedNickname(nickname)
            try require(saved.nickname == normalized, "私有昵称回读不符")
            let members = try await live.people(at: address)
            let ownMember = try XCTUnwrap(members.first { $0.accountID == identity })
            try require(ownMember.nickname == (phase == "readOnlyName" ? baseline.person.nickname : saved.nickname), "共享昵称回读不符")
        } else if phase == "recoverName" {
            try require(remote.writable && state.cloudPeopleIssue == nil, "恢复读写后的昵称同步未完成")
            let saved = try await live.myPerson()
            let members = try await live.people(at: address)
            try require(saved.nickname == env["YUJI_NICKNAME_B"] && members.first { $0.accountID == identity }?.nickname == saved.nickname, "恢复权限后昵称未到达共享成员记录")
        } else if phase == "addB" {
            let operation = "nickname-" + run.uuidString + "-B-entry"
            if !state.store.data.appliedOperations.contains(operation) {
                let account = try XCTUnwrap(state.store.accounts(in: fixture.ledgerID).first)
                let category = try XCTUnwrap(state.store.categories(in: fixture.ledgerID, kind: .expense).first { $0.isLeaf })
                try require(state.perform {
                    _ = try state.store.addTransaction(Transaction(ledgerID: fixture.ledgerID, operationID: operation,
                        kind: .expense, amountCents: 2222, date: Day(year: 2026, month: 10, day: 15), accountID: account.id,
                        categoryID: category.id, note: "昵称 B " + run.uuidString.prefix(8)))
                }, "B 新建失败")
            }
            await sync()
            let entry = try XCTUnwrap(state.store.data.transactions.first { $0.operationID == operation })
            try require(entry.authorID == identity && entry.lastEditorID == identity && entry.amountCents == 2222, "B 新记账归属不正确")
        } else if phase == "editA" {
            let note = try XCTUnwrap(env["YUJI_NICKNAME_A_NOTE"])
            let entry = try XCTUnwrap(state.store.activeTransactions(in: fixture.ledgerID).first { $0.note.hasPrefix(note) })
            try require(entry.authorID == fixture.ownerID && entry.amountCents == 1111, "不是 A 新建的验收记录")
            try require(state.perform { _ = try state.store.updateTransaction(entry.id) { $0.note = note + " · B已核对" } }, "B 编辑失败")
            await sync()
            let edited = try XCTUnwrap(state.store.data.transactions.first { $0.id == entry.id })
            try require(edited.authorID == fixture.ownerID && edited.lastEditorID == identity, "修改错误改变创建人")
        }
        if phase == "verifyNames" {
            try require(state.personName(fixture.ownerID, ledgerID: fixture.ledgerID) == env["YUJI_NICKNAME_A"], "A 展示昵称不符")
            try require(state.personName(identity, ledgerID: fixture.ledgerID) == env["YUJI_NICKNAME_B"], "B 展示昵称不符")
        }
        let finalFetch = try await live.fetch(address)
        let result = try XCTUnwrap(finalFetch)
        for entry in baseline.book.transactions {
            try require(result.snapshot.transactions.first { $0.id == entry.id } == entry, "原始验收记录被改动，停止")
        }
        let link = try XCTUnwrap(state.cloudLink(for: fixture.ledgerID))
        try require(!link.pending && link.issue == nil && link.incoming == nil, link.issue ?? "财务未完成同步")
        try encoder.encode(result.snapshot).write(to: directory.appendingPathComponent(phase + "-after-book.json"), options: .atomic)
        let summary: [String: Any] = ["phase": phase, "environment": "Production", "distinctAccounts": true,
            "normalFileUnchanged": try fingerprint(normal) == before, "records": result.snapshot.transactions.count,
            "expenseCents": result.snapshot.transactions.filter(\.isActive).reduce(Int64(0)) { $0 + $1.amountCents },
            "originalEntriesUnchanged": true, "nicknamePending": state.myCloudPerson?.pending ?? false,
            "nicknameHasIssue": state.cloudPeopleIssue != nil]
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent(phase + "-summary.json"), options: .atomic)
        print("NICKNAME_PHASE_RESULT " + String(decoding: try JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys]), as: UTF8.self))
    }
}
