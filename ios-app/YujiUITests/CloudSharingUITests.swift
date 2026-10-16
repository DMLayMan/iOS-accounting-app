import XCTest

final class CloudSharingUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ mode: String, large: Bool = false, dark: Bool = false) {
        app = XCUIApplication(); app.useIsolatedFixture(); app.launchEnvironment["YUJI_TEST_STORE_MODE"] = "empty"
        app.launchEnvironment["YUJI_TEST_CLOUD_MODE"] = mode
        if dark { app.launchEnvironment["YUJI_STRESS_DARK"] = "1" }
        app.launchArguments = ["-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); XCTAssertTrue(app.tabBars.buttons["账本"].waitForExistence(timeout:15))
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching:.any).matching(identifier:id).firstMatch }
    private func openSettings() { XCTAssertTrue(element("ledger.cloud").waitForExistence(timeout:5)); element("ledger.cloud").tap(); XCTAssertTrue(element("cloud.status").waitForExistence(timeout:5)) }
    private func capture(_ name: String) { let a = XCTAttachment(screenshot:app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func reveal(_ target: XCUIElement) {
        for _ in 0..<10 {
            let top = app.scrollContentTop
            let bottom = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.frame.maxY - 30
            if target.exists && target.isHittable && target.frame.midY > top && target.frame.midY < bottom { return }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: app.frame.width * 0.9, dy: top + (bottom - top) * 0.78))
                .press(forDuration: 0.03, thenDragTo: origin.withOffset(CGVector(dx: app.frame.width * 0.9, dy: top + (bottom - top) * 0.25)))
        }
        XCTFail("Unreachable cloud control: \(target)")
    }
    private func waitForPaused() {
        let paused = expectation(for: NSPredicate(format: "label CONTAINS %@", "暂停"), evaluatedWith: element("cloud.status"))
        wait(for: [paused], timeout: 5)
    }
    func testEnableCancelPauseAndRelaunchPreservesCloudBinding() {
        launch("ready"); openSettings(); reveal(element("cloud.enable")); element("cloud.enable").tap()
        app.alerts.buttons["取消"].tap(); XCTAssertTrue(element("cloud.enable").exists)
        element("cloud.enable").tap(); app.alerts.buttons["开启同步"].tap()
        XCTAssertTrue(element("cloud.sync").waitForExistence(timeout:8)); capture("cloud-01-owner-synced")
        let pause = app.switches["cloud.pause"]
        reveal(pause); pause.coordinate(withNormalizedOffset: CGVector(dx:0.9,dy:0.5)).tap(); waitForPaused()
        app.terminate(); app.launch(); openSettings(); waitForPaused(); capture("cloud-02-paused-relaunch")
    }
    func testReadOnlyEntryBlockedAndPermissionVisible() {
        launch("readonly"); XCTAssertTrue(element("ledger.cloudStatus").waitForExistence(timeout:5))
        app.tabBars.buttons["记账"].tap(); XCTAssertTrue(app.alerts["提示"].waitForExistence(timeout:5)); app.alerts.buttons["好"].tap()
        openSettings(); reveal(element("cloud.permission")); XCTAssertTrue(element("cloud.permission").label.contains("仅可查看")); capture("cloud-03-readonly")
    }
    func testConflictCompareAndPreserveCopyAdoptsRemote() {
        launch("conflict"); openSettings(); XCTAssertTrue(element("cloud.compare").waitForExistence(timeout:6))
        element("cloud.compare").tap(); XCTAssertTrue(app.staticTexts["金额"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["¥20.00"].exists); XCTAssertTrue(app.staticTexts["¥30.00"].exists)
        capture("cloud-04-conflict-comparison")
        app.navigationBars.buttons.firstMatch.tap(); reveal(element("cloud.resolve")); element("cloud.resolve").tap()
        app.alerts.buttons["取消"].tap(); XCTAssertTrue(element("cloud.compare").exists)
        element("cloud.resolve").tap(); app.alerts.buttons["保留副本并处理"].tap()
        reveal(element("cloud.message")); XCTAssertTrue(element("cloud.message").exists); XCTAssertFalse(element("cloud.compare").exists); capture("cloud-05-conflict-resolved")
        app.navigationBars.buttons.firstMatch.tap(); element("ledger.switch").tap()
        let copy = app.buttons.matching(NSPredicate(format:"label == %@", "个人账本（未同步副本）")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout:5)); copy.tap()
        XCTAssertTrue(element("ledger.netExpense").waitForExistence(timeout:5))
        XCTAssertTrue(element("ledger.netExpense").label.contains("20.00"))
        capture("cloud-11-preserved-local-copy")
    }
    func testOfflineAndRevokedExplainRecoveryWithoutFalseSyncedState() {
        launch("offline"); openSettings(); XCTAssertTrue(element("cloud.issue").waitForExistence(timeout:5))
        XCTAssertTrue(element("cloud.issue").label.contains("连接")); capture("cloud-06-offline")
        app.terminate(); launch("revoked"); openSettings()
        XCTAssertTrue(element("cloud.issue").waitForExistence(timeout:5)); XCTAssertTrue(element("cloud.issue").label.contains("权限")); capture("cloud-07-revoked")
    }
    func testSignedOutAndLargestTypeControlsRemainReachable() {
        launch("signedOut",large:true); openSettings(); XCTAssertTrue(element("cloud.accountMessage").label.contains("登录 iCloud"))
        XCTAssertFalse(element("cloud.enable").exists); reveal(element("cloud.retry")); XCTAssertGreaterThanOrEqual(element("cloud.retry").frame.height,44)
        capture("cloud-08-signed-out-accessibility")
    }
}

