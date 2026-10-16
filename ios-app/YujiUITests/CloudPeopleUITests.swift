import XCTest

final class CloudPeopleUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(large: Bool = false, readonly: Bool = false) {
        app = XCUIApplication(); app.useIsolatedFixture()
        app.launchEnvironment["YUJI_TEST_STORE_MODE"] = "empty"
        app.launchEnvironment["YUJI_TEST_CLOUD_MODE"] = readonly ? "peopleReadonly" : "people"
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if large {
            app.launchEnvironment["YUJI_STRESS_DARK"] = "1"
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch(); XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 15))
    }
    private func item(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<10 {
            if element.exists && element.isHittable && element.frame.midY > app.scrollContentTop && element.frame.midY < app.frame.maxY - 80 { return }
            app.swipeUp()
        }
        XCTFail("无法到达控件 \(element)")
    }
    private func openNickname() {
        app.tabBars.buttons["我的"].tap()
        let entry = item("me.nickname"); reveal(entry); entry.tap()
        XCTAssertTrue(item("nickname.input").waitForExistence(timeout: 5))
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testDefaultRenameSharedFeedDetailAndReset() {
        launch(); openNickname()
        XCTAssertTrue(app.staticTexts["小余"].waitForExistence(timeout: 5)); capture("people-01-default")
        item("nickname.input").tap(); item("nickname.input").typeText("咖啡同学")
        item("nickname.save").tap()
        XCTAssertTrue(item("nickname.saved").waitForExistence(timeout: 6))
        capture("people-save-feedback")
        app.terminate(); app.launch()
        app.tabBars.buttons["流水"].tap()
        let own = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "咖啡同学（我）")).firstMatch
        let other = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "小满")).firstMatch
        XCTAssertTrue(own.waitForExistence(timeout: 6)); XCTAssertTrue(other.exists)
        capture("people-02-shared-feed")
        other.tap(); XCTAssertTrue(app.staticTexts["记账人"].waitForExistence(timeout: 5)); XCTAssertTrue(app.staticTexts["小满"].exists)
        capture("people-03-author-detail")
        openNickname(); item("nickname.reset").tap(); item("nickname.save").tap(); item("nickname.save").tap()
        openNickname(); XCTAssertEqual(item("nickname.input").value as? String, "")
        XCTAssertTrue(app.staticTexts["小余"].exists); capture("people-04-default-restored")
    }
    func testCompactDarkLargestTypeReadOnlyCanChangePrivateName() {
        launch(large: true, readonly: true); openNickname()
        let field = item("nickname.input"); field.tap(); field.typeText("共享账本里的长昵称二十字测试刚刚好")
        let save = item("nickname.save"); XCTAssertTrue(save.isHittable); XCTAssertTrue(save.isEnabled)
        capture("people-05-compact-dark-keyboard")
        save.tap()
        let warning = item("nickname.issue"); reveal(warning)
        XCTAssertTrue(warning.label.contains("只读")); capture("people-06-readonly-largest")
    }
}
