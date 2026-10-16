import CloudKit
import CryptoKit
import XCTest
import YujiCore
@testable import Yuji

/// Explicitly authorized QA cleanup only. Ordinary test runs never delete a zone.
@MainActor
final class LiveCloudFixtureCleanupTests: XCTestCase {
    private struct Manifest: Decodable {
        let accountID: String
        let address: CloudAddress
        let expected: CloudLedgerSnapshot
        let normalBeforeSHA256: String?
        let normalPreviewSHA256: String?
        let paymentSHA256: String?
    }

    private func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CloudSyncError.invalid(message) }
    }

    private func approvedFixture() throws -> (Manifest, CloudKitTransport) {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["YUJI_LIVE_SERVICE_ACCEPTANCE"] == "1")
        let session = try XCTUnwrap(environment["YUJI_STRESS_SESSION"])
        try require(UUID(uuidString: session) != nil, "必须使用独立测试目录")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let directory = FileManager.default.temporaryDirectory
        let manifest = try decoder.decode(Manifest.self, from: Data(contentsOf:
            directory.appendingPathComponent("yuji-approved-fixture-cleanup.json")))
        try require(manifest.address.environment == "Development" && manifest.address.scope == .private,
                    "只允许处理 Development 私有验收 zone")
        try require(UUID(uuidString: manifest.expected.ledger.id.raw) != nil,
                    "验收账本必须使用精确 UUID")
        try manifest.expected.validate()
        try require(manifest.expected.transactions.count == 3 &&
                    manifest.expected.transactions.filter { $0.kind == .expense }.reduce(Int64(0)) { $0 + $1.amountCents } == 2000 &&
                    manifest.expected.transactions.filter { $0.kind == .income }.reduce(Int64(0)) { $0 + $1.amountCents } == 10000,
                    "不是已批准的三笔验收数据")
        let transport = try XCTUnwrap(CloudKitTransport.configured())
        try require(transport.identifier == manifest.address.container && transport.environment == "Development",
                    "测试包的实际容器或环境不符")
        return (manifest, transport)
    }

    func testDeleteExplicitlyApprovedDevelopmentFixture() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["YUJI_LIVE_FIXTURE_CLEANUP"] == "DELETE_APPROVED_FIXTURE")
        let (manifest, transport) = try approvedFixture()
        let account = try await transport.accountID()
        try require(account == manifest.accountID, "当前拥有者身份不符")
        let before = Set(try await transport.addresses())
        try require(before.contains(manifest.address), "目标 zone 不存在；不得盲目重复删除")
        let fetched = try await transport.fetch(manifest.address)
        let remote = try XCTUnwrap(fetched)
        try require(remote.snapshot.matches(manifest.expected), "云端内容已变化，必须重新审查")
        let share = try await transport.share(at: manifest.address)
        try require(share.currentUserParticipant?.role == .owner && share.publicPermission == .none,
                    "只允许拥有者处理已知私有测试共享")
        let current = try await transport.accountID()
        try require(current == manifest.accountID, "删除前账号发生变化")
        _ = try await transport.container.privateCloudDatabase.deleteRecordZone(withID: transport.zoneID(manifest.address))
        // Persist the deletion acknowledgment before readback, so a later failure is not retried blindly.
        try writeSummary(["deletionAcknowledged": true, "absenceVerified": false])
        let after = Set(try await transport.addresses())
        try require(!after.contains(manifest.address), "删除已确认，目标消失仍需回读")
        try require(after == before.subtracting([manifest.address]), "其他 zone 集合发生变化，停止本地回收")
        try writeSummary(["deletionAcknowledged": true, "absenceVerified": true, "otherZonesUnchanged": true])
    }

    func testReadBackApprovedFixtureAbsence() async throws {
        let (manifest, transport) = try approvedFixture()
        let account = try await transport.accountID()
        try require(account == manifest.accountID, "回读账号不符")
        let addresses = try await transport.addresses()
        try require(!addresses.contains(manifest.address), "验收 zone 仍存在")
        let remote = try await transport.fetch(manifest.address)
        XCTAssertNil(remote)
    }

    func testApplyExplicitlyApprovedNormalFixturePreview() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["YUJI_LIVE_FIXTURE_CLEANUP"] == "APPLY_APPROVED_LOCAL_PREVIEW")
        try require(environment["YUJI_TEST_CLOUD_MODE"] == "signedOut", "宿主自动同步必须隔离")
        let (manifest, transport) = try approvedFixture()
        let account = try await transport.accountID()
        try require(account == manifest.accountID, "本地回收前账号不符")
        let addresses = try await transport.addresses()
        try require(!addresses.contains(manifest.address), "云端尚未清理，不写本地")
        let normalURL = JSONFileRepository.defaultURL()
        let previewURL = FileManager.default.temporaryDirectory.appendingPathComponent("yuji-approved-normal-preview.json")
        let paymentURL = normalURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("YujiDeveloperSupport/support.json")
        let beforeHash = try XCTUnwrap(manifest.normalBeforeSHA256)
        let previewHash = try XCTUnwrap(manifest.normalPreviewSHA256)
        let paymentHash = try XCTUnwrap(manifest.paymentSHA256)
        try require(try sha256(normalURL) == beforeHash && sha256(previewURL) == previewHash &&
                    sha256(paymentURL) == paymentHash, "当前文件与批准预览不同，必须重新回读")
        let repository = JSONFileRepository(url: normalURL)
        let before = try XCTUnwrap(try repository.load())
        let preview = try XCTUnwrap(try JSONFileRepository(url: previewURL).load())
        let id = manifest.expected.ledger.id
        let current = try CloudLedgerSnapshot(data: before, ledgerID: id)
        try require(current.matches(manifest.expected), "本地验收账本已变化")
        var required = before
        let operations = Set(required.transactions.filter { $0.ledgerID == id }.map(\.operationID))
        CloudWorkspace.remove(id, from: &required)
        required.cloudLinks?.removeAll { $0.cached.ledger.id == id && $0.address == manifest.address }
        required.appliedOperations.removeAll { operations.contains($0) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try require(try encoder.encode(required) == encoder.encode(preview), "预览影响了非目标数据或绑定")
        // No await between the final compare and atomic save; the normal App is not running.
        try require(try sha256(normalURL) == beforeHash, "保存前文件发生变化")
        try repository.save(preview)
        let readback = try XCTUnwrap(try repository.load())
        try require(try encoder.encode(readback) == encoder.encode(required), "原子保存回读不符")
        try require(try sha256(paymentURL) == paymentHash, "支付日志发生变化")
        let summary: [String: Any] = ["normalPreviewApplied": true, "remainingRecords": readback.transactions.count,
                                      "remainingBooks": readback.ledgers.count, "paymentUnchanged": true,
                                      "otherBusinessAndBindingsUnchanged": true]
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
            .write(to: FileManager.default.temporaryDirectory.appendingPathComponent("yuji-fixture-local-cleanup-summary.json"), options: .atomic)
    }

    private func sha256(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private func writeSummary(_ values: [String: Bool]) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("yuji-fixture-cleanup-summary.json")
        try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
            .write(to: url, options: .atomic)
    }
}
