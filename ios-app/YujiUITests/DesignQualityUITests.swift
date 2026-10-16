import XCTest

final class DesignQualityUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.useIsolatedFixture()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(e("stats.net").waitForExistence(timeout: 15))
    }
    private func e(_ id: String) -> XCUIElement { id == "root.newEntry" ? app.tabBars.buttons["记账"] : app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func capture(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    @discardableResult private func reveal(_ id: String) -> XCUIElement {
        let target = e(id)
        for _ in 0..<22 {
            let entry = app.scrollViews["entry.form"].exists ? app.scrollViews["entry.form"] : app.scrollViews["ledger.scroll"]
            let stats = app.scrollViews["stats.scroll"]
            let editor = app.scrollViews["categories.editor.scroll"]
            let viewport = editor.exists ? editor.frame : (entry.exists && entry.isHittable ? entry.frame : (stats.exists && stats.isHittable ? stats.frame : app.frame))

            let rootAction = e("root.newEntry")
            var bottom = rootAction.exists && rootAction.isHittable ? rootAction.frame.minY - 6 : min(viewport.maxY - 8, app.frame.height - 30)
            let categorySave = e("categories.save")
            if id != "categories.save", categorySave.exists, categorySave.isHittable { bottom = min(bottom, categorySave.frame.minY) }
            let keypad = e("entry.amountKeypad")
            if keypad.exists { bottom = min(bottom, keypad.frame.minY) }
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY) }
            let top = max(viewport.minY + 8, app.scrollContentTop)
            if target.exists && target.isHittable && target.frame.minY >= top && target.frame.maxY <= bottom - 8 { return target }
            let above = target.exists && target.frame.midY < top
            let upper = top + (bottom - top) * 0.22
            let lower = top + (bottom - top) * 0.78
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: app.frame.width * 0.9, dy: above ? upper : lower))
            let end = origin.withOffset(CGVector(dx: app.frame.width * 0.9, dy: above ? lower : upper))
            start.press(forDuration: 0.03, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        }
        capture("unreachable-" + id); XCTFail(id); return target
    }
    private func back() { app.navigationBars.buttons.element(boundBy: 0).tap() }
    private func replace(_ id: String, _ value: String) {
        let field = e(id); field.tap()
        let old = (field.value as? String) ?? ""
        if !old.isEmpty && old != field.placeholderValue { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        field.typeText(value)
    }

    func testCategoryIconSheetCreateCancelAndPersistence() {
        e("root.newEntry").tap()
        XCTAssertTrue(e("entry.addCategory").waitForExistence(timeout: 5))
        e("entry.addCategory").tap()
        XCTAssertTrue(e("categories.name").waitForExistence(timeout: 5))
        XCTAssertGreaterThan(e("categories.cancel").frame.minY, app.frame.height * 0.2)
        XCTAssertFalse(e("categories.save").isEnabled)
        capture("30-category-create-sheet")
        e("categories.icon.cup.and.saucer").tap()
        XCTAssertEqual(e("categories.iconPreview").label, "当前图标：咖啡")
        e("categories.name").tap(); e("categories.name").typeText("周末早午餐\n")
        capture("31-category-icon-name")
        e("categories.save").tap()
        XCTAssertTrue(e("entry.amount").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["已选 餐饮 · 周末早午餐"].exists)
        capture("32-category-created-selected")
        e("entry.close").tap()
        app.terminate(); app.launch()
        XCTAssertTrue(e("root.newEntry").waitForExistence(timeout: 10)); e("root.newEntry").tap()
        e("entry.editCategories").tap()
        let created = app.cells.matching(NSPredicate(format: "label CONTAINS %@", "周末早午餐")).firstMatch
        XCTAssertTrue(created.waitForExistence(timeout: 5)); created.tap()
        XCTAssertTrue(e("categories.iconPreview").waitForExistence(timeout: 5))
        XCTAssertEqual(e("categories.iconPreview").label, "当前图标：咖啡")
        capture("33-category-edit-restored")
        e("categories.cancel").tap()
        e("entry.close").tap()
    }

    func testEverySupportPageTourAndAccountValidation() {
        app.tabBars.buttons["账本"].tap()
        capture("40-home")
        app.buttons["看统计"].tap()
        XCTAssertTrue(app.tabBars.buttons["统计"].isSelected)
        XCTAssertFalse(app.navigationBars.buttons["Back"].exists)
        app.tabBars.buttons["账本"].tap()
        reveal("转账").tap(); capture("41-transfer"); app.buttons["取消"].tap()
        reveal("ledger.switch").tap(); capture("42-ledger-switch"); app.buttons["关闭"].tap()
        app.tabBars.buttons["我的"].tap(); capture("43-me")
        app.buttons["账户"].tap()
        XCTAssertTrue(e("root.newEntry").isHittable)
        capture("44-accounts")
        app.buttons["新增账户"].tap()
        XCTAssertTrue(e("account.name").waitForExistence(timeout: 5))
        capture("45-account-editor")
        replace("account.name", "测试账户")
        replace("account.opening", "12x")
        e("account.save").tap()
        XCTAssertTrue(e("account.error").waitForExistence(timeout: 5))
        XCTAssertTrue(e("account.name").exists)
        capture("46-account-invalid-stays")
        replace("account.opening", "-12.50")
        e("account.save").tap()
        XCTAssertTrue(app.buttons["新增账户"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["测试账户"].exists)
        back()
        app.buttons["分类管理"].tap(); capture("47-category-library"); back()
        app.buttons["我的账本"].tap(); capture("48-ledgers"); back()
        app.buttons["最近删除"].tap(); capture("49-trash"); back()
        app.buttons["备份、恢复与导出"].tap(); capture("50-data"); back()
        reveal("外观与反馈").tap(); XCTAssertTrue(app.navigationBars["外观与反馈"].waitForExistence(timeout: 5)); capture("51-settings"); back()
        app.tabBars.buttons["流水"].tap(); capture("52-feed")
        e("feed.search").tap(); capture("53-search-filter"); app.buttons["取消"].tap()
        e("feed.transaction.tx-003").tap()
        XCTAssertTrue(app.navigationBars["咖啡茶饮"].waitForExistence(timeout: 5))
        XCTAssertTrue(e("root.newEntry").isHittable)
        capture("54-transaction-detail")
    }

    func testLongNoteReadabilityAndProfileShortcuts() {
        app.tabBars.buttons["我的"].tap()
        let appearance = app.buttons["外观与反馈"]
        XCTAssertTrue(appearance.isHittable)
        XCTAssertLessThan(appearance.frame.maxY, app.tabBars.firstMatch.frame.minY,
                          "The appearance shortcut should be visible without an initial scroll")
        capture("76-profile-shortcuts")
        appearance.tap()
        XCTAssertTrue(e("theme.preset.sage").waitForExistence(timeout: 5))
        back()
        app.tabBars.buttons["流水"].tap()
        let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'feed.transaction.' AND label CONTAINS %@", "较长备注：旅行期间")).firstMatch
        for _ in 0..<5 {
            if record.isHittable && record.frame.maxY < app.tabBars.firstMatch.frame.minY { break }
            app.swipeUp()
        }
        XCTAssertTrue(record.label.contains("返回统计后仍应保留原来的时间与分类。"))
        capture("77-long-note-feed")
        record.tap()
        let note = e("detail.note")
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue(note.label.hasSuffix("返回统计后仍应保留原来的时间与分类。"))
        XCTAssertGreaterThan(note.frame.width, app.frame.width * 0.65)
        capture("78-long-note-detail")
        back()
        XCTAssertTrue(record.exists)
        XCTAssertTrue(e("feed.date").label.contains("9 月"))
    }

    func testEntryPickersSearchAndChangedCategoryCancel() {
        e("root.newEntry").tap()
        XCTAssertTrue(e("entry.accountPicker").waitForExistence(timeout: 5))
        e("entry.accountPicker").tap(); capture("55-account-picker"); app.buttons["取消"].tap()
        e("entry.datePicker").tap(); capture("56-date-picker"); app.buttons["取消"].tap()
        e("entry.allCategories").tap(); capture("57-category-search")
        e("categories.search").tap(); e("categories.search").typeText("不存在的分类\n")
        capture("58-category-search-empty"); app.buttons["取消"].tap()
        e("entry.addCategory").tap()
        XCTAssertTrue(e("categories.name").waitForExistence(timeout: 5))
        e("categories.name").tap(); e("categories.name").typeText("尚未创建\n")
        e("categories.cancel").tap()
        XCTAssertTrue(e("form.keepEditing").waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        capture("59-category-cancel-inline")
        e("form.keepEditing").tap()
        XCTAssertEqual(e("categories.name").value as? String, "尚未创建")
        e("categories.cancel").tap(); e("form.discard").tap()
        XCTAssertTrue(e("entry.addCategory").waitForExistence(timeout: 5))
        XCTAssertFalse(app.cells.matching(NSPredicate(format: "label CONTAINS %@", "尚未创建")).firstMatch.exists)
    }

    func testBackupReviewCancelAndRecoverableRestore() {
        app.terminate(); app.launchEnvironment["YUJI_RESTORE_PREVIEW_TEST"] = "1"; app.launch()
        XCTAssertTrue(e("stats.net").waitForExistence(timeout: 10))
        let original = e("stats.net").label
        app.tabBars.buttons["我的"].tap(); reveal("备份、恢复与导出").tap()
        XCTAssertTrue(e("backup.confirmRestore").waitForExistence(timeout: 5))
        capture("62-backup-review")
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["生成备份文件"].waitForExistence(timeout: 5))
        back(); app.tabBars.buttons["统计"].tap()
        XCTAssertEqual(e("stats.net").label, original)
        app.tabBars.buttons["我的"].tap(); reveal("备份、恢复与导出").tap()
        XCTAssertTrue(e("backup.confirmRestore").waitForExistence(timeout: 5)); e("backup.confirmRestore").tap()
        XCTAssertTrue(app.buttons["恢复到上次替换前"].waitForExistence(timeout: 5))
        capture("63-backup-recovery-available")
    }

    func testDarkCategorySheetAndEverySymbolAvailable() {
        app.terminate()
        app.launchEnvironment["YUJI_STRESS_DARK"] = "1"
        app.useIsolatedFixture()
        app.launch()
        XCTAssertTrue(e("root.newEntry").waitForExistence(timeout: 10)); e("root.newEntry").tap()
        capture("60-dark-entry")
        e("entry.addCategory").tap()
        XCTAssertTrue(e("categories.name").waitForExistence(timeout: 5)); capture("61-dark-category")
        reveal("categories.icon.gift").tap()
        XCTAssertEqual(e("categories.iconPreview").label, "当前图标：礼物")
    }

    func testLargeTypeCategoryAndSupportPages() {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(e("root.newEntry").waitForExistence(timeout: 10))
        app.tabBars.buttons["账本"].tap(); capture("70-large-home")
        e("root.newEntry").tap(); capture("71-large-entry")
        reveal("entry.addCategory").tap()
        XCTAssertTrue(e("categories.name").waitForExistence(timeout: 5)); capture("72-large-category")
        XCTAssertTrue(e("categories.save").isHittable)
        e("categories.cancel").tap(); e("entry.close").tap()
        app.tabBars.buttons["我的"].tap(); capture("73-large-me")
    }

    func testLargestTypeCategoryCreateWithKeyboardAndIcon() {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        e("root.newEntry").tap()
        reveal("entry.addCategory").tap()
        let name = e("categories.name")
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("周末早午餐与咖啡\n")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let icon = reveal("categories.icon.cup.and.saucer")
        capture("74-largest-category-icon-visible")
        icon.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(icon.isSelected)
        let save = e("categories.save")
        XCTAssertTrue(save.isHittable); XCTAssertTrue(save.isEnabled)
        capture("74-largest-category-can-save")
        save.tap()
        XCTAssertTrue(e("entry.amount").waitForExistence(timeout: 5))
        reveal("entry.allCategories")
        XCTAssertTrue(e("entry.allCategories").label.contains("周末早午餐与咖啡"))
        capture("75-largest-category-selected")
    }
}
