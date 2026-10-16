import XCTest

final class StatsPeopleUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(large: Bool = false) {
        app = XCUIApplication(); app.useIsolatedFixture()
        app.launchEnvironment["YUJI_TEST_STORE_MODE"] = "empty"
        app.launchEnvironment["YUJI_TEST_CLOUD_MODE"] = "peopleStats"
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if large {
            app.launchEnvironment["YUJI_STRESS_DARK"] = "1"
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["统计"].waitForExistence(timeout: 15))
        app.tabBars.buttons["统计"].tap()
        XCTAssertTrue(item("stats.authorFilter").waitForExistence(timeout: 8))
    }
    private func item(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func select(_ name: String) {
        item("stats.authorFilter").tap()
        let option = app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<10 {
            if element.exists && element.isHittable && element.frame.midY > app.scrollContentTop && element.frame.midY < app.frame.maxY - 80 { return }
            app.swipeUp()
        }
        XCTFail("找不到统计明细")
    }
    func testPersonFilterLinksSummaryRefundChartAndRecords() {
        launch()
        XCTAssertEqual(item("stats.net").label, "净支出，¥35.00")
        select("小满")
        XCTAssertEqual(item("stats.net").label, "净支出，¥15.00")
        capture("stats-people-selected")
        let record = item("stats.transaction.stats-person-b"); reveal(record)
        XCTAssertTrue(record.exists)
        XCTAssertTrue(item("stats.transaction.stats-person-refund").exists)
        XCTAssertFalse(item("stats.transaction.stats-person-a").exists)
        XCTAssertFalse(item("stats.transaction.stats-person-unknown").exists)
        let clear = item("stats.detailClearAuthor")
        XCTAssertTrue(clear.exists); XCTAssertTrue(clear.label.contains("小满"))
        capture("stats-people-linked-records")
        reveal(clear); clear.tap()
        let allSummary = item("stats.detailSummary"); reveal(allSummary)
        XCTAssertFalse(item("stats.detailClearAuthor").exists)
        XCTAssertTrue(allSummary.label.contains("35.00"))
        for _ in 0..<8 { if item("stats.authorFilter").isHittable { break }; app.swipeDown() }
        select("未知记账人"); XCTAssertEqual(item("stats.net").label, "净支出，¥8.00")
        item("stats.clearAuthor").tap(); XCTAssertEqual(item("stats.net").label, "净支出，¥35.00")
        select("小余（我）"); XCTAssertEqual(item("stats.net").label, "净支出，¥12.00")
        capture("stats-people-own")
    }
    func testDarkLargestTypeFilterRemainsReachable() {
        launch(large: true)
        app.tabBars.buttons["我的"].tap()
        let nickname = item("me.nickname"); reveal(nickname); nickname.tap()
        let input = item("nickname.input")
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap()
        let longName = "共享账本里的长昵称二十字测试刚刚好"
        input.typeText(longName); item("nickname.save").tap()
        app.tabBars.buttons["统计"].tap()
        select(longName + "（我）")
        XCTAssertTrue(item("stats.clearAuthor").isHittable)
        let filter = item("stats.authorFilter")
        XCTAssertGreaterThanOrEqual(filter.frame.height, 44)
        XCTAssertGreaterThanOrEqual(filter.frame.minX, 0)
        XCTAssertLessThanOrEqual(filter.frame.maxX, app.frame.maxX)
        capture("stats-people-dark-largest")
        item("stats.clearAuthor").tap()
        XCTAssertTrue(filter.label.contains("全部记账人"))
    }
}
