import XCTest

final class TimeNavigationUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.useIsolatedFixture()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(e("stats.date").waitForExistence(timeout: 12))
    }
    private func e(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func capture(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func mode(_ label: String) { app.segmentedControls["period.mode"].buttons[label].tap() }
    private func month(_ year: Int, _ month: Int, from: String = "stats") {
        e(from + ".date").tap()
        mode("月")
        e("period.year").tap()
        e("period.chooseYear.\(year)").tap()
        let target = e("period.month.\(month)")
        if !target.isHittable { app.swipeUp() }
        target.tap()
        XCTAssertTrue(e(from + ".date").waitForExistence(timeout: 5))
    }

    func testMonthJumpSharesRangeAndCancelLeavesAppliedDate() {
        capture("01-stats-month-center-tab")
        XCTAssertFalse(e("stats.period").exists)
        e("stats.date").tap(); capture("02-month-picker")
        e("period.year").tap(); e("period.chooseYear.2024").tap()
        capture("03-year-jump")
        e("period.month.2").tap()
        XCTAssertTrue(e("stats.date").label.contains("2024 年 2 月"))
        app.tabBars.buttons["流水"].tap()
        XCTAssertTrue(e("feed.date").label.contains("2024 年 2 月"))
        XCTAssertEqual(e("feed.count").label, "7 笔")
        XCTAssertTrue(e("feed.previous").isHittable)
        capture("04-feed-same-leap-month")
        e("feed.date").tap(); e("period.year").tap(); e("period.chooseYear.2022").tap()
        e("period.cancel").tap()
        XCTAssertTrue(e("feed.date").label.contains("2024 年 2 月"))
        XCTAssertEqual(e("feed.count").label, "7 笔")
        month(2023, 2, from: "feed")
        XCTAssertTrue(e("feed.empty").waitForExistence(timeout: 5))
        capture("05-empty-month")
        e("feed.resetAll").tap(); XCTAssertEqual(e("feed.count").label, "470 笔")
        app.tabBars.buttons["统计"].tap()
        XCTAssertEqual(e("stats.date").label, "全部时间")
        XCTAssertTrue(e("stats.net").label.contains("263,163.82"))
        capture("06-all-time-statistics")
    }

    func testYearCustomFutureAndComparisonFlow() {
        e("stats.date").tap(); mode("年"); capture("10-year-picker")
        e("period.fullYear.2025").tap()
        XCTAssertTrue(e("stats.net").label.contains("58,596.97"))
        capture("11-year-statistics")
        app.tabBars.buttons["流水"].tap(); XCTAssertEqual(e("feed.date").label, "2025 年")
        e("feed.date").tap(); mode("自定"); capture("12-custom-range")
        XCTAssertTrue(e("period.applyRange").isEnabled); e("period.applyRange").tap()
        XCTAssertTrue(e("feed.customRange").label.contains("2025.12.31"))
        app.tabBars.buttons["统计"].tap()
        XCTAssertTrue(e("stats.net").label.contains("58,596.97"))
        XCTAssertFalse(e("stats.compare.年度同比").exists)
        month(2026, 12)
        XCTAssertTrue(e("stats.futurePeriod").waitForExistence(timeout: 5))
        XCTAssertFalse(e("stats.net").exists)
        capture("13-future-range")
        e("stats.resetPeriod").tap()
        XCTAssertTrue(e("stats.net").label.contains("501.05"))
        e("stats.compare.环比").tap()
        app.swipeUp()
        XCTAssertTrue(e("stats.comparisonPeriod").waitForExistence(timeout: 5))
        app.segmentedControls["stats.comparisonPeriod"].buttons["基期"].tap()
        capture("14-comparison-linked")
    }

    func testCenterActionKeepsOriginAndDraftThroughKeyboardAndSave() {
        for title in ["账本", "流水", "统计", "我的"] {
            app.tabBars.buttons[title].tap()
            let button = app.tabBars.buttons["记账"]
            XCTAssertTrue(button.isHittable)
            XCTAssertEqual(button.frame.midX, app.frame.midX, accuracy: 3)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            capture("20-tab-" + title)
            button.tap()
            XCTAssertTrue(e("entry.amount").waitForExistence(timeout: 5))
            XCTAssertFalse(app.tabBars.firstMatch.isHittable)
            e("entry.close").tap()
            XCTAssertTrue(app.tabBars.buttons[title].isSelected)
        }
        app.tabBars.buttons["流水"].tap()
        let date = e("feed.date").label
        app.tabBars.buttons["记账"].tap()
        e("entry.note").tap(); e("entry.note").typeText("中间记账入口验收")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertFalse(e("entry.amountKeypad").exists)
        capture("21-entry-keyboard-exclusive")
        e("entry.note").typeText("\n")
        XCTAssertTrue(e("entry.amountKeypad").waitForExistence(timeout: 5))
        capture("22-entry-amount-keypad")
        e("entry.close").tap()
        XCTAssertTrue(app.tabBars.buttons["流水"].isSelected)
        app.tabBars.buttons["记账"].tap()
        XCTAssertTrue((e("entry.note").value as? String ?? "").contains("中间记账入口验收"))
        XCTAssertTrue(e("entry.save").isEnabled); e("entry.save").tap()
        XCTAssertTrue(e("feed.date").waitForExistence(timeout: 5))
        XCTAssertEqual(e("feed.date").label, date)
        XCTAssertTrue(app.tabBars.buttons["流水"].isSelected)
        capture("23-save-back-to-feed")
    }

    func testDarkAppearanceAndLargestTypeHaveReachableDateAndEntry() {
        app.terminate()
        app.useIsolatedFixture()
        app.launchEnvironment["YUJI_STRESS_DARK"] = "1"
        app.launch(); XCTAssertTrue(e("stats.date").waitForExistence(timeout: 10))
        capture("30-dark-statistics")
        e("stats.date").tap(); capture("31-dark-picker"); e("period.cancel").tap()
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); XCTAssertTrue(e("stats.date").waitForExistence(timeout: 10))
        capture("32-large-statistics")
        e("stats.date").tap(); capture("33-large-picker")
        XCTAssertTrue(e("period.year").isHittable); e("period.month.2").tap()
        app.tabBars.buttons["流水"].tap(); capture("34-large-feed")
        XCTAssertTrue(e("feed.date").isHittable)
        app.tabBars.buttons["记账"].tap()
        XCTAssertTrue(e("entry.close").waitForExistence(timeout: 5)); capture("35-large-entry")
        e("entry.close").tap(); XCTAssertTrue(app.tabBars.buttons["流水"].isSelected)
    }
}
