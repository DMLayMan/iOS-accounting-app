import XCTest

/// Native audits supplement, but do not replace, physical-device VoiceOver listening.
final class AccessibilityUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.useIsolatedFixture()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(element("stats.net").waitForExistence(timeout: 15))
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func audit(_ screen: String) throws {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = screen + "-accessibility-tree"; tree.lifetime = .keepAlways; add(tree)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = screen; screenshot.lifetime = .keepAlways; add(screenshot)
        continueAfterFailure = true
        // Keep deterministic interaction checks strict. Contrast/Dynamic Type/clipping and
        // Chinese numeric-label heuristics are tracked in the full-audit evidence alongside
        // color-ratio tests, largest-type walkthroughs and physical VoiceOver listening.
        try app.performAccessibilityAudit(for: [.hitRegion, .trait, .elementDetection])
    }

    func testLedgerAudit() throws {
        app.tabBars.buttons["账本"].tap()
        try audit("ledger")
    }

    func testEntryAudit() throws {
        app.tabBars.buttons["记账"].tap()
        XCTAssertTrue(element("entry.amount").waitForExistence(timeout: 5))
        try audit("entry")
    }

    func testCategoryEditorAudit() throws {
        app.tabBars.buttons["记账"].tap()
        XCTAssertTrue(element("entry.addCategory").waitForExistence(timeout: 5))
        element("entry.addCategory").tap()
        XCTAssertTrue(element("categories.name").waitForExistence(timeout: 5))
        try audit("category-editor")
    }

    func testStatsAudit() throws {
        try audit("stats")
    }

    func testStatsFilteredActionsHaveFullTouchTargets() throws {
        func reveal(_ control: XCUIElement) {
            for _ in 0..<20 {
                let top = app.scrollContentTop
                let bottom = app.tabBars.firstMatch.frame.minY
                if control.isHittable && control.frame.minY > top && control.frame.maxY < bottom { return }
                let above = control.exists && control.frame.midY < top
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let upper = origin.withOffset(CGVector(dx: app.frame.width * 0.9, dy: top + (bottom - top) * 0.3))
                let lower = origin.withOffset(CGVector(dx: app.frame.width * 0.9, dy: top + (bottom - top) * 0.7))
                (above ? upper : lower).press(forDuration: 0.03, thenDragTo: above ? lower : upper)
            }
            XCTFail("Control outside the visible viewport: \(control)")
        }
        app.segmentedControls["stats.periodMode"].buttons["全部"].tap()
        let ranking = element("stats.category.stress-food")
        reveal(ranking)
        ranking.tap()
        for id in ["stats.sort", "stats.resetFilters"] {
            let control = app.buttons[id]
            reveal(control)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44 - 0.01, id)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44 - 0.01, id)
        }
        try audit("stats-filtered-actions")
        app.buttons["stats.resetFilters"].tap()
        XCTAssertFalse(element("stats.resetFilters").exists)
        let more = app.buttons["stats.loadMore"]
        reveal(more)
        XCTAssertGreaterThanOrEqual(more.frame.height, 48 - 0.01)
        let before = more.label
        try audit("stats-pagination")
        more.tap()
        XCTAssertNotEqual(more.label, before)
    }

    func testFeedAudit() throws {
        app.tabBars.buttons["流水"].tap()
        try audit("feed")
    }

    func testProfileAudit() throws {
        app.tabBars.buttons["我的"].tap()
        try audit("profile")
    }

    func testEntrySemanticsAndDestructiveDecision() {
        app.tabBars.buttons["记账"].tap()
        XCTAssertTrue(element("entry.amount").waitForExistence(timeout: 5))
        XCTAssertTrue(element("entry.amount").label.hasPrefix("支出金额"))
        XCTAssertEqual(element("entry.key..").label, "小数点")
        XCTAssertEqual(element("entry.key.-").label, "减号")
        XCTAssertTrue(element("entry.datePicker").label.contains("2026 年 09 月 10 日"))
        for id in ["entry.kind.expense", "entry.kind.income", "entry.editCategories", "entry.addCategory"] {
            let control = app.buttons[id]
            // Accessibility frames may round 44pt to 43.99999999999997.
            XCTAssertGreaterThanOrEqual(control.frame.width, 44 - 0.01, id)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44 - 0.01, id)
        }
        element("entry.clearDraft").tap()
        XCTAssertTrue(element("entry.keepEditing").waitForExistence(timeout: 5))
        XCTAssertFalse(element("entry.note").exists, "Inactive form must leave the accessibility tree during the decision")
        XCTAssertFalse(element("entry.amountKeypad").exists)
        element("entry.keepEditing").tap()
        XCTAssertTrue(element("entry.note").waitForExistence(timeout: 5))
        XCTAssertTrue(element("entry.amountKeypad").exists)
    }

    func testIncomeRankingAndTransactionReadAsOneRecord() {
        app.segmentedControls["stats.periodMode"].buttons["全部"].tap()
        let measure = app.segmentedControls["stats.measure"]
        for _ in 0..<6 {
            if measure.isHittable && measure.frame.minY > app.scrollContentTop { break }
            app.scrollViews["stats.scroll"].swipeUp()
        }
        measure.buttons["收入"].tap()
        let row = element("stats.category.stress-work")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("收入"))
        XCTAssertFalse(row.label.contains("退款"))
        app.tabBars.buttons["流水"].tap()
        let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'feed.transaction.'")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertTrue(record.label.contains("人民币"))
        XCTAssertTrue(record.label.contains("账户"))
        XCTAssertTrue(record.label.contains("年"))
    }

    func testSupportPreviewAudit() throws {
        app.terminate()
        app.launchEnvironment["YUJI_TEST_SUPPORT_MODE"] = "preview"
        app.launch()
        app.tabBars.buttons["我的"].tap()
        element("me.developerSupport").tap()
        XCTAssertTrue(element("support.offer.coffee").waitForExistence(timeout: 10))
        element("support.offer.coffee").tap()
        try audit("support-preview")
    }

    func testNicknameAudit() throws {
        app.terminate()
        app.useIsolatedFixture()
        app.launchEnvironment["YUJI_TEST_STORE_MODE"] = "empty"
        app.launchEnvironment["YUJI_TEST_CLOUD_MODE"] = "people"
        app.launch()
        app.tabBars.buttons["我的"].tap()
        let nickname = element("me.nickname")
        for _ in 0..<6 {
            if nickname.isHittable { break }
            app.swipeUp()
        }
        nickname.tap()
        XCTAssertTrue(element("nickname.input").waitForExistence(timeout: 5))
        try audit("nickname-simulated-cloud")
    }
}
