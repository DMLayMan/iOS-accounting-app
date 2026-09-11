import XCTest

final class ThemeUITests: XCTestCase {
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
    private func settings() {
        app.tabBars.buttons["我的"].tap()
        let link = app.buttons["外观与反馈"]
        if !link.isHittable { app.swipeUp() }
        link.tap()
        XCTAssertTrue(e("theme.preset.sage").waitForExistence(timeout: 5))
    }
    private func show(_ id: String) {
        for _ in 0..<3 { if e(id).isHittable { return }; app.swipeUp() }
        XCTAssertTrue(e(id).isHittable)
    }

    func testSheetExitDecisionKeepsSelectedTheme() {
        settings(); e("theme.preset.plum").tap()
        app.tabBars.buttons["记账"].tap()
        XCTAssertTrue(e("entry.addCategory").waitForExistence(timeout: 5))
        e("entry.addCategory").tap()
        let name = e("categories.name")
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("未完成分类\n")
        e("categories.cancel").tap()
        XCTAssertTrue(e("form.keepEditing").waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        capture("84-theme-sheet-exit")
        e("form.discard").tap()
        XCTAssertTrue(e("entry.amount").waitForExistence(timeout: 5))
    }

    func testThemeAcrossPagesEntryAndRelaunch() {
        settings()
        e("theme.preset.plum").tap()
        XCTAssertTrue(e("theme.preset.plum").isSelected)
        capture("01-theme-settings")
        app.tabBars.buttons["统计"].tap(); e("stats.previous").tap()
        XCTAssertTrue(e("stats.net").label.contains("7,574.66")); capture("02-plum-statistics")
        app.tabBars.buttons["流水"].tap(); capture("03-plum-feed")
        XCTAssertEqual(e("feed.count").label, "15 笔")
        app.tabBars.buttons["账本"].tap(); capture("04-plum-ledger")
        app.tabBars.buttons["记账"].tap(); XCTAssertTrue(e("entry.amount").waitForExistence(timeout: 5))
        capture("05-expense-entry")
        e("entry.kind.income").tap(); capture("06-income-entry")
        e("entry.close").tap()
        app.terminate(); app.launch()
        XCTAssertTrue(e("stats.date").waitForExistence(timeout: 10))
        settings(); XCTAssertTrue(e("theme.preset.plum").isSelected)
    }

    func testCustomEditorAppliesOnlyWhenFinished() {
        settings(); e("theme.preset.ocean").tap()
        show("theme.custom"); e("theme.custom").tap()
        let swatch = app.otherElements["深紫色 12"]
        XCTAssertTrue(swatch.waitForExistence(timeout: 5)); swatch.tap()
        capture("10-custom-color-editor")
        app.terminate(); app.launch()
        XCTAssertTrue(e("stats.date").waitForExistence(timeout: 10))
        settings(); XCTAssertTrue(e("theme.preset.ocean").isSelected)
        show("theme.custom"); e("theme.custom").tap()
        XCTAssertTrue(swatch.waitForExistence(timeout: 5)); swatch.tap()
        let done = app.buttons.matching(NSPredicate(format: "label IN %@", ["完成", "关闭", "Done", "Close"])).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertTrue(e("theme.custom").waitForExistence(timeout: 5))
        XCTAssertEqual(e("theme.custom").value as? String, "已选择")
        let chosenColor = e("theme.current").value as? String
        XCTAssertNotNil(chosenColor)
        XCTAssertNotEqual(chosenColor, "#376CA0")
        capture("11-custom-applied")
        app.terminate(); app.launch(); XCTAssertTrue(e("stats.date").waitForExistence(timeout: 10))
        settings(); show("theme.custom")
        XCTAssertEqual(e("theme.custom").value as? String, "已选择")
        XCTAssertEqual(e("theme.current").value as? String, chosenColor)
    }

    func testDarkThemeAndLargestText() {
        settings(); e("theme.preset.amber").tap()
        app.segmentedControls["theme.appearance"].buttons["深色"].tap()
        capture("20-dark-settings")
        app.tabBars.buttons["统计"].tap(); e("stats.previous").tap(); capture("21-dark-statistics")
        app.tabBars.buttons["流水"].tap(); capture("22-dark-feed")
        app.tabBars.buttons["记账"].tap(); XCTAssertTrue(e("entry.close").waitForExistence(timeout: 5))
        capture("23-dark-entry"); e("entry.close").tap()
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); XCTAssertTrue(e("stats.date").waitForExistence(timeout: 10))
        settings(); show("theme.preset.plum"); e("theme.preset.plum").tap()
        capture("24-large-settings")
        XCTAssertTrue(e("theme.preset.plum").isSelected)
        app.tabBars.buttons["流水"].tap(); capture("25-large-feed")
        XCTAssertTrue(e("feed.date").isHittable)
    }
}
