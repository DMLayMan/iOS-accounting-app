import XCTest
import CloudKit
import YujiCore
@testable import Yuji

@MainActor
final class CloudMemberInvitationTests: XCTestCase {
    func testCurrentParticipantAliasResolvesToVerifiedAccount() {
        let config = CloudAddress(container: "iCloud.test", environment: "Production", zoneName: "")
        XCTAssertEqual(CloudKitTransport.memberIdentity(CKCurrentUserDefaultName, currentAccount: "iCloud.test|Production|b", configuration: config), "iCloud.test|Production|b")
    }
    func testOtherMemberIdentityKeepsContainerAndEnvironment() {
        let config = CloudAddress(container: "iCloud.test", environment: "Production", zoneName: "")
        XCTAssertEqual(CloudKitTransport.memberIdentity("a", currentAccount: "iCloud.test|Production|b", configuration: config), "iCloud.test|Production|a")
        XCTAssertNotEqual(CloudKitTransport.memberIdentity("a", currentAccount: "iCloud.test|Production|b", configuration: config), "iCloud.test|Production|b")
    }
    func testInviteEmailKeepsBoundAliasAndTrimsOuterSpaces() throws {
        XCTAssertEqual(try CloudKitTransport.inviteEmail("  member+home@example.cn\n"), "member+home@example.cn")
    }

    func testInviteEmailRejectsMultipleRecipientsAndControlCharacters() {
        for email in ["", "member", "@example.cn", "member@", "one@example.cn,two@example.cn", "one@example.cn\ntwo", "one@@example.cn", "one@example\u{0}.cn"] {
            XCTAssertThrowsError(try CloudKitTransport.inviteEmail(email))
        }
    }

    func testInviteEmailRejectsOversizedInput() {
        XCTAssertThrowsError(try CloudKitTransport.inviteEmail(String(repeating: "x", count: 254) + "@example.cn"))
    }
}