extension CloudSharingUITests {
    func testSameSourceCancelThenExplicitCloudCopyPreservesOriginal() {
        launch("collision"); openSettings(); reveal(element("cloud.enable")); element("cloud.enable").tap()
        app.alerts.buttons["开启同步"].tap(); XCTAssertTrue(app.alerts["云端已有同源账本"].waitForExistence(timeout:5))
        app.alerts.buttons["取消"].tap(); XCTAssertTrue(element("cloud.enable").exists)
        element("cloud.enable").tap(); app.alerts.buttons["开启同步"].tap()
        XCTAssertTrue(app.alerts["云端已有同源账本"].waitForExistence(timeout:5))
        app.alerts.buttons["另建副本并同步"].tap()
        XCTAssertTrue(app.staticTexts["个人账本（iCloud 副本）"].waitForExistence(timeout:8))
        element("ledger.switch").tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"label == %@", "个人账本")).firstMatch.waitForExistence(timeout:5))
        capture("cloud-13-independent-cloud-copy")
    }
    func testLeaveCancelThenPreservesLocalCopyAndReturnsToBook() {
        launch("readonly"); openSettings(); reveal(element("cloud.leave")); element("cloud.leave").tap()
        app.alerts.buttons["取消"].tap(); XCTAssertTrue(element("cloud.permission").exists)
        element("cloud.leave").tap(); app.alerts.buttons["保留副本并退出"].tap()
        XCTAssertTrue(element("ledger.switch").waitForExistence(timeout:8))
        XCTAssertTrue(app.staticTexts["个人账本（本地副本）"].waitForExistence(timeout:5))
        app.tabBars.buttons["记账"].tap(); XCTAssertTrue(app.buttons["entry.save"].waitForExistence(timeout:5))
        capture("cloud-12-local-copy-after-leave")
    }
    func testDarkAppearanceAndLargePermissionScreen() {
        launch("readonly",large:true,dark:true); openSettings(); reveal(element("cloud.permission"))
        XCTAssertTrue(element("cloud.permission").label.contains("仅可查看")); capture("cloud-09-dark-large")
        reveal(element("cloud.members")); XCTAssertFalse(element("cloud.members").isEnabled)
        capture("cloud-10-dark-members")
    }
}
