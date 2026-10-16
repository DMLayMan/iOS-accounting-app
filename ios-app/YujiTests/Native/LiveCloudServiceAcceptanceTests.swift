import CloudKit
import XCTest
import YujiCore
@testable import Yuji

/// Opt-in, read-only checks against the existing isolated Development share.
@MainActor
final class LiveCloudServiceAcceptanceTests: XCTestCase {
    /// Mutates only the named test recipient in the opt-in Development fixture.
    /// This is SDK verification, not proof of Apple's member-management UI.
    func testChangeAuthorizedRecipientPermission() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["YUJI_LIVE_SERVICE_ACCEPTANCE"] == "1")
        let session = try XCTUnwrap(environment["YUJI_STRESS_SESSION"])
        XCTAssertNotNil(UUID(uuidString: session))
        let action = try XCTUnwrap(environment["YUJI_LIVE_PERMISSION_ACTION"])
        XCTAssertTrue(["readOnly", "readWrite", "remove"].contains(action))
        let email = try XCTUnwrap(environment["YUJI_LIVE_INVITE_EMAIL"])
        let directory = FileManager.default.temporaryDirectory
        let repository = JSONFileRepository(url: directory.appendingPathComponent("yuji-stress-\(session).json"))
        let data = try XCTUnwrap(try repository.load())
        let account = try XCTUnwrap(data.activeCloudAccountID)
        let link = try XCTUnwrap(data.cloudLinks?.first {
            $0.accountID == account && $0.cached.ledger.id == data.activeLedgerID
        })
        XCTAssertEqual(link.address.scope, .private)
        XCTAssertEqual(link.address.environment, "Development")
        let transport = try XCTUnwrap(CloudKitTransport.configured())
        let current = try await transport.accountID()
        XCTAssertEqual(current, account)
        let share = try await transport.share(at: link.address)
        XCTAssertEqual(share.publicPermission, .none)
        XCTAssertEqual(share.currentUserParticipant?.role, .owner)
        let lookup = try await transport.container.shareParticipant(forEmailAddress: email)
        func isRecipient(_ value: CKShare.Participant) -> Bool {
            if let id = lookup.userIdentity.userRecordID, value.userIdentity.userRecordID == id { return true }
            return value.userIdentity.lookupInfo?.emailAddress?.caseInsensitiveCompare(email) == .orderedSame
        }
        let participant = try XCTUnwrap(share.participants.first(where: isRecipient))
        XCTAssertNotEqual(participant.role, .owner)
        if action == "remove" { share.removeParticipant(participant) }
        else { participant.permission = action == "readOnly" ? .readOnly : .readWrite }
        let beforeSave = try await transport.accountID()
        XCTAssertEqual(beforeSave, account)
        _ = try await transport.container.privateCloudDatabase.save(share)
        let readback = try await transport.share(at: link.address)
        let updated = readback.participants.first(where: isRecipient)
        if action == "remove" { XCTAssertNil(updated) }
        else { XCTAssertEqual(updated?.permission, action == "readOnly" ? .readOnly : .readWrite) }
        let summary: [String: Any] = ["action": action, "privatePermission": readback.publicPermission == .none,
                                      "participantCount": readback.participants.count, "recipientPresent": updated != nil]
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("yuji-live-permission-summary.json"), options: .atomic)
    }
    func testReadIsolatedPrivateInvitation() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["YUJI_LIVE_SERVICE_ACCEPTANCE"] == "1")
        let session = try XCTUnwrap(environment["YUJI_STRESS_SESSION"])
        XCTAssertNotNil(UUID(uuidString: session))
        let directory = FileManager.default.temporaryDirectory
        let repository = JSONFileRepository(url: directory.appendingPathComponent("yuji-stress-\(session).json"))
        let data = try XCTUnwrap(try repository.load())
        let account = try XCTUnwrap(data.activeCloudAccountID)
        let link = try XCTUnwrap(data.cloudLinks?.first {
            $0.accountID == account && $0.cached.ledger.id == data.activeLedgerID
        })
        XCTAssertEqual(link.address.scope, .private)
        XCTAssertEqual(link.address.environment, "Development")
        let transport = try XCTUnwrap(CloudKitTransport.configured())
        let currentAccount = try await transport.accountID()
        XCTAssertEqual(currentAccount, account)
        let share = try await transport.share(at: link.address)
        XCTAssertEqual(share.publicPermission, .none)
        let url = try XCTUnwrap(share.url)
        XCTAssertTrue(["icloud.com", "www.icloud.com", "icloud.com.cn", "www.icloud.com.cn"].contains(url.host ?? ""))
        XCTAssertTrue(url.path.hasPrefix("/share/"))
        let summary: [String: Any] = [
            "privatePermission": true,
            "urlPresent": true,
            "participantCount": share.participants.count,
            "acceptedNonOwners": share.participants.filter { $0.role != .owner && $0.acceptanceStatus == .accepted }.count,
            "pendingNonOwners": share.participants.filter { $0.role != .owner && $0.acceptanceStatus == .pending }.count
        ]
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("yuji-live-share-summary.json"), options: .atomic)
        try Data(url.absoluteString.utf8)
            .write(to: directory.appendingPathComponent("yuji-live-private-invitation.txt"), options: .atomic)
    }
}
