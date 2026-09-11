import XCTest

final class ICostTimeUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.useIsolatedFixture()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(e("stats.periodMode").waitForExistence(timeout: 12))
    }
    private func e(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func capture(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func mode(_ title: String) { app.segmentedControls["stats.periodMode"].buttons[title].tap() }
    private func month(_ year: Int, _ month: Int, from: String = "stats") {
        e(from + ".date").tap()
        app.segmentedControls["period.mode"].buttons["月"].tap()
        e("period.year").tap(); e("period.chooseYear.\(year)").tap()
        e("period.month.\(month)").tap()
    }

    func testBothTabsShareHeaderGeometryAndModeTransitions() {
        let names = ["periodMode", "date", "previous", "next"]
        let statsFrames = Dictionary(uniqueKeysWithValues: names.map { ($0, e("stats." + $0).frame) })
        capture("70-unified-statistics")
        app.tabBars.buttons["流水"].tap()
        XCTAssertTrue(e("feed.periodMode").waitForExistence(timeout: 5))
        for name in names {
            let frame = e("feed." + name).frame
            let expected = statsFrames[name]!
            XCTAssertEqual(frame.minX, expected.minX, accuracy: 1, name)
            XCTAssertEqual(frame.minY, expected.minY, accuracy: 1, name)
            XCTAssertEqual(frame.width, expected.width, accuracy: 1, name)
            XCTAssertEqual(frame.height, expected.height, accuracy: 1, name)
        }
        capture("71-unified-feed")
        let modes = app.segmentedControls["feed.periodMode"]
        XCTAssertEqual(modes.buttons.allElementsBoundByIndex.map(\.label), ["月", "年", "全部", "范围"])
        modes.buttons["年"].tap()
        XCTAssertEqual(e("feed.date").label, "2026 年")
        e("feed.previous").tap()
        XCTAssertEqual(e("feed.date").label, "2025 年")
        app.tabBars.buttons["统计"].tap()
        XCTAssertTrue(app.segmentedControls["stats.periodMode"].buttons["年"].isSelected)
        XCTAssertTrue(e("stats.net").label.contains("58,596.97"))
        app.tabBars.buttons["流水"].tap()
        modes.buttons["范围"].tap()
        XCTAssertTrue(e("period.applyRange").waitForExistence(timeout: 5))
        e("period.cancel").tap()
        XCTAssertTrue(modes.buttons["年"].isSelected)
        XCTAssertEqual(e("feed.date").label, "2025 年")
        modes.buttons["全部"].tap()
        XCTAssertEqual(e("feed.count").label, "470 笔")
        XCTAssertFalse(e("feed.previous").exists)
        modes.buttons["范围"].tap(); e("period.cancel").tap()
        XCTAssertTrue(modes.buttons["全部"].isSelected)
        modes.buttons["范围"].tap(); e("period.applyRange").tap()
        XCTAssertTrue(modes.buttons["范围"].isSelected)
        app.tabBars.buttons["统计"].tap()
        XCTAssertTrue(app.segmentedControls["stats.periodMode"].buttons["范围"].isSelected)
        XCTAssertTrue(e("stats.net").label.contains("263,163.82"))
    }

    func testVisiblePreviousNextAndSharedMonthYear() {
        XCTAssertFalse(e("stats.date.wheel").exists)
        XCTAssertFalse(e("stats.date.swipeHint").exists)
        capture("01-statistics-icost")
        for id in ["stats.previous", "stats.next"] {
            XCTAssertTrue(e(id).isHittable)
            XCTAssertGreaterThanOrEqual(e(id).frame.width, 44)
            XCTAssertGreaterThanOrEqual(e(id).frame.height, 44)
        }
        e("stats.previous").tap()
        XCTAssertEqual(e("stats.date").label, "2026 年 8 月")
        XCTAssertTrue(e("stats.net").label.contains("7,574.66"))
        capture("02-previous-month")
        e("stats.next").tap()
        XCTAssertTrue(e("stats.net").label.contains("501.05"))
        month(2024, 1)
        e("stats.previous").tap()
        XCTAssertEqual(e("stats.date").label, "2023 年 12 月")
        capture("03-cross-year")
        e("stats.next").tap(); e("stats.next").tap()
        app.tabBars.buttons["流水"].tap()
        XCTAssertEqual(e("feed.date").label, "2024 年 2 月")
        XCTAssertEqual(e("feed.count").label, "7 笔")
        XCTAssertTrue(e("feed.previous").isHittable)
        capture("04-feed-icost")
        e("feed.previous").tap(); XCTAssertEqual(e("feed.date").label, "2024 年 1 月")
        e("feed.next").tap()
        app.tabBars.buttons["统计"].tap()
        mode("年")
        XCTAssertEqual(e("stats.date").label, "2024 年")
        XCTAssertTrue(e("stats.net").label.contains("63,458.00"))
        capture("05-year-mode")
        e("stats.previous").tap(); XCTAssertEqual(e("stats.date").label, "2023 年")
        e("stats.next").tap(); XCTAssertEqual(e("stats.date").label, "2024 年")
        mode("月"); XCTAssertEqual(e("stats.date").label, "2024 年 9 月")
    }

    func testRangeCancelAllEmptyAndFutureDoNotChangeMeaning() {
        mode("范围")
        XCTAssertTrue(e("period.applyRange").waitForExistence(timeout: 5))
        capture("10-range-picker")
        e("period.cancel").tap()
        XCTAssertEqual(e("stats.date").label, "2026 年 9 月")
        XCTAssertTrue(app.segmentedControls["stats.periodMode"].buttons["月"].isSelected)
        mode("全部")
        XCTAssertFalse(e("stats.previous").exists)
        XCTAssertTrue(e("stats.net").label.contains("263,163.82"))
        capture("11-all-time")
        mode("范围"); e("period.cancel").tap()
        XCTAssertTrue(app.segmentedControls["stats.periodMode"].buttons["全部"].isSelected)
        XCTAssertTrue(e("stats.net").label.contains("263,163.82"))
        mode("范围"); e("period.applyRange").tap()
        XCTAssertTrue(app.segmentedControls["stats.periodMode"].buttons["范围"].isSelected)
        XCTAssertTrue(e("stats.net").label.contains("263,163.82"))
        XCTAssertFalse(e("stats.next").exists)
        month(2026, 12)
        XCTAssertTrue(e("stats.futurePeriod").exists)
        capture("12-future-period")
        e("stats.resetPeriod").tap()
        month(2023, 2)
        app.tabBars.buttons["流水"].tap()
        XCTAssertTrue(e("feed.empty").waitForExistence(timeout: 5))
        capture("13-empty-feed")
        e("feed.next").tap()
        XCTAssertEqual(e("feed.date").label, "2023 年 3 月")
        XCTAssertTrue(e("feed.empty").exists)
        e("feed.resetAll").tap(); XCTAssertEqual(e("feed.count").label, "470 笔")
    }

    func testDarkAndLargestTypeKeepControlsReachable() {
        app.terminate()
        app.useIsolatedFixture()
        app.launchEnvironment["YUJI_STRESS_DARK"] = "1"
        app.launch(); XCTAssertTrue(e("stats.date").waitForExistence(timeout: 10))
        e("stats.previous").tap(); capture("20-dark-statistics")
        app.tabBars.buttons["流水"].tap(); capture("21-dark-feed")
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); XCTAssertTrue(e("stats.date").waitForExistence(timeout: 10))
        e("stats.previous").tap()
        XCTAssertEqual(e("stats.date").label, "2026 年 8 月")
        XCTAssertTrue(e("stats.date").isHittable)
        capture("22-large-statistics")
        e("stats.date").tap(); XCTAssertTrue(e("period.year").waitForExistence(timeout: 5))
        e("period.cancel").tap()
        app.tabBars.buttons["流水"].tap()
        e("feed.previous").tap()
        XCTAssertEqual(e("feed.date").label, "2026 年 7 月")
        XCTAssertTrue(e("feed.date").isHittable)
        XCTAssertTrue(e("feed.count").isHittable)
        capture("23-large-feed")
        app.tabBars.buttons["记账"].tap()
        XCTAssertTrue(e("entry.close").waitForExistence(timeout: 5)); e("entry.close").tap()
        XCTAssertEqual(e("feed.date").label, "2026 年 7 月")
    }
}
