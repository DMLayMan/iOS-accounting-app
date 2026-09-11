import XCTest

final class CategoryBudgetUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.useIsolatedFixture()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch(); XCTAssertTrue(e("stats.net").waitForExistence(timeout: 12))
    }
    private func e(_ id: String) -> XCUIElement { id == "root.newEntry" ? app.tabBars.buttons["记账"] : app.descendants(matching: .any).matching(identifier: id).firstMatch }
    // UIKit exposes an enabled wrapper around a disabled toolbar button. Inspect the button itself.
    private var applyButton: XCUIElement { app.buttons["categoryBudget.apply"].firstMatch }
    private func capture(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func seeded(dark: Bool = false, large: Bool = false) {
        app.terminate(); app.useIsolatedFixture()
        app.launchEnvironment["YUJI_CATEGORY_BUDGET_FIXTURE"] = "1"
        if dark { app.launchEnvironment["YUJI_STRESS_DARK"] = "1" }
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); XCTAssertTrue(e("stats.net").waitForExistence(timeout: 12))
    }
    @discardableResult private func reveal(_ id: String) -> XCUIElement {
        let target = e(id)
        for _ in 0..<14 {
            let top = app.scrollContentTop
            let bottom: CGFloat
            if app.keyboards.firstMatch.exists { bottom = app.keyboards.firstMatch.frame.minY - 8 }
            else if e("entry.amountKeypad").exists { bottom = e("entry.amountKeypad").frame.minY - 12 }
            else if e("budget.save").exists && e("budget.save").isHittable { bottom = e("budget.save").frame.minY - 8 }
            else if e("root.newEntry").exists && e("root.newEntry").isHittable { bottom = e("root.newEntry").frame.minY - 8 }
            else { bottom = app.frame.height - 35 }
            if target.exists && target.isHittable && target.frame.midY > top && target.frame.midY < bottom { return target }
            let above = target.exists && target.frame.midY < top
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: app.frame.width * 0.82, dy: top + (bottom-top) * (above ? 0.2 : 0.8)))
                .press(forDuration: 0.03, thenDragTo: origin.withOffset(CGVector(dx: app.frame.width * 0.82, dy: top + (bottom-top) * (above ? 0.8 : 0.2))), withVelocity: .slow, thenHoldForDuration: 0)
        }
        capture("99-unreachable-" + id); XCTFail(id); return target
    }
    private func openManager() { reveal("stats.budgetManage").tap(); XCTAssertTrue(e("budget.monthly").waitForExistence(timeout: 5)) }
    private func amount(_ value: String) {
        let field = reveal("categoryBudget.amount"); field.tap()
        if e("categoryBudget.amount.clear").exists { e("categoryBudget.amount.clear").tap(); field.tap() }
        field.typeText(value)
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
    }
    private func addRule(_ category: String, query: String, period: String = "每月", amount value: String, finish: Bool = true) {
        reveal("budget.category.add").tap()
        XCTAssertTrue(e("categoryBudget.period").waitForExistence(timeout: 5))
        app.segmentedControls["categoryBudget.period"].buttons[period].tap()
        e("categoryBudget.choose").tap()
        let search = e("categoryBudget.search"); XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText(query + "\n")
        reveal("categoryBudget.select." + category).tap()
        amount(value)
        if finish { applyButton.tap(); XCTAssertTrue(e("budget.category.add").waitForExistence(timeout: 5)) }
    }

    func testRuleCRUDDuplicateAndPersistence() {
        openManager()
        addRule("stress-food-1", query: "咖啡", amount: "20")
        addRule("stress-food", query: "餐饮", period: "每年", amount: "1000")
        addRule("stress-food-1", query: "咖啡", amount: "30", finish: false)
        XCTAssertTrue(e("categoryBudget.error").exists); XCTAssertFalse(applyButton.isEnabled)
        capture("01-duplicate-rule-inline-error")
        app.segmentedControls["categoryBudget.period"].buttons["每年"].tap(); applyButton.tap()
        reveal("budget.category.edit.month.stress-food-1").tap(); amount("50"); applyButton.tap()
        reveal("budget.category.edit.year.stress-food-1").tap(); reveal("categoryBudget.remove").tap()
        capture("02-rule-management")
        e("budget.save").tap()
        XCTAssertTrue(e("stats.categoryBudget.row.month:stress-food-1").waitForExistence(timeout: 5))
        XCTAssertTrue(e("stats.categoryBudget.row.month:stress-food-1").label.contains("89.90"))
        app.terminate(); app.launch()
        XCTAssertTrue(e("stats.categoryBudget.row.month:stress-food-1").waitForExistence(timeout: 10))
        openManager(); reveal("budget.category.edit.month.stress-food-1").tap(); reveal("categoryBudget.remove").tap()
        reveal("budget.category.edit.year.stress-food").tap(); reveal("categoryBudget.remove").tap(); e("budget.save").tap()
        XCTAssertFalse(e("stats.categoryBudget.row.month:stress-food-1").exists)
        XCTAssertFalse(e("stats.categoryBudget.more").exists)
        capture("03-no-category-rules")
    }

    func testOverrunsFoldAndEntryPreview() {
        seeded()
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'stats.categoryBudget.row.'")).count, 2)
        XCTAssertTrue(e("stats.categoryBudget.hidden").label.contains("1"))
        capture("10-two-overruns-collapsed")
        reveal("stats.categoryBudget.more").tap()
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'stats.categoryBudget.row.'")).count, 4)
        reveal("stats.categoryBudget.row.month:stress-home"); capture("11-expanded-all-rules")
        reveal("stats.categoryBudget.more").tap()
        e("root.newEntry").tap(); XCTAssertTrue(e("entry.key.1").waitForExistence(timeout: 5))
        for key in ["1","2","0"] { e("entry.key." + key).tap() }
        reveal("category.child.咖啡茶饮").tap()
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'entry.categoryBudget.row.'")).count, 2)
        reveal("entry.categoryBudget.more").tap()
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'entry.categoryBudget.row.'")).count, 4)
        reveal("entry.categoryBudget.row.month:stress-food-1")
        XCTAssertTrue(e("entry.categoryBudget.row.month:stress-food-1").label.contains("209.90"))
        capture("12-entry-related-budget-preview")
        reveal("entry.note").tap(); e("entry.note").typeText("分类预算测试\n")
        XCTAssertTrue(e("entry.amountKeypad").waitForExistence(timeout: 5))
        e("entry.close").tap()
        reveal("stats.net"); XCTAssertTrue(e("stats.net").label.contains("501.05"))
        e("root.newEntry").tap(); XCTAssertTrue(e("entry.save").waitForExistence(timeout: 5)); e("entry.save").tap()
        reveal("stats.net"); XCTAssertTrue(e("stats.net").label.contains("621.05"))
        reveal("stats.categoryBudget.more").tap()
        XCTAssertTrue(e("stats.categoryBudget.row.month:stress-food-1").label.contains("209.90"))
        capture("13-save-updates-category-budget")
    }

    func testDarkCategoryBudgetAndEditor() {
        seeded(dark: true)
        reveal("stats.categoryBudget.hidden"); capture("20-dark-collapsed-budgets")
        openManager(); reveal("budget.category.edit.month.stress-food-1").tap()
        capture("21-dark-rule-editor")
        amount("12.345")
        let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "invalid-rule-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        capture("22-invalid-rule-action")
        XCTAssertTrue(e("categoryBudget.error").exists); XCTAssertFalse(applyButton.isEnabled)
        app.navigationBars.buttons["取消"].tap(); e("form.discard").tap()
        app.navigationBars.buttons["取消"].tap()
        XCTAssertTrue(e("stats.net").waitForExistence(timeout: 5))
    }

    func testLargestTextCategoryBudgetAndEditor() {
        seeded(large: true)
        reveal("stats.categoryBudget.more"); capture("30-large-collapsed-budgets")
        openManager(); reveal("budget.category.edit.year.stress-food-1").tap()
        reveal("categoryBudget.amount"); capture("31-large-rule-editor")
        XCTAssertTrue(applyButton.isHittable)
        app.navigationBars.buttons["取消"].tap()
        XCTAssertTrue(e("budget.save").waitForExistence(timeout: 5))
    }
}
