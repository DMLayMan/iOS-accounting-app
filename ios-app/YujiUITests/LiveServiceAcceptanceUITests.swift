import XCTest

/// Opt-in physical-device checks. Ordinary regression never purchases or uploads data.
/// No SKTestSession or simulated cloud transport is used by these tests.
@MainActor
final class LiveServiceAcceptanceUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["YUJI_LIVE_SERVICE_ACCEPTANCE"] == "1", "Requires explicit live-service opt-in")
        let session = try XCTUnwrap(environment["YUJI_LIVE_SESSION"])
        XCTAssertNotNil(UUID(uuidString: session), "Live acceptance must use an isolated UUID")
        app = XCUIApplication()
        app.launchEnvironment = [
            "YUJI_STRESS_SESSION": session,
            "YUJI_TEST_STORE_MODE": "empty",
            "YUJI_TEST_SUPPORT_MODE": "storekit"
        ]
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["账本"].waitForExistence(timeout: 20))
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForLabel(_ id: String, containing text: String, timeout: TimeInterval = 90) {
        let target = element(id)
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        let changed = expectation(for: NSPredicate(format: "label CONTAINS %@", text), evaluatedWith: target)
        wait(for: [changed], timeout: timeout)
    }

    private func openCloud() {
        element("ledger.cloud").tap()
        XCTAssertTrue(element("cloud.status").waitForExistence(timeout: 10))
        XCTAssertFalse(element("cloud.simulated").exists, "This check must contact real CloudKit")
    }

    private func openSupport() {
        app.tabBars.buttons["我的"].tap()
        element("me.developerSupport").tap()
        XCTAssertTrue(element("support.heading").waitForExistence(timeout: 15))
    }

    func testDevelopmentPrivateUploadAndRelaunch() throws {
        openCloud()
        let enable = element("cloud.enable")
        XCTAssertTrue(enable.waitForExistence(timeout: 60), "A real iCloud account must be available")
        capture("live-cloud-01-before-upload")
        enable.tap()
        app.alerts.buttons["开启同步"].tap()
        waitForLabel("cloud.status", containing: "已同步到 iCloud")
        XCTAssertFalse(element("cloud.pending").exists)
        XCTAssertFalse(element("cloud.issue").exists)
        capture("live-cloud-02-private-synced")

        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["记账"].tap()
        XCTAssertTrue(element("entry.amountKeypad").waitForExistence(timeout: 10))
        element("entry.kind.expense").tap()
        element("category.child.早餐").tap()
        for digit in ["1", "2", ".", "3", "4"] { element("entry.key.\(digit)").tap() }
        element("entry.save").tap()
        XCTAssertTrue(app.tabBars.buttons["账本"].waitForExistence(timeout: 10))
        openCloud()
        waitForLabel("cloud.status", containing: "已同步到 iCloud")
        XCTAssertFalse(element("cloud.pending").exists)
        XCTAssertFalse(element("cloud.issue").exists)
        capture("live-cloud-03-record-synced")

        app.terminate()
        app.launch()
        waitForLabel("ledger.netExpense", containing: "12.34", timeout: 20)
        openCloud()
        waitForLabel("cloud.status", containing: "已同步到 iCloud")
        capture("live-cloud-04-relaunch")
    }

    func testSandboxThreeProductsLoadAndPreparePurchase() throws {
        openSupport()
        for tier in ["encourage", "coffee", "generous"] {
            let offer = element("support.offer.\(tier)")
            XCTAssertTrue(offer.waitForExistence(timeout: 60), "App Store Connect product missing: \(tier)")
            XCTAssertFalse(offer.label.isEmpty)
        }
        XCTAssertFalse(element("support.purchase").isEnabled)
        element("support.offer.coffee").tap()
        XCTAssertTrue(element("support.purchase").isEnabled)
        capture("live-iap-01-real-products-coffee-selected")
        // The human signs in and confirms only the system Sandbox purchase dialog.
        // This test deliberately leaves the purchase button for that handoff.
    }

    /// The human alone presses purchase, authenticates and confirms Sandbox.
    /// The runner only prepares selection, then observes the resulting feedback.
    func testHumanSandboxPurchaseDismissesAndThanks() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["YUJI_LIVE_HUMAN_PURCHASE"] == "1")
        let expectedCount = try XCTUnwrap(ProcessInfo.processInfo.environment["YUJI_LIVE_EXPECTED_RECORDS"])
        openSupport()
        let offer = element("support.offer.encourage")
        XCTAssertTrue(offer.waitForExistence(timeout: 60))
        XCTAssertTrue(offer.label.contains("¥6.00"), "Stop before handoff if the real storefront differs")
        offer.tap()
        XCTAssertTrue(element("support.purchase").isEnabled)
        capture("live-iap-04-current-yuan-offer-before-human-purchase")
        print("YUJI_LIVE_READY_FOR_HUMAN_SANDBOX_PURCHASE")
        let thanks = expectation(for: NSPredicate(format: "exists == true AND label CONTAINS %@", "咖啡收到"),
                                 evaluatedWith: element("app.toast"))
        wait(for: [thanks], timeout: 300)
        XCTAssertFalse(element("support.heading").exists, "Verified purchase must dismiss the sheet")
        capture("live-iap-05-real-sandbox-dismissed-and-thanked")
        app.tabBars.buttons["流水"].tap()
        XCTAssertEqual(element("feed.count").label, "\(expectedCount) 笔")
        capture("live-iap-06-real-purchase-did-not-add-record")
    }

    func testReadBackSupportAfterHumanSandboxPurchase() throws {
        openSupport()
        XCTAssertTrue(app.staticTexts["也谢谢你之前的支持。"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["咖啡收到啦"].exists, "Cold launch must not replay thanks")
        capture("live-iap-02-persisted-support-after-relaunch")
        app.navigationBars["支持开发者"].buttons["关闭"].tap()
        app.tabBars.buttons["流水"].tap()
        XCTAssertEqual(element("feed.count").label, "1 笔", "Support must not create ledger records")
        capture("live-iap-03-ledger-unaffected")
    }

    /// Creates only the existing isolated ledger's private CKShare and opens
    /// Apple's controller. It does not send a message or invite a recipient.
    func testPreparePrivateSharingController() throws {
        openCloud()
        waitForLabel("cloud.status", containing: "已同步到 iCloud")
        let members = element("cloud.members")
        XCTAssertTrue(members.waitForExistence(timeout: 15))
        XCTAssertTrue(members.isEnabled)
        members.tap()
        let invite = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "与更多人共享")).firstMatch
        XCTAssertTrue(invite.waitForExistence(timeout: 60), "Must be Apple's sharing controller, not an error alert")
        XCTAssertTrue(invite.isHittable)
        capture("live-share-01-system-private-sharing-controller")
    }

    /// Exercises Apple's copy-link action; the hosted test reads the same share.
    func testOpenPrivateInvitationOptions() throws {
        openCloud()
        waitForLabel("cloud.status", containing: "已同步到 iCloud")
        let members = element("cloud.members")
        XCTAssertTrue(members.waitForExistence(timeout: 15))
        XCTAssertTrue(members.isEnabled)
        members.tap()
        let invite = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "与更多人共享")).firstMatch
        XCTAssertTrue(invite.waitForExistence(timeout: 60))
        XCTAssertTrue(invite.isHittable)
        invite.tap()
        let copyLink = app.cells.matching(NSPredicate(format: "label == %@", "拷贝链接")).firstMatch
        XCTAssertTrue(copyLink.waitForExistence(timeout: 60))
        XCTAssertTrue(copyLink.isHittable)
        capture("live-share-02-private-invitation-options")
        copyLink.tap()
        XCTAssertTrue(element("cloud.status").waitForExistence(timeout: 30))
        capture("live-share-03-private-link-copied")
    }

    /// Adds only the recipient explicitly provided for this isolated live run.
    func testInviteAuthorizedLiveRecipient() throws {
        let recipient = try XCTUnwrap(ProcessInfo.processInfo.environment["YUJI_LIVE_INVITE_EMAIL"])
        XCTAssertTrue(recipient.contains("@"))
        openCloud()
        waitForLabel("cloud.status", containing: "已同步到 iCloud")
        let invite = element("cloud.invite")
        XCTAssertTrue(invite.waitForExistence(timeout: 15))
        XCTAssertTrue(invite.isEnabled)
        invite.tap()
        let email = element("cloud.invite.email")
        XCTAssertTrue(email.waitForExistence(timeout: 15))
        capture("live-share-04-explicit-recipient-form")
        email.tap()
        email.typeText(recipient)
        app.buttons["完成输入"].tap()
        element("cloud.invite.create").tap()
        XCTAssertTrue(element("cloud.invite.success").waitForExistence(timeout: 90))
        XCTAssertFalse(element("cloud.invite.error").exists)
        capture("live-share-05-explicit-invitation-created")
        element("cloud.invite.close").tap()
        let memberVisible = expectation(
            for: NSPredicate { _, _ in
                self.app.staticTexts["等待接受邀请"].exists || self.app.staticTexts["已加入"].exists
            }, evaluatedWith: app)
        wait(for: [memberVisible], timeout: 30)
        capture("live-share-06-pending-recipient")
    }

    func testSharedBookWriteFromB() throws {
        openCloud()
        waitForLabel("cloud.status", containing: "已同步到 iCloud")
        XCTAssertTrue(element("cloud.permission").label.contains("我可以共同记账"))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(element("ledger.netExpense").label.contains("12.34"))
        app.tabBars.buttons["记账"].tap()
        XCTAssertTrue(element("entry.amountKeypad").waitForExistence(timeout: 10))
        element("entry.kind.expense").tap()
        element("category.child.早餐").tap()
        for digit in ["7", ".", "6", "6"] { element("entry.key.\(digit)").tap() }
        element("entry.save").tap()
        XCTAssertTrue(app.tabBars.buttons["账本"].waitForExistence(timeout: 10))
        openCloud()
        waitForLabel("cloud.status", containing: "已同步到 iCloud")
        XCTAssertFalse(element("cloud.pending").exists)
        XCTAssertFalse(element("cloud.issue").exists)
        capture("live-share-07-b-wrote-and-synced")
    }

    func testOwnerReadsBAndWritesIncome() throws {
        openCloud()
        element("cloud.sync").tap()
        waitForLabel("cloud.status", containing: "已同步到 iCloud")
        XCTAssertTrue(element("cloud.permission").label.contains("我是拥有者"))
        app.navigationBars.buttons.firstMatch.tap()
        waitForLabel("ledger.netExpense", containing: "20.00", timeout: 30)
        capture("live-share-08-a-read-b-record")
        app.tabBars.buttons["记账"].tap()
        XCTAssertTrue(element("entry.amountKeypad").waitForExistence(timeout: 10))
        element("entry.kind.income").tap()
        let category = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "category.child.")).firstMatch
        XCTAssertTrue(category.waitForExistence(timeout: 10))
        category.tap()
        for digit in ["1", "0", "0"] { element("entry.key.\(digit)").tap() }
        element("entry.save").tap()
        XCTAssertTrue(app.tabBars.buttons["账本"].waitForExistence(timeout: 10))
        openCloud()
        waitForLabel("cloud.status", containing: "已同步到 iCloud")
        XCTAssertFalse(element("cloud.pending").exists)
        XCTAssertFalse(element("cloud.issue").exists)
        capture("live-share-09-a-income-synced")
    }

    func testBReadsOwnerIncomeAfterRelaunch() throws {
        openCloud()
        element("cloud.sync").tap()
        waitForLabel("cloud.status", containing: "已同步到 iCloud")
        XCTAssertTrue(element("cloud.permission").label.contains("我可以共同记账"))
        app.navigationBars.buttons.firstMatch.tap()
        waitForLabel("ledger.income", containing: "100.00", timeout: 30)
        XCTAssertTrue(element("ledger.netExpense").label.contains("20.00"))
        XCTAssertTrue(element("ledger.surplus").label.contains("80.00"))
        XCTAssertTrue(element("ledger.recordCount").label.contains("3 笔"))
        capture("live-share-10-b-read-a-income-after-relaunch")
    }

    func testBReadOnlyBlocksEntryAfterPermissionRefresh() throws {
        openCloud()
        element("cloud.sync").tap()
        waitForLabel("cloud.status", containing: "仅可查看")
        XCTAssertTrue(element("cloud.permission").label.contains("我仅可查看"))
        XCTAssertFalse(element("cloud.pending").exists)
        capture("live-share-11-b-read-only")
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["记账"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(element("entry.amountKeypad").exists)
        capture("live-share-12-b-cannot-record")
    }

    func testBReadWriteRestoredWithoutChangingData() throws {
        openCloud()
        element("cloud.sync").tap()
        waitForLabel("cloud.status", containing: "已同步到 iCloud")
        XCTAssertTrue(element("cloud.permission").label.contains("我可以共同记账"))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(element("ledger.surplus").label.contains("80.00"))
        app.tabBars.buttons["记账"].tap()
        XCTAssertTrue(element("entry.amountKeypad").waitForExistence(timeout: 10))
        capture("live-share-13-b-editing-restored")
    }

    func testBRevocationFreezesSharedBookAndKeepsRecords() throws {
        openCloud()
        element("cloud.sync").tap()
        waitForLabel("cloud.issue", containing: "权限")
        XCTAssertTrue(element("cloud.permission").label.contains("我仅可查看"))
        capture("live-share-14-b-revoked")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(element("ledger.recordCount").label.contains("3 笔"))
        XCTAssertTrue(element("ledger.surplus").label.contains("80.00"))
        app.tabBars.buttons["记账"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(element("entry.amountKeypad").exists)
        capture("live-share-15-revoked-cannot-record")
    }

    /// The external harness opens the private URL after this readiness marker.
    /// A cold system launch deliberately uses B's empty normal repository.
    func testAcceptExternalInvitation() throws {
        let mode = ProcessInfo.processInfo.environment["YUJI_LIVE_EXTERNAL_INVITATION"]
        try XCTSkipUnless(mode == "cold" || mode == "warm")
        if mode == "cold" { app.terminate() }
        print("YUJI_LIVE_READY_FOR_EXTERNAL_INVITATION")
        let shareService = XCUIApplication(bundleIdentifier: "com.apple.CloudKit.ShareBear")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let openButtons = [app.buttons["打开"], springboard.buttons["打开"], shareService.buttons["打开"]]
        let ready = expectation(for: NSPredicate { _, _ in
            self.element("cloud.accept").exists || openButtons.contains { $0.exists }
        }, evaluatedWith: app)
        wait(for: [ready], timeout: 60)
        if !element("cloud.accept").exists, let open = openButtons.first(where: { $0.exists }) { open.tap() }
        XCTAssertTrue(element("cloud.accept").waitForExistence(timeout: 60), "System URL must reach the global invitation sheet")
        capture("live-share-16-\(mode ?? "")-invitation")
        element("cloud.accept").tap()
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element("cloud.accept"))
        wait(for: [closed], timeout: 90)
        XCTAssertTrue(element("ledger.cloudStatus").waitForExistence(timeout: 90))
        waitForLabel("ledger.cloudStatus", containing: "已同步到 iCloud", timeout: 30)
        waitForLabel("ledger.surplus", containing: "80.00", timeout: 30)
        XCTAssertTrue(element("ledger.recordCount").label.contains("3 笔"))
        capture("live-share-17-\(mode ?? "")-joined")
    }
}
