import XCTest

final class BudgetEntryUITests: XCTestCase {
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
    private func capture(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    @discardableResult private func reveal(_ id: String) -> XCUIElement {
        let target = e(id)
        for _ in 0..<16 {
            let top = app.scrollContentTop
            let bottom: CGFloat
            if app.keyboards.firstMatch.exists { bottom = app.keyboards.firstMatch.frame.minY - 10 }
            else if e("entry.amountKeypad").exists { bottom = e("entry.amountKeypad").frame.minY - 8 }
            else if e("root.newEntry").isHittable { bottom = e("root.newEntry").frame.minY - 8 }
            else { bottom = app.frame.height - 90 }
            if target.exists && target.isHittable && target.frame.midY > top && target.frame.midY < bottom { return target }
            let above = target.exists && target.frame.midY < top
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: app.frame.width * 0.86, dy: top + (bottom - top) * (above ? 0.2 : 0.8)))
                .press(forDuration: 0.03, thenDragTo: origin.withOffset(CGVector(dx: app.frame.width * 0.86, dy: top + (bottom - top) * (above ? 0.8 : 0.2))), withVelocity: .slow, thenHoldForDuration: 0)
        }
        capture("99-unreachable-" + id); XCTFail(id); return target
    }
    private func replace(_ id: String, _ value: String) {
        let field = reveal(id); field.tap()
        let old = field.value as? String ?? ""
        if old != field.placeholderValue && !old.isEmpty {
            let clear = e(id + ".clear")
            if clear.exists { clear.tap(); field.tap() }
            else { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        }
        if !value.isEmpty { field.typeText(value) }
    }
    private func finishKeyboard() { if app.keyboards.firstMatch.exists { app.buttons["完成"].firstMatch.tap() } }
    private func setBudget(month: String, year: String) {
        app.tabBars.buttons["账本"].tap(); reveal("ledger.budget").tap()
        XCTAssertTrue(e("budget.monthly").waitForExistence(timeout: 5))
        replace("budget.monthly", month); replace("budget.yearly", year); finishKeyboard()
        e("budget.save").tap()
        XCTAssertTrue(e("root.newEntry").waitForExistence(timeout: 5))
        app.tabBars.buttons["统计"].tap()
    }

    func testCreateBudgetsDraftPreviewSaveAndAnnualBalance() {
        app.tabBars.buttons["账本"].tap(); e("ledger.create").tap()
        XCTAssertTrue(e("ledger.newName").waitForExistence(timeout: 5))
        replace("ledger.newName", "预算生活")
        replace("budget.monthly", "100"); replace("budget.yearly", "1000"); finishKeyboard()
        capture("01-create-with-budgets")
        e("ledger.saveNew").tap()
        app.tabBars.buttons["统计"].tap()
        XCTAssertTrue(e("stats.budgetRemaining").label.contains("100.00"))
        capture("02-budget-before-entry")
        e("root.newEntry").tap()
        XCTAssertTrue(e("entry.key.1").waitForExistence(timeout: 5))
        for key in ["1", "2", "0"] { e("entry.key." + key).tap() }
        e("category.child.早餐").tap()
        XCTAssertGreaterThanOrEqual(e("category.parent.餐饮").frame.minX, e("entry.parents").frame.minX)
        XCTAssertTrue(e("entry.budgetHint").label.contains("超出 ¥20.00"))
        XCTAssertTrue(e("entry.budgetHint").label.contains("剩余 ¥880.00"))
        capture("03-entry-budget-projection")
        reveal("entry.note").tap(); e("entry.note").typeText("预算预览\n")
        XCTAssertTrue(e("entry.amountKeypad").waitForExistence(timeout: 5))
        e("entry.close").tap()
        XCTAssertTrue(e("stats.budgetRemaining").label.contains("100.00"))
        e("root.newEntry").tap()
        XCTAssertTrue(e("entry.save").waitForExistence(timeout: 5)); XCTAssertTrue(e("entry.save").isEnabled)
        e("entry.save").tap()
        XCTAssertTrue(e("stats.budgetRemaining").waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["统计"].isSelected)
        XCTAssertTrue(e("stats.budgetRemaining").label.contains("超出 ¥20.00"))
        capture("04-month-over-budget")
        e("stats.date").tap(); app.segmentedControls["period.mode"].buttons["年"].tap(); e("period.thisYear").tap()
        XCTAssertTrue(e("stats.budgetRemaining").label.contains("880.00"))
        capture("05-independent-year-budget")
        app.terminate(); app.launch()
        XCTAssertTrue(e("stats.budgetRemaining").waitForExistence(timeout: 10))
        XCTAssertTrue(e("stats.budgetRemaining").label.contains("超出 ¥20.00"))
    }

    func testExistingBudgetInvalidInputClearAndLedgerIsolation() {
        setBudget(month: "1000", year: "60000")
        XCTAssertTrue(e("stats.budgetRemaining").label.contains("498.95"))
        capture("06-existing-ledger-budget")
        reveal("stats.budgetManage").tap()
        replace("budget.monthly", "12.345"); finishKeyboard()
        XCTAssertTrue(e("budget.inputError").exists); XCTAssertFalse(e("budget.save").isEnabled)
        capture("07-budget-input-error")
        replace("budget.monthly", ""); finishKeyboard(); e("budget.save").tap()
        XCTAssertTrue(e("stats.budgetUnset").waitForExistence(timeout: 5))
        e("stats.date").tap(); app.segmentedControls["period.mode"].buttons["年"].tap(); e("period.thisYear").tap()
        XCTAssertTrue(e("stats.budgetAmounts").label.contains("60,000.00"))
        app.tabBars.buttons["账本"].tap(); reveal("ledger.switch").tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledger.choose.' AND identifier != 'ledger.choose.stress'")).firstMatch.tap()
        app.tabBars.buttons["统计"].tap()
        XCTAssertTrue(e("stats.budgetUnset").waitForExistence(timeout: 5))
    }

    func testCenterActionAndLastRecordStayReachable() {
        let fab = e("root.newEntry")
        for tab in ["账本", "流水", "统计"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(fab.isHittable); XCTAssertEqual(fab.frame.midX, app.frame.midX, accuracy: 3)
            XCTAssertGreaterThanOrEqual(fab.frame.height, 44)
            XCTAssertLessThanOrEqual(fab.frame.maxY, app.tabBars.firstMatch.frame.maxY)
            capture("10-floating-" + tab)
        }
        app.tabBars.buttons["流水"].tap()
        app.swipeUp(); app.swipeUp()
        capture("11-feed-last-record-clearance")
        reveal("feed.transaction.tx-057").tap()
        XCTAssertTrue(e("root.newEntry").isHittable)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        e("root.newEntry").tap()
        XCTAssertTrue(e("entry.amount").waitForExistence(timeout: 5))
        e("entry.close").tap()
        XCTAssertTrue(app.tabBars.buttons["流水"].isSelected)
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(e("root.newEntry").isHittable)
    }

    func testDarkBudgetAndEntry() {
        app.terminate()
        app.useIsolatedFixture()
        app.launchEnvironment["YUJI_STRESS_DARK"] = "1"
        app.launch()
        setBudget(month: "500", year: "30000")
        capture("20-dark-budget")
        e("root.newEntry").tap(); e("entry.key.1").tap()
        capture("21-dark-entry-budget")
        XCTAssertTrue(e("entry.budgetHint").label.contains("超出"))
        e("entry.close").tap()
    }

    func testLargestTextBudgetEditorAndFloatingAction() {
        setBudget(month: "1000", year: "60000")
        app.terminate(); app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        reveal("stats.budgetRemaining"); capture("30-large-budget")
        reveal("stats.budgetManage").tap(); reveal("budget.yearly"); capture("31-large-budget-editor")
        app.buttons["取消"].tap()
        e("root.newEntry").tap(); reveal("entry.budgetHint"); capture("32-large-entry-budget")
        e("entry.close").tap()
        XCTAssertTrue(e("root.newEntry").isHittable)
    }
}
