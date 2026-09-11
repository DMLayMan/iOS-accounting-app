import XCTest

final class LifecycleUITests: XCTestCase {
    private func launch(mode: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.useIsolatedFixture()
        app.launchEnvironment["YUJI_TEST_STORE_MODE"] = mode
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testFirstLaunchAnchorsLedgerAndEmptyEntryCanClose() {
        let app = launch(mode: "empty")
        XCTAssertTrue(app.tabBars.buttons["账本"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["账本"].isSelected)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "ledger.currentName").firstMatch.label.contains("个人账本"))
        capture(app, "80-first-launch")
        app.tabBars.buttons["记账"].tap()
        let close = app.buttons["entry.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5)); close.tap()
        XCTAssertTrue(app.tabBars.buttons["账本"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["账本"].isSelected)
    }
    func testEmptyLedgerDeleteRequiresConfirmationAndKeepsLastLedger() {
        let app = launch(mode: "empty")
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 10))
        app.tabBars.buttons["我的"].tap(); app.buttons["我的账本"].tap()
        app.buttons["管理 个人账本"].tap()
        XCTAssertFalse(app.buttons["删除空账本"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.85)).tap() // dismiss outside the menu
        app.buttons["新建账本"].tap()
        let name = app.textFields["ledger.newName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("临时账本\n")
        XCTAssertTrue(app.buttons["ledger.saveNew"].waitForExistence(timeout: 5)); app.buttons["ledger.saveNew"].tap()
        XCTAssertTrue(app.buttons["管理 临时账本"].waitForExistence(timeout: 5))
        app.buttons["管理 临时账本"].tap(); app.buttons["删除空账本"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        capture(app, "85-empty-ledger-confirmation")
        app.alerts.firstMatch.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["管理 临时账本"].exists)
        app.buttons["管理 临时账本"].tap(); app.buttons["删除空账本"].tap()
        app.alerts.firstMatch.buttons["删除"].tap()
        XCTAssertFalse(app.buttons["管理 临时账本"].exists)
        XCTAssertTrue(app.buttons["管理 个人账本"].exists)
    }

    func testUnreadableStoreOffersRecoveryWithoutEnteringEmptyLedger() {
        let app = launch(mode: "unreadable")
        XCTAssertTrue(app.buttons["recovery.retry"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        capture(app, "81-unreadable-recovery")
        app.buttons["recovery.retry"].tap()
        XCTAssertTrue(app.buttons["recovery.retry"].exists)
        app.buttons["选择备份恢复"].tap()
        XCTAssertTrue(app.buttons["生成备份文件"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["生成备份文件"].isEnabled)
        XCTAssertFalse(app.buttons["导出当前账本 CSV"].isEnabled)
        XCTAssertTrue(app.buttons["选择备份恢复"].isEnabled)
        capture(app, "82-recovery-data")
    }
}
