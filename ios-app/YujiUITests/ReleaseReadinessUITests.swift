import XCTest

/// Release audit coverage for paths previously checked only at the domain layer.
/// Each test owns an empty, isolated ledger; no personal file or prior QA session is reused.
final class ReleaseReadinessUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.useIsolatedFixture()
        app.launchEnvironment["YUJI_TEST_STORE_MODE"] = "empty"
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["账本"].waitForExistence(timeout: 15))
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func reveal(_ target: XCUIElement) {
        for _ in 0..<10 {
            let keypad = element("entry.amountKeypad")
            let bottom = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY
                : (keypad.exists ? keypad.frame.minY : (app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.frame.maxY - 30))
            if target.exists && target.isHittable && target.frame.midY > app.scrollContentTop && target.frame.midY < bottom { return }
            let top = app.scrollContentTop
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.9, dy: top + (bottom - top) * 0.78))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.9, dy: top + (bottom - top) * 0.25))
            start.press(forDuration: 0.03, thenDragTo: end)
        }
        XCTFail("Unreachable audit control: \(target)")
    }

    private func record(_ kind: String, amount: String, category: String) {
        app.tabBars.buttons["记账"].tap()
        XCTAssertTrue(app.buttons["entry.kind.\(kind)"].waitForExistence(timeout: 5))
        app.buttons["entry.kind.\(kind)"].tap()
        element("category.child.\(category)").tap()
        for key in amount { app.buttons["entry.key.\(key)"].tap() }
        XCTAssertTrue(app.buttons["entry.save"].isEnabled)
        app.buttons["entry.save"].tap()
        XCTAssertTrue(app.tabBars.buttons["账本"].waitForExistence(timeout: 5))
    }

    private func prepareYesterdayEntry() {
        app.tabBars.buttons["记账"].tap()
        XCTAssertTrue(element("entry.amount").waitForExistence(timeout: 5))
        element("category.child.早餐").tap()
        for key in "42" { app.buttons["entry.key.\(key)"].tap() }
        let note = app.textFields["entry.note"]
        note.tap(); note.typeText("backdate keep")
        app.buttons["entry.noteDone"].tap()
        app.buttons["entry.datePicker"].tap()
        let yesterday = app.datePickers.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR label == %@", "9月9日", "9")).firstMatch
        XCTAssertTrue(yesterday.waitForExistence(timeout: 5), app.debugDescription)
        yesterday.tap()
        app.navigationBars["选择日期"].buttons["完成"].tap()
    }

    func testBackdateAdjustAndCancelPreserveEntryBeforeExplicitSave() {
        prepareYesterdayEntry()
        XCTAssertTrue(element("entry.accountStartWarning").waitForExistence(timeout: 5))
        XCTAssertTrue(element("entry.accountStartWarning").label.contains("2026年9月10日"), element("entry.accountStartWarning").label)
        XCTAssertFalse(app.buttons["entry.save"].isEnabled)
        capture("backdate-01-explanation")
        app.buttons["entry.adjustAccountStart"].tap()
        XCTAssertTrue(app.navigationBars["调整记账起点"].waitForExistence(timeout: 5))
        app.navigationBars["调整记账起点"].buttons["取消"].tap()
        XCTAssertTrue(element("entry.accountStartWarning").waitForExistence(timeout: 5))
        XCTAssertTrue(element("entry.amount").label.contains("42"))
        XCTAssertEqual(app.textFields["entry.note"].value as? String, "backdate keep")
        app.buttons["entry.adjustAccountStart"].tap()
        capture("backdate-02-adjust-account")
        app.buttons["account.save"].tap()
        XCTAssertTrue(app.buttons["entry.save"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("entry.accountStartWarning").exists)
        XCTAssertTrue(element("entry.amount").label.contains("42"))
        XCTAssertEqual(app.textFields["entry.note"].value as? String, "backdate keep")
        capture("backdate-03-entry-retained")
        app.buttons["entry.save"].tap()
        XCTAssertTrue(app.tabBars.buttons["账本"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(element("ledger.balance").waitForExistence(timeout: 10))
        XCTAssertTrue(element("ledger.balance").label.contains("42.00"))
        app.tabBars.buttons["流水"].tap()
        XCTAssertEqual(element("feed.count").label, "1 笔")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "backdate keep")).firstMatch.exists)
    }

    func testLargestTypeDarkBackdateRecoveryKeepsActionsReachable() {
        prepareYesterdayEntry()
        app.buttons["entry.close"].tap()
        XCTAssertTrue(app.tabBars.buttons["账本"].waitForExistence(timeout: 5))
        app.tabBars.buttons["我的"].tap()
        app.buttons["外观与反馈"].tap()
        app.segmentedControls["theme.appearance"].buttons["深色"].tap()
        XCTAssertTrue(app.segmentedControls["theme.appearance"].buttons["深色"].isSelected)
        app.tabBars.buttons["账本"].tap()
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.tabBars.buttons["记账"].tap()
        let adjust = app.buttons["entry.adjustAccountStart"]
        reveal(adjust)
        capture("backdate-04-largest-dark-explanation")
        adjust.tap()
        let save = app.buttons["account.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5)); XCTAssertTrue(save.isHittable)
        capture("backdate-05-largest-dark-account")
        save.tap()
        XCTAssertTrue(app.buttons["entry.save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["entry.save"].isEnabled)
        capture("backdate-06-largest-dark-retained")
        app.buttons["entry.save"].tap()
        XCTAssertTrue(app.tabBars.buttons["账本"].waitForExistence(timeout: 5))
    }

    func testIncomeExpenseRefundTransferAndRelaunchConserveBalance() {
        record("income", amount: "120", category: "工资")
        record("expense", amount: "30", category: "早餐")
        app.tabBars.buttons["流水"].tap()
        let expense = app.cells.containing(.staticText, identifier: "早餐").firstMatch
        XCTAssertTrue(expense.waitForExistence(timeout: 5)); expense.tap()
        reveal(app.buttons["记一笔退款"]); app.buttons["记一笔退款"].tap()
        let amount = app.textFields["refund.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5)); amount.tap()
        let oldValue = amount.value as? String ?? ""
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldValue.count) + "10")
        capture("release-01-refund-save")
        app.buttons["refund.save"].tap()
        XCTAssertTrue(app.navigationBars["早餐"].waitForExistence(timeout: 5))
        app.tabBars.buttons["账本"].tap()
        XCTAssertTrue(element("ledger.netExpense").label.contains("20.00"))
        XCTAssertTrue(element("ledger.income").label.contains("120.00"))
        reveal(app.buttons["转账"]); app.buttons["转账"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "转出账户")).firstMatch.tap()
        app.buttons["现金"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "转入账户")).firstMatch.tap()
        app.buttons["银行卡"].tap()
        let transferAmount = app.textFields["金额（可算式）"]
        transferAmount.tap(); transferAmount.typeText("25")
        capture("release-02-transfer-save")
        app.navigationBars["转账"].buttons["保存"].tap()
        XCTAssertTrue(app.tabBars.buttons["账本"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(element("ledger.surplus").waitForExistence(timeout: 10))
        XCTAssertTrue(element("ledger.surplus").label.contains("100.00"))
        XCTAssertTrue(element("ledger.balance").label.contains("100.00"))
        capture("release-03-balanced-after-relaunch")
        app.tabBars.buttons["统计"].tap()
        XCTAssertTrue(element("stats.net").label.contains("20.00"))
        app.tabBars.buttons["流水"].tap()
        XCTAssertEqual(element("feed.count").label, "4 笔")
    }

    func testBackupAndCSVOpenShareAndImportCancelPreservesLedger() {
        app.tabBars.buttons["我的"].tap()
        app.buttons["备份、恢复与导出"].tap()
        app.buttons["生成备份文件"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 8))
        waitForShareToAppear()
        capture("release-04-backup-system-share")
        closeSystemShare()
        reveal(app.buttons["导出当前账本 CSV"])
        XCTAssertTrue(app.buttons["导出当前账本 CSV"].isHittable)
        app.buttons["导出当前账本 CSV"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 8))
        waitForShareToAppear()
        capture("release-05-csv-system-share")
        closeSystemShare()
        app.buttons["选择备份恢复"].tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8))
        capture("release-06-system-file-picker")
        cancel.tap()
        XCTAssertTrue(app.buttons["生成备份文件"].waitForExistence(timeout: 5))
        app.tabBars.buttons["账本"].tap()
        XCTAssertTrue(element("ledger.balance").label.contains("0.00"))
    }

    private func waitForShareToAppear() {
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["关闭", "Close"])).firstMatch
        let ready = expectation(for: NSPredicate(format: "exists == true AND hittable == true"), evaluatedWith: close)
        wait(for: [ready], timeout: 8)
    }

    private func closeSystemShare() {
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["关闭", "Close"])).firstMatch
        if close.waitForExistence(timeout: 2) { close.tap() }
        else {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "system-share-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            let grabber = app.buttons["Sheet Grabber"]
            XCTAssertTrue(grabber.exists)
            grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        }
    }

    func testLongAccountNameKeepsEntryDateOnScreen() {
        let name = "家庭日常共同生活专用银行卡账户用于验证长名称显示（含家庭旅行专项储蓄与长期备用金）"
        app.tabBars.buttons["我的"].tap(); app.buttons["账户"].tap()
        app.buttons["新增账户"].tap()
        let field = app.textFields["account.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(name)
        app.buttons["account.save"].tap()
        XCTAssertTrue(app.buttons["新增账户"].waitForExistence(timeout: 5))
        app.tabBars.buttons["记账"].tap()
        app.buttons["entry.accountPicker"].tap()
        app.buttons[name].tap()
        XCTAssertTrue(app.buttons["entry.datePicker"].waitForExistence(timeout: 5))
        capture("release-07-long-account-name")
        let date = app.buttons["entry.datePicker"]
        XCTAssertLessThanOrEqual(date.frame.maxX, app.frame.maxX, "Long account names must leave the date control inside the screen")
        for id in ["entry.accountPicker", "entry.amount", "entry.amountKeypad", "entry.save"] {
            let control = element(id)
            XCTAssertGreaterThanOrEqual(control.frame.minX, app.frame.minX, id)
            XCTAssertLessThanOrEqual(control.frame.maxX, app.frame.maxX, id)
        }
        XCTAssertTrue(date.isHittable)
        date.tap()
        XCTAssertTrue(app.buttons["取消"].waitForExistence(timeout: 5))
        capture("release-08-long-name-date-picker")
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["entry.close"].waitForExistence(timeout: 5))
        app.buttons["entry.close"].tap()
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.tabBars.buttons["记账"].tap()
        let largeDate = app.buttons["entry.datePicker"]
        reveal(largeDate)
        XCTAssertTrue(largeDate.isHittable)
        XCTAssertTrue(app.buttons["entry.accountPicker"].label.contains(name), "The full account name must remain available to accessibility")
        for id in ["entry.accountPicker", "entry.datePicker", "entry.amount", "entry.amountKeypad", "entry.save"] {
            let control = element(id)
            XCTAssertGreaterThanOrEqual(control.frame.minX, app.frame.minX, id)
            XCTAssertLessThanOrEqual(control.frame.maxX, app.frame.maxX, id)
        }
        capture("review-largest-type-long-account")
        largeDate.tap()
        XCTAssertTrue(app.buttons["取消"].waitForExistence(timeout: 5))
    }

    func testBackgroundCheckpointRestoresUnsubmittedEntryWithoutChangingTotals() {
        app.tabBars.buttons["记账"].tap()
        element("category.child.早餐").tap()
        for key in "123" { app.buttons["entry.key.\(key)"].tap() }
        XCUIDevice.shared.press(.home)
        // Wait for the scene transition, not a close action, then terminate.
        let background = expectation(for: NSPredicate { _, _ in
            self.app.state == .runningBackground || self.app.state == .runningBackgroundSuspended
        }, evaluatedWith: app)
        wait(for: [background], timeout: 8)
        app.terminate(); app.launch()
        XCTAssertTrue(element("ledger.balance").waitForExistence(timeout: 10))
        XCTAssertTrue(element("ledger.balance").label.contains("0.00"))
        app.tabBars.buttons["记账"].tap()
        XCTAssertTrue(element("entry.amount").label.contains("123"))
        XCTAssertTrue(element("entry.selectedCategory").label.contains("早餐"))
        capture("review-background-draft-restored")
        app.buttons["entry.save"].tap()
        XCTAssertTrue(element("ledger.netExpense").label.contains("123.00"))
    }

    func testOfflinePrivacyAndHelpAreReadable() {
        app.tabBars.buttons["我的"].tap()
        reveal(app.buttons["隐私说明"]); app.buttons["隐私说明"].tap()
        XCTAssertTrue(app.staticTexts["余记隐私说明"].waitForExistence(timeout: 5))
        capture("review-privacy")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(app.buttons["帮助与反馈"]); app.buttons["帮助与反馈"].tap()
        reveal(element("about.support"))
        XCTAssertTrue(element("about.support").isHittable)
        capture("review-help")
    }

    func testBackgroundDraftCanReturnToOriginalEmptyValues() {
        app.tabBars.buttons["记账"].tap()
        element("category.child.早餐").tap()
        for key in "12" { app.buttons["entry.key.\(key)"].tap() }
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 8))
        app.activate()
        XCTAssertTrue(app.buttons["删除一位"].waitForExistence(timeout:5))
        XCTAssertEqual(element("entry.amount").label,"¥12.00")
        app.buttons["删除一位"].tap(); XCTAssertEqual(element("entry.amount").label,"¥1.00")
        app.buttons["删除一位"].tap(); XCTAssertEqual(element("entry.amount").label,"¥0")
        app.buttons["entry.kind.income"].tap(); app.buttons["entry.kind.expense"].tap()
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 8))
        app.terminate(); app.launch()
        app.tabBars.buttons["记账"].tap()
        XCTAssertEqual(element("entry.amount").label, "¥0")
        XCTAssertEqual(element("entry.selectedCategory").label, "请选择二级分类")
        capture("review-background-reverted-draft")
    }

    func testAccountAndAmountFiltersApplyValidateCancelAndClear() {
        record("expense", amount: "30", category: "早餐")
        record("expense", amount: "50", category: "早餐")
        record("income", amount: "120", category: "工资")
        app.tabBars.buttons["流水"].tap(); app.buttons["feed.search"].tap()
        element("feed.filterAccount").tap(); app.buttons["现金"].tap()
        let min = app.textFields["feed.minimum"], max = app.textFields["feed.maximum"]
        reveal(min); min.tap(); min.typeText("40")
        app.buttons["完成输入"].tap()
        reveal(max); max.tap(); max.typeText("130")
        app.buttons["完成输入"].tap()
        app.buttons["feed.applyFilter"].tap()
        XCTAssertEqual(element("feed.count").label, "2 笔")
        capture("review-account-amount-filter")
        app.buttons["feed.search"].tap()
        reveal(min); min.tap()
        min.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (min.value as? String ?? "").count) + "140")
        app.buttons["完成输入"].tap()
        XCTAssertTrue(element("feed.filterError").exists)
        XCTAssertFalse(app.buttons["feed.applyFilter"].isEnabled)
        capture("review-invalid-amount-range")
        app.buttons["取消"].tap()
        XCTAssertEqual(element("feed.count").label, "2 笔")
        app.buttons["feed.clearFilter"].tap()
        XCTAssertEqual(element("feed.count").label, "3 笔")
    }

    func testRecoveryPointPreviewAndConfirmedCleanupKeepCurrentLedger() {
        app.terminate(); app.launchEnvironment["YUJI_RESTORE_PREVIEW_TEST"] = "1"; app.launch()
        app.tabBars.buttons["我的"].tap(); app.buttons["备份、恢复与导出"].tap()
        XCTAssertTrue(app.buttons["backup.confirmRestore"].waitForExistence(timeout: 5))
        app.buttons["backup.confirmRestore"].tap()
        let manage = app.buttons["backup.recoveryPoints"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5)); manage.tap()
        let menu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "管理恢复点 ")).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5)); capture("review-recovery-points")
        menu.tap(); app.buttons["删除这个副本"].tap()
        app.alerts.firstMatch.buttons["取消"].tap()
        XCTAssertTrue(menu.exists)
        menu.tap(); app.buttons["删除这个副本"].tap()
        capture("review-recovery-cleanup-confirm")
        app.alerts.firstMatch.buttons["删除副本"].tap()
        XCTAssertTrue(app.staticTexts["没有本地恢复点"].waitForExistence(timeout: 5))
        app.tabBars.buttons["账本"].tap()
        XCTAssertTrue(element("ledger.balance").label.contains("0.00"))
    }

    func testNoUsableAccountExplainsRecoveryAndKeepsDraft() {
        app.tabBars.buttons["我的"].tap(); app.buttons["账户"].tap()
        for name in ["现金", "银行卡"] {
            app.cells.containing(.staticText, identifier: name).firstMatch.tap()
            XCTAssertTrue(app.buttons["归档账户"].waitForExistence(timeout: 5))
            app.buttons["归档账户"].tap()
            XCTAssertTrue(app.buttons["新增账户"].waitForExistence(timeout: 5))
        }
        app.tabBars.buttons["记账"].tap()
        element("category.child.早餐").tap()
        for key in "12" { app.buttons["entry.key.\(key)"].tap() }
        app.buttons["entry.accountPicker"].tap()
        XCTAssertTrue(app.staticTexts["没有可用账户"].waitForExistence(timeout: 5))
        capture("review-no-usable-account")
        app.buttons["取消"].tap(); app.buttons["entry.close"].tap()
        app.tabBars.buttons["记账"].tap()
        XCTAssertEqual(element("entry.amount").label, "¥12.00")
        XCTAssertFalse(app.buttons["entry.save"].isEnabled)
    }
}
