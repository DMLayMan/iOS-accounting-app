import XCTest

final class StatsStressUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.useIsolatedFixture()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(element("stats.net").waitForExistence(timeout: 15))
    }
    private func element(_ id: String) -> XCUIElement { id == "root.newEntry" ? app.tabBars.buttons["记账"] : app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func capture(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func reveal(_ id: String) -> XCUIElement {
        let target = element(id)
        for _ in 0..<22 {
            let entry = app.scrollViews["entry.form"]
            let stats = app.scrollViews["stats.scroll"]
            let viewport = entry.exists && entry.isHittable ? entry.frame : (stats.exists && stats.isHittable ? stats.frame : app.frame)

            let rootAction = element("root.newEntry")
            let bottom = rootAction.exists && rootAction.isHittable ? rootAction.frame.minY - 6 : min(viewport.maxY - 8, app.frame.height - 30)
            let top = max(viewport.minY + 8, app.scrollContentTop)
            if target.exists && target.isHittable && target.frame.midY > top && target.frame.midY < bottom { return target }
            let above = target.exists && target.frame.midY < top
            let upper = top + (bottom - top) * 0.22
            let lower = top + (bottom - top) * 0.78
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: app.frame.width * 0.9, dy: above ? upper : lower))
            let end = origin.withOffset(CGVector(dx: app.frame.width * 0.9, dy: above ? lower : upper))
            start.press(forDuration: 0.03, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        }
        capture("99-unreachable-" + id)
        XCTAssertTrue(target.isHittable, id); return target
    }
    private func jump(_ year: Int, _ month: Int? = nil) {
        goTop(); element("stats.date").tap()
        app.segmentedControls["period.mode"].buttons[month == nil ? "年" : "月"].tap()
        if let month {
            element("period.year").tap(); element("period.chooseYear.\(year)").tap()
            let target = element("period.month.\(month)")
            if !target.isHittable { app.swipeUp() }
            target.tap()
        } else { element("period.fullYear.\(year)").tap() }
    }
    func testRefundDeletionCancelAndUndoRestoreAmount() {
        jump(2023, 1)
        reveal("stats.transaction.tx-470").tap()
        reveal("删除").tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.firstMatch.buttons["取消"].tap()
        XCTAssertTrue(element("detail.amount").exists)
        reveal("删除").tap(); app.alerts.firstMatch.buttons["删除"].tap()
        XCTAssertTrue(app.buttons["撤销"].waitForExistence(timeout: 5))
        app.buttons["撤销"].tap()
        goTop()
        XCTAssertTrue(element("stats.net").label.contains("-12,000.00"))
        capture("83-refund-delete-undo")
    }

    func testFiveYearDateJumpNegativeRefundAndEmptyMonth() {
        capture("01-current-month")
        jump(2023, 1)
        XCTAssertTrue(element("stats.net").label.contains("-12,000.00"))
        capture("02-refund-only-month")
        reveal("stats.category.stress-shop").tap()
        reveal("stats.filter.stress-shop-1").tap()
        XCTAssertTrue(element("stats.detailSummary").waitForExistence(timeout: 5))
        XCTAssertTrue(element("stats.detailSummary").label.contains("1 条流水"))
        capture("03-refund-drilldown")
        reveal("stats.transaction.tx-470").tap()
        capture("04-original-refund-detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        goTop()
        app.swipeDown(); app.swipeDown()
        jump(2023, 2)
        XCTAssertTrue(element("stats.net").label.contains("0.00"))
        XCTAssertTrue(element("stats.compare.环比").label.contains("基期为负"))
        capture("05-empty-month-negative-base")
        jump(2022, 1)
        XCTAssertTrue(element("stats.compare.环比").label.contains("基期早于记账起点"))
        element("stats.compare.环比").tap()
        capture("06-before-recording-start")
    }
    func testRankingDrilldownSortingAndBackPreservesContext() {
        jump(2024, 2)
        reveal("stats.category.stress-travel").tap()
        reveal("stats.filter.stress-travel-2").tap()
        XCTAssertTrue(element("stats.detailSummary").waitForExistence(timeout: 5))
        capture("07-leap-month-transactions")
        reveal("stats.transactionSort").tap(); element("stats.records.amount").tap()
        XCTAssertTrue(element("stats.transactionSort").label.contains("金额从高到低"))
        reveal("stats.transaction.tx-002").tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("stats.transactionSort").label.contains("金额从高到低"))
        goTop()
        reveal("stats.sort").tap()
        app.buttons["按笔数排序"].tap()
        XCTAssertTrue(element("stats.sort").label.contains("笔数"))
        capture("08-ranking-by-count")
    }
    func testYearChartComparisonAndIncome() {
        jump(2023)
        capture("09-year-negative-bar")
        reveal("stats.month.1").tap()
        XCTAssertTrue(element("stats.net").label.contains("-12,000.00"))
        goTop()
        jump(2026, 9) // The current date picker is the single navigation contract.
        reveal("stats.compare.同比").tap()
        XCTAssertTrue(reveal("stats.comparisonPeriod").exists)
        capture("10-comparison-exact-windows")
        reveal("stats.comparisonPeriod").buttons["基期"].tap()
        capture("11-comparison-base-transactions")
        goTop()
        jump(2025)
        _ = reveal("stats.measure")
        app.segmentedControls["stats.measure"].buttons["收入"].tap()
        capture("12-income-distribution")
        XCTAssertTrue(element("stats.category.stress-work").exists)
        XCTAssertFalse(element("stats.category.stress-shop").exists)
        let incomeSummary = element("stats.detailSummary").label
        XCTAssertFalse(incomeSummary.contains("净支出"))
        XCTAssertFalse(incomeSummary.contains("退款"))
    }
    func testDonutSelectionAndEditingRefresh() {
        jump(2024, 2)
        let slice = reveal("stats.slice.stress-food")
        slice.coordinate(withNormalizedOffset: CGVector(dx: 0.61, dy: 0.08)).tap()
        XCTAssertTrue(element("stats.clearSlice").waitForExistence(timeout: 5))
        XCTAssertTrue(element("stats.detailSummary").label.contains("餐饮"))
        capture("13-pie-selection-inline")
        element("stats.clearSlice").tap()
        XCTAssertFalse(element("stats.clearSlice").exists)
        reveal("stats.category.stress-travel").tap()
        reveal("stats.filter.stress-travel-2").tap()
        reveal("stats.transaction.tx-002").tap()
        for _ in 0..<4 { if app.buttons["编辑"].isHittable { break }; app.swipeUp() }
        app.buttons["编辑"].tap()
        XCTAssertTrue(element("entry.save").waitForExistence(timeout: 5))
        XCTAssertTrue(element("entry.save").isEnabled)
        app.buttons["加号，长按更多运算"].tap()
        element("entry.key.1").tap(); element("entry.save").tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("stats.detailSummary").label.contains("2,901.29"))
        capture("14-edited-total-updated")
        reveal("stats.transaction.tx-002").tap()
        for _ in 0..<4 { if app.buttons["记一笔退款"].isHittable { break }; app.swipeUp() }
        app.buttons["记一笔退款"].tap()
        XCTAssertTrue(element("refund.amount").waitForExistence(timeout: 5))
        XCTAssertEqual(element("refund.amount").value as? String, "2901.29")
        XCTAssertTrue(element("refund.save").isEnabled)
        capture("15-large-refund-prefill")
    }

    func testLargeTextDarkAppearanceAndReachableRanking() {
        app.terminate()
        app.useIsolatedFixture()
        app.launchEnvironment["YUJI_STRESS_DARK"] = "1"
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(element("stats.net").waitForExistence(timeout: 10))
        capture("16-large-text-dark-summary")
        reveal("stats.category.stress-food").tap()
        reveal("stats.filter.stress-food-1").tap()
        XCTAssertTrue(element("stats.detailSummary").waitForExistence(timeout: 5))
        capture("17-large-text-dark-drilldown")
        for _ in 0..<2 {
            reveal("stats.childAll.stress-food").tap()
            XCTAssertTrue(element("stats.detailSummary").label.contains("501.05"))
            reveal("stats.filter.stress-food-1").tap()
            XCTAssertTrue(element("stats.detailSummary").label.contains("139.90"))
        }
        goTop()
        app.tabBars.buttons["记账"].tap()
        XCTAssertTrue(element("entry.clearDraft").waitForExistence(timeout: 5))
        element("entry.clearDraft").tap()
        XCTAssertTrue(element("entry.keepEditing").isHittable)
        XCTAssertTrue(element("entry.discard").isHittable)
        XCTAssertFalse(element("entry.amountKeypad").exists)
        capture("29-dark-large-text-exit")
    }

    func testNewDraftClosesWithoutPopupAndRestoresAfterRelaunch() {
        let originalNet = element("stats.net").label
        app.tabBars.buttons["记账"].tap()
        XCTAssertTrue(element("entry.amount").waitForExistence(timeout: 5))
        XCTAssertTrue(element("entry.amount").label.contains("123,456"))
        app.buttons["加号，长按更多运算"].tap(); element("entry.key.1").tap()
        capture("20-new-entry-auto-draft")
        element("entry.close").tap()
        XCTAssertTrue(element("stats.net").waitForExistence(timeout: 5))
        XCTAssertFalse(element("entry.exitDecision").exists)
        XCTAssertEqual(element("stats.net").label, originalNet)
        app.terminate(); app.launch()
        XCTAssertTrue(element("stats.net").waitForExistence(timeout: 10))
        app.tabBars.buttons["记账"].tap()
        XCTAssertTrue(element("entry.amount").waitForExistence(timeout: 5))
        XCTAssertTrue(element("entry.amount").label.contains("123,457"))
        capture("21-draft-restored")
        element("entry.clearDraft").tap()
        XCTAssertTrue(element("entry.exitDecision").waitForExistence(timeout: 5))
        XCTAssertFalse(element("entry.amountKeypad").exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        capture("22-clear-draft-inline")
        element("entry.keepEditing").tap()
        XCTAssertTrue(element("entry.amountKeypad").exists)
        element("entry.clearDraft").tap(); element("entry.discard").tap()
        app.tabBars.buttons["记账"].tap()
        XCTAssertTrue(element("entry.amount").waitForExistence(timeout: 5))
        XCTAssertEqual(element("entry.amount").label, "¥0")
        element("entry.close").tap()
    }

    func testEditCancelUsesInlineDecisionAndProtectsOtherDraft() {
        jump(2024, 2)
        reveal("stats.category.stress-travel").tap()
        reveal("stats.filter.stress-travel-2").tap()
        reveal("stats.transaction.tx-002").tap()
        revealEdit().tap()
        XCTAssertTrue(element("entry.close").waitForExistence(timeout: 5))
        element("entry.close").tap()
        XCTAssertFalse(element("entry.exitDecision").exists)
        revealEdit().tap()
        XCTAssertTrue(element("entry.save").waitForExistence(timeout: 5))
        app.buttons["加号，长按更多运算"].tap(); element("entry.key.1").tap()
        // Cancel while the note keyboard is up: neither keyboard may remain underneath the decision.
        element("entry.note").tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        element("entry.close").tap()
        XCTAssertTrue(element("entry.exitDecision").waitForExistence(timeout: 5))
        XCTAssertFalse(element("entry.amountKeypad").exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        capture("23-edit-cancel-inline")
        element("entry.keepEditing").tap()
        XCTAssertTrue(element("entry.amountKeypad").exists)
        XCTAssertTrue(element("entry.amount").label.contains("2,901.29"))
        element("entry.close").tap(); element("entry.discard").tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("stats.detailSummary").label.contains("2,900.29"))
        reveal("stats.transaction.tx-002").tap(); revealEdit().tap()
        XCTAssertTrue(element("entry.save").waitForExistence(timeout: 5))
        app.buttons["加号，长按更多运算"].tap(); element("entry.key.1").tap(); element("entry.save").tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("stats.detailSummary").label.contains("2,901.29"))
        goTop()
        app.tabBars.buttons["记账"].tap()
        XCTAssertTrue(element("entry.amount").waitForExistence(timeout: 5))
        XCTAssertTrue(element("entry.amount").label.contains("123,456"))
        capture("24-other-draft-preserved")
    }

    private func revealEdit() -> XCUIElement {
        for _ in 0..<6 { if app.buttons["编辑"].isHittable { return app.buttons["编辑"] }; app.swipeUp() }
        return app.buttons["编辑"]
    }

    func testInlineFiltersLinkTotalsWithoutModalAndKeepContext() {
        reveal("stats.category.stress-food").tap()
        capture("25-inline-parent-selected")
        XCTAssertTrue(element("stats.detailSummary").label.contains("餐饮"))
        XCTAssertFalse(element("stats.closeSheet").exists)
        XCTAssertTrue(app.navigationBars["统计"].exists)
        XCTAssertTrue(element("stats.detailSummary").label.contains("501.05"))
        reveal("stats.filter.stress-food-1").tap()
        XCTAssertTrue(element("stats.detailSummary").label.contains("咖啡茶饮"))
        XCTAssertTrue(element("stats.detailSummary").label.contains("2 条流水"))
        XCTAssertTrue(element("stats.detailSummary").label.contains("139.90"))
        _ = reveal("stats.transaction.tx-003")
        capture("26-inline-leaf-transactions")
        reveal("stats.childAll.stress-food").tap()
        XCTAssertTrue(element("stats.detailSummary").label.contains("501.05"))
        reveal("stats.resetFilters").tap()
        XCTAssertTrue(element("stats.detailSummary").label.contains("全部支出"))
        goTop()
        reveal("stats.compare.同比").tap()
        _ = reveal("stats.comparisonPeriod")
        capture("27-inline-comparison")
        let current = element("stats.detailSummary").label
        app.segmentedControls["stats.comparisonPeriod"].buttons["基期"].tap()
        XCTAssertNotEqual(element("stats.detailSummary").label, current)
        capture("28-inline-base-period")
        app.segmentedControls["stats.comparisonPeriod"].buttons["本期"].tap()
        XCTAssertEqual(element("stats.detailSummary").label, current)
        element("stats.closeComparison").tap()
        goTop()
        XCTAssertTrue(element("stats.date").label.contains("2026 年 9 月"))
    }

    private func goTop() {
        for _ in 0..<25 {
            let amount = element("stats.net")
            if amount.exists && amount.isHittable && amount.frame.midY > app.scrollContentTop { return }
            let top = app.scrollContentTop
            let bottom = app.tabBars.firstMatch.frame.minY - 8
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: app.frame.width * 0.9, dy: top + (bottom - top) * 0.2))
            let end = origin.withOffset(CGVector(dx: app.frame.width * 0.9, dy: top + (bottom - top) * 0.8))
            start.press(forDuration: 0.03, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        }
        XCTFail("Cannot return to statistics period")
    }

    func testFeedSearchPreservesQueryAndEmptyFilterCanBeCleared() {
        app.tabBars.buttons["流水"].tap()
        element("feed.date").tap(); app.segmentedControls["period.mode"].buttons["全部"].tap()
        XCTAssertTrue(element("feed.transaction.tx-003").waitForExistence(timeout: 5))
        for _ in 0..<5 { app.swipeUp() }
        capture("18-five-year-feed")
        element("feed.search").tap()
        let query = element("feed.query")
        XCTAssertTrue(query.waitForExistence(timeout: 5)); query.tap(); query.typeText("旅行\n")
        XCTAssertTrue(element("feed.clearFilter").waitForExistence(timeout: 5))
        element("feed.search").tap()
        XCTAssertEqual(element("feed.query").value as? String, "旅行")
        element("feed.query").tap(); element("feed.query").typeText("不存在的分类\n")
        XCTAssertTrue(element("feed.empty").waitForExistence(timeout: 5))
        capture("19-empty-filter-recovery")
        element("feed.clearFilter").tap()
        XCTAssertTrue(element("feed.transaction.tx-003").waitForExistence(timeout: 5))
    }

}
