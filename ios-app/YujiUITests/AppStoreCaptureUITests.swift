import XCTest

/// Render the canonical Release UI against a synthetic database installed into a
/// newly created simulator. Never run on an existing/personal device or normal suite.
final class AppStoreCaptureUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["YUJI_APP_STORE_CAPTURE"] == "1")
        #if targetEnvironment(simulator)
        let expected = try XCTUnwrap(env["YUJI_CAPTURE_SIMULATOR"])
        XCTAssertNotNil(UUID(uuidString: expected))
        XCTAssertEqual(env["SIMULATOR_UDID"], expected, "Only the newly prepared screenshot simulator is allowed")
        #else
        throw XCTSkip("Store screenshots require the dedicated synthetic simulator")
        #endif
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["账本"].waitForExistence(timeout: 15))
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }

    func testCaptureStatisticsChart() {
        app.tabBars.buttons["统计"].tap()
        if app.buttons["stats.date"].label.contains("10 月") || app.buttons["stats.date"].label.contains("10月") {
            app.buttons["stats.previous"].tap()
        }
        let heading = app.staticTexts["收支去向"]
        XCTAssertTrue(heading.exists)
        let targetY = app.buttons["stats.date"].frame.maxY + 24
        for _ in 0..<3 {
            let gap = heading.frame.minY - targetY
            if abs(gap) < 8 { break }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: gap > 0 ? 0.8 : 0.35))
            start.press(forDuration: 0.1,
                thenDragTo: start.withOffset(CGVector(dx: 0, dy: -min(300, max(-300, gap)))),
                withVelocity: XCUIGestureVelocity(rawValue: 100), thenHoldForDuration: 0.3)
        }
        XCTAssertGreaterThanOrEqual(heading.frame.minY, app.buttons["stats.date"].frame.maxY)
        let ring = element("stats.slice.stress-food")
        XCTAssertTrue(ring.isHittable)
        XCTAssertGreaterThanOrEqual(ring.frame.minY, app.buttons["stats.date"].frame.maxY)
        XCTAssertLessThanOrEqual(ring.frame.maxY, app.tabBars.firstMatch.frame.minY)
        capture("appstore-02-statistics")
    }

    func testCaptureCoreTasks() {
        XCTAssertTrue(app.staticTexts["日常账本"].waitForExistence(timeout: 5))
        capture("appstore-04-ledger")
        app.tabBars.buttons["统计"].tap()
        if app.buttons["stats.date"].label.contains("10 月") || app.buttons["stats.date"].label.contains("10月") {
            app.buttons["stats.previous"].tap()
        }
        XCTAssertTrue(app.buttons["stats.date"].label.contains("9"), app.buttons["stats.date"].label)
        XCTAssertTrue(element("stats.net").exists)
        app.buttons["stats.budgetManage"].tap()
        XCTAssertTrue(app.navigationBars["账本预算"].waitForExistence(timeout: 5))
        let budgetTitle = app.navigationBars["账本预算"]
        budgetTitle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)))
        capture("appstore-03-budgets")
        app.navigationBars["账本预算"].buttons["取消"].tap()
        app.swipeUp()
        XCTAssertTrue(element("stats.slice.stress-food").exists)
        capture("appstore-02-statistics")
        app.tabBars.buttons["流水"].tap()
        if app.buttons["feed.date"].label.contains("10 月") || app.buttons["feed.date"].label.contains("10月") {
            app.buttons["feed.previous"].tap()
        }
        XCTAssertTrue(element("feed.count").waitForExistence(timeout: 5))
        capture("appstore-05-feed")
        app.tabBars.buttons["记账"].tap()
        // This fixture-only capture may be rerun after a draft-preserving close.
        if app.buttons["entry.clearDraft"].exists {
            app.buttons["entry.clearDraft"].tap()
            app.buttons["entry.discard"].tap()
            XCTAssertTrue(app.tabBars.buttons["记账"].waitForExistence(timeout: 5))
            app.tabBars.buttons["记账"].tap()
        }
        XCTAssertTrue(element("category.child.正餐").waitForExistence(timeout: 5))
        element("category.child.正餐").tap()
        for key in "38.5" { app.buttons["entry.key.\(key)"].tap() }
        XCTAssertTrue(app.buttons["entry.save"].isEnabled)
        XCTAssertTrue(element("entry.amount").label.contains("38.50"), element("entry.amount").label)
        capture("appstore-01-entry")
        app.buttons["entry.close"].tap()
    }
}
