import XCTest

final class LedgerFeedUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.useIsolatedFixture()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(e("stats.net").waitForExistence(timeout: 12))
    }
    private func e(_ id: String) -> XCUIElement { id == "root.newEntry" ? app.tabBars.buttons["记账"] : app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    @discardableResult private func bring(_ id: String) -> XCUIElement {
        let target = e(id)
        for _ in 0..<14 {

            let root = e("root.newEntry")
            let top = app.scrollContentTop
            let bottom = root.exists && root.isHittable ? root.frame.minY - 8 : app.frame.maxY - 50
            if target.exists && target.isHittable && target.frame.midY > top && target.frame.midY < bottom { return target }
            let above = target.exists && target.frame.midY <= top
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let y1 = top + (bottom - top) * (above ? 0.2 : 0.8)
            let y2 = top + (bottom - top) * (above ? 0.8 : 0.2)
            origin.withOffset(CGVector(dx: app.frame.width * 0.9, dy: y1)).press(forDuration: 0.03,
                thenDragTo: origin.withOffset(CGVector(dx: app.frame.width * 0.9, dy: y2)), withVelocity: .slow, thenHoldForDuration: 0)
        }
        capture("99-unreachable-" + id); XCTFail(id); return target
    }
    private func chooseMonth(_ year: Int, _ month: Int) {
        e("feed.date").tap()
        app.segmentedControls["period.mode"].buttons["月"].tap()
        XCTAssertTrue(e("period.year").waitForExistence(timeout: 5))
        e("period.year").tap()
        app.buttons["\(year) 年"].tap()
        bring("period.month.\(month)").tap()
        XCTAssertTrue(e("feed.date").waitForExistence(timeout: 5))
    }
    private func back() { app.navigationBars.buttons.element(boundBy: 0).tap() }

    func testCumulativeOverviewCreateSwitchAndRelaunch() {
        app.tabBars.buttons["账本"].tap()
        XCTAssertTrue(e("ledger.income").label.contains("754,276.21"))
        XCTAssertTrue(e("ledger.surplus").label.contains("491,112.39"))
        XCTAssertTrue(e("ledger.netExpense").label.contains("263,163.82"))
        XCTAssertTrue(e("ledger.recordCount").label.contains("470"))
        XCTAssertFalse(app.staticTexts["最近记录"].exists)
        capture("01-ledger-cumulative")
        bring("ledger.balance")
        XCTAssertTrue(e("ledger.balance").label.contains("496,212.39"))
        capture("02-ledger-accounts-summary")
        bring("ledger.create").tap()
        XCTAssertTrue(e("ledger.newName").waitForExistence(timeout: 5))
        capture("03-new-ledger-form")
        e("ledger.newName").tap(); e("ledger.newName").typeText("假期账本\n")
        XCTAssertTrue(e("ledger.saveNew").waitForExistence(timeout: 5))
        e("ledger.saveNew").tap()
        XCTAssertTrue(e("ledger.currentName").waitForExistence(timeout: 5))
        XCTAssertTrue(e("ledger.currentName").label.contains("假期账本"))
        XCTAssertTrue(e("ledger.recordCount").label.contains("0 笔"))
        capture("04-new-ledger-selected")
        app.terminate(); app.launch(); app.tabBars.buttons["账本"].tap()
        XCTAssertTrue(e("ledger.currentName").label.contains("假期账本"))
        e("ledger.switch").tap()
        XCTAssertTrue(e("ledger.switcherCreate").waitForExistence(timeout: 5))
        capture("05-switch-with-create")
        e("ledger.choose.stress").tap()
        XCTAssertTrue(e("ledger.income").label.contains("754,276.21"))
        bring("ledger.openFeed").tap()
        XCTAssertTrue(app.tabBars.buttons["流水"].isSelected)
    }

    func testMonthJumpRangeAndSearchKeepContext() {
        app.tabBars.buttons["流水"].tap()
        XCTAssertEqual(e("feed.count").label, "4 笔")
        capture("10-feed-current-month")
        e("feed.date").tap(); app.segmentedControls["period.mode"].buttons["全部"].tap()
        XCTAssertEqual(e("feed.count").label, "470 笔")
        capture("11-feed-all-years")
        chooseMonth(2024, 2)
        XCTAssertEqual(e("feed.count").label, "7 笔")
        XCTAssertTrue(e("feed.date").label.contains("2024 年 2 月"))
        capture("12-feed-leap-month")
        e("feed.date").tap()
        app.segmentedControls["period.mode"].buttons["自定"].tap()
        capture("13-custom-date-range")
        e("period.applyRange").tap()
        XCTAssertTrue(e("feed.customRange").label.contains("2024.02.29"))
        XCTAssertEqual(e("feed.count").label, "7 笔")
        e("feed.search").tap()
        e("feed.query").tap(); e("feed.query").typeText("旅行\n")
        XCTAssertTrue(e("feed.clearFilter").waitForExistence(timeout: 5))
        capture("14-range-and-category")
        bring("feed.transaction.tx-002").tap(); back()
        XCTAssertTrue(e("feed.customRange").label.contains("2024.02.29"))
        XCTAssertTrue(e("feed.clearFilter").exists)
        e("feed.search").tap()
        XCTAssertEqual(e("feed.query").value as? String, "旅行")
        app.buttons["取消"].tap()
        e("feed.clearFilter").tap()
        XCTAssertEqual(e("feed.count").label, "7 笔")
    }

    func testMonthNavigationEmptyRecoveryAndSwitcherCreation() {
        app.tabBars.buttons["流水"].tap()
        chooseMonth(2023, 1)
        XCTAssertEqual(e("feed.count").label, "1 笔")
        XCTAssertTrue(e("feed.totals").label.contains("-12,000.00"))
        capture("15-refund-month")
        chooseMonth(2022, 12)
        XCTAssertTrue(e("feed.date").label.contains("2022 年 12 月"))
        chooseMonth(2023, 2)
        XCTAssertTrue(e("feed.empty").waitForExistence(timeout: 5))
        XCTAssertTrue(e("feed.date").label.contains("2023 年 2 月"))
        capture("16-empty-month-recovery")
        e("feed.resetAll").tap()
        XCTAssertEqual(e("feed.count").label, "470 笔")
        app.tabBars.buttons["账本"].tap()
        e("ledger.switch").tap(); e("ledger.switcherCreate").tap()
        XCTAssertTrue(e("ledger.newName").waitForExistence(timeout: 5))
        e("ledger.newName").tap(); e("ledger.newName").typeText("专用账本\n")
        e("ledger.saveNew").tap()
        XCTAssertTrue(e("ledger.currentName").waitForExistence(timeout: 5))
        XCTAssertTrue(e("ledger.currentName").label.contains("专用账本"))
        app.tabBars.buttons["流水"].tap()
        XCTAssertTrue(e("feed.empty").waitForExistence(timeout: 5))
        XCTAssertEqual(e("feed.count").label, "0 笔")
    }

    func testDarkBookAndTimePicker() {
        app.terminate()
        app.useIsolatedFixture()
        app.launchEnvironment["YUJI_STRESS_DARK"] = "1"
        app.launch()
        app.tabBars.buttons["账本"].tap(); capture("20-dark-ledger")
        app.tabBars.buttons["流水"].tap(); capture("21-dark-feed")
        e("feed.date").tap(); capture("22-dark-date-picker")
        XCTAssertTrue(e("period.month.2").isHittable)
        app.buttons["取消"].tap()
    }

    func testLargestTextHasReachableBookAndDateActions() {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.tabBars.buttons["账本"].tap(); capture("30-large-ledger")
        bring("ledger.create").tap()
        XCTAssertTrue(e("ledger.newName").waitForExistence(timeout: 5)); capture("31-large-new-ledger")
        app.buttons["取消"].tap()
        app.tabBars.buttons["流水"].tap(); capture("32-large-feed")
        e("feed.date").tap()
        XCTAssertTrue(e("period.year").waitForExistence(timeout: 5)); capture("33-large-date-picker")
        bring("period.month.2").tap()
        XCTAssertTrue(e("feed.date").label.contains("2 月"))
    }
}
