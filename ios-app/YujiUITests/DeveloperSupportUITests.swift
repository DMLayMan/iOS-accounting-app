import XCTest
import StoreKitTest

@MainActor
final class DeveloperSupportUITests: XCTestCase {
    private var app: XCUIApplication!
    private var session: SKTestSession?

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.useIsolatedFixture()
        app.launchEnvironment["YUJI_TEST_STORE_MODE"] = "empty"
        app.launchEnvironment["YUJI_TEST_SUPPORT_MODE"] = "preview"
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    }

    private func launch() {
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["账本"].waitForExistence(timeout: 15))
    }

    private func e(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func reveal(_ target: XCUIElement) {
        for _ in 0..<10 {
            let top = app.scrollContentTop
            var bottom = app.tabBars.firstMatch.isHittable ? app.tabBars.firstMatch.frame.minY : app.frame.maxY - 35
            // Numeric entry is a fixed footer, not part of the scrollable form.
            let keypad = e("entry.amountKeypad")
            if keypad.exists { bottom = min(bottom, keypad.frame.minY) }
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY) }
            if target.exists && target.isHittable && target.frame.midY > top && target.frame.midY < bottom { return }
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.9, dy: top + (bottom - top) * 0.75))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.9, dy: top + (bottom - top) * 0.25))
            start.press(forDuration: 0.03, thenDragTo: end)
        }
        XCTFail("Support control not reachable: \(target)")
    }

    private func openSupport() {
        app.tabBars.buttons["我的"].tap()
        let entry = e("me.developerSupport")
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertTrue(entry.isHittable, "Support entry must be reachable on the initial viewport without scrolling")
        XCTAssertGreaterThanOrEqual(entry.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        XCTAssertLessThan(entry.frame.midY, app.tabBars.firstMatch.frame.minY)
        if !app.launchArguments.contains("UICTContentSizeCategoryAccessibilityXXXL") {
            XCTAssertLessThanOrEqual(entry.frame.maxY, app.tabBars.firstMatch.frame.minY)
        }
        XCTAssertEqual(entry.label, "好用，请开发者喝杯☕吧")
        capture("support-01-manual-entry")
        entry.tap()
        XCTAssertTrue(e("support.heading").waitForExistence(timeout: 10))
    }

    private func record() {
        app.tabBars.buttons["记账"].tap()
        XCTAssertTrue(e("entry.amountKeypad").waitForExistence(timeout: 5))
        if app.launchArguments.contains("UICTContentSizeCategoryAccessibilityXXXL") {
            reveal(e("entry.allCategories")); e("entry.allCategories").tap()
            let search = app.textFields["categories.search"]
            XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("早餐\n")
            app.buttons["早餐"].tap()
        } else {
            XCTAssertTrue(e("category.child.早餐").waitForExistence(timeout: 5))
            e("category.child.早餐").tap()
        }
        app.buttons["entry.key.1"].tap()
        app.buttons["entry.save"].tap()
    }

    private func storeKit() throws {
        let testSession = try SKTestSession(configurationFileNamed: "YujiSupport")
        testSession.resetToDefaultState(); testSession.clearTransactions()
        testSession.disableDialogs = true
        testSession.locale = Locale(identifier: "zh_CN"); testSession.storefront = "CHN"
        session = testSession
        app.launchEnvironment["YUJI_TEST_SUPPORT_MODE"] = "storekit"
    }

    func testLocalStoreKitVerifiedPurchaseAndRelaunchDoNotCreateLedgerRecords() throws {
        app.launchEnvironment["YUJI_TEST_SUPPORT_RECORDS"] = "99"
        try storeKit(); launch(); openSupport()
        XCTAssertTrue(e("support.offer.coffee").waitForExistence(timeout: 10))
        XCTAssertFalse(e("support.purchase").isEnabled)
        e("support.offer.coffee").tap()
        XCTAssertTrue(e("support.offer.coffee").isSelected)
        capture("support-02-storekit-coffee-selected")
        XCTAssertTrue(try XCTUnwrap(session).allTransactions().isEmpty)
        e("support.purchase").tap()
        XCTAssertTrue(e("app.toast").waitForExistence(timeout: 15))
        XCTAssertEqual(e("app.toast").label, "咖啡收到啦，谢谢你的支持。")
        XCTAssertFalse(e("support.heading").exists)
        XCTAssertGreaterThan(e("app.toast").frame.minY, app.navigationBars["我的"].frame.maxY)
        capture("support-03-storekit-verified-thanks")
        let transactions = try XCTUnwrap(session).allTransactions()
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions.first?.productIdentifier, "com.yuji.app.support.coffee")
        app.terminate(); launch(); openSupport()
        XCTAssertTrue(app.staticTexts["也谢谢你之前的支持。"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["咖啡收到啦"].exists)
        XCTAssertEqual(try XCTUnwrap(session).allTransactions().count, 1)
        XCTAssertFalse(e("support.purchase").isEnabled)
        e("support.offer.coffee").tap(); e("support.purchase").tap()
        XCTAssertTrue(e("app.toast").waitForExistence(timeout: 15))
        XCTAssertFalse(e("support.heading").exists)
        XCTAssertEqual(try XCTUnwrap(session).allTransactions().count, 2)
        capture("support-16-second-voluntary-support")
        app.tabBars.buttons["流水"].tap()
        XCTAssertEqual(e("feed.count").label, "0 笔")
        record()
        XCTAssertFalse(e("support.invitation.accept").waitForExistence(timeout: 2))
    }

    func testLocalStoreKitPendingApprovalUpdatesAndColdRestartDoesNotReplayThanks() throws {
        try storeKit(); try XCTUnwrap(session).askToBuyEnabled = true
        launch(); openSupport()
        XCTAssertTrue(e("support.offer.coffee").waitForExistence(timeout: 10))
        e("support.offer.coffee").tap(); e("support.purchase").tap()
        XCTAssertTrue(e("support.result").waitForExistence(timeout: 15))
        XCTAssertTrue(e("support.purchase").isEnabled)
        capture("support-04-storekit-pending")
        let transaction = try XCTUnwrap(try XCTUnwrap(session).allTransactions().first)
        try XCTUnwrap(session).approveAskToBuyTransaction(identifier: transaction.identifier)
        XCTAssertTrue(e("app.toast").waitForExistence(timeout: 15))
        XCTAssertFalse(e("support.heading").exists)
        capture("support-05-storekit-approved")
        app.terminate(); launch(); openSupport()
        XCTAssertTrue(app.staticTexts["也谢谢你之前的支持。"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["咖啡收到啦"].exists)
    }

    func testApprovalAfterClosingSheetShowsThanksWithoutReopeningIt() throws {
        try storeKit(); try XCTUnwrap(session).askToBuyEnabled = true
        launch(); openSupport()
        XCTAssertTrue(e("support.offer.coffee").waitForExistence(timeout: 10))
        e("support.offer.coffee").tap(); e("support.purchase").tap()
        XCTAssertTrue(e("support.result").waitForExistence(timeout: 15))
        app.navigationBars["支持开发者"].buttons["关闭"].tap()
        let transaction = try XCTUnwrap(try XCTUnwrap(session).allTransactions().first)
        try XCTUnwrap(session).approveAskToBuyTransaction(identifier: transaction.identifier)
        XCTAssertTrue(e("app.toast").waitForExistence(timeout: 15))
        XCTAssertFalse(e("support.heading").exists)
        capture("support-15-approved-after-dismissal")
    }

    func test100thSuccessfulSaveInvitesOnceAfterEntryClosesAndNeverAgain() {
        app.launchEnvironment["YUJI_TEST_SUPPORT_RECORDS"] = "99"
        launch()
        XCTAssertFalse(e("support.invitation.accept").exists)
        record()
        XCTAssertTrue(e("support.invitation.accept").waitForExistence(timeout: 10))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertFalse(e("entry.amountKeypad").exists)
        capture("support-06-100-record-invitation")
        e("support.invitation.dismiss").tap()
        app.terminate(); launch(); record()
        XCTAssertFalse(e("support.invitation.accept").waitForExistence(timeout: 3))
        openSupport()
        XCTAssertTrue(e("support.offer.coffee").waitForExistence(timeout: 5))
    }

    func testInvitationAcceptDismissesBeforeOpeningSupport() {
        app.launchEnvironment["YUJI_TEST_SUPPORT_RECORDS"] = "99"
        launch(); record()
        XCTAssertTrue(e("support.invitation.accept").waitForExistence(timeout: 10))
        e("support.invitation.accept").tap()
        XCTAssertTrue(e("support.offer.coffee").waitForExistence(timeout: 10))
        XCTAssertFalse(e("support.invitation.accept").exists)
        capture("support-07-accepted-invitation")
        app.navigationBars["支持开发者"].buttons["关闭"].tap()
        record()
        XCTAssertFalse(e("support.invitation.accept").waitForExistence(timeout: 3))
    }

    func testUnknownPurchaseReopensFreshWithoutManualHistoryManagement() {
        app.launchEnvironment["YUJI_TEST_SUPPORT_MODE"] = "uncertain"
        launch(); openSupport()
        XCTAssertTrue(e("support.offer.coffee").waitForExistence(timeout: 5))
        e("support.offer.coffee").tap(); e("support.purchase").tap()
        XCTAssertTrue(e("support.result").waitForExistence(timeout: 5))
        XCTAssertTrue(e("support.purchase").isEnabled)
        XCTAssertFalse(e("support.check").exists)
        capture("support-08-unknown-inline")
        app.navigationBars["支持开发者"].buttons["关闭"].tap(); openSupport()
        XCTAssertTrue(e("support.offer.coffee").waitForExistence(timeout: 5))
        XCTAssertFalse(e("support.result").exists)
        XCTAssertFalse(e("support.purchase").isEnabled)
        app.terminate(); launch(); openSupport()
        XCTAssertTrue(e("support.offer.coffee").waitForExistence(timeout: 5))
        XCTAssertFalse(e("support.result").exists)
        e("support.offer.coffee").tap()
        XCTAssertTrue(e("support.purchase").isEnabled)
        app.navigationBars["支持开发者"].buttons["关闭"].tap(); record()
    }

    func testPendingPurchaseDoesNotBlockChooserAfterColdRestart() {
        app.launchEnvironment["YUJI_TEST_SUPPORT_MODE"] = "pending"
        launch(); openSupport()
        XCTAssertTrue(e("support.offer.coffee").waitForExistence(timeout: 5))
        e("support.offer.coffee").tap(); e("support.purchase").tap()
        XCTAssertTrue(e("support.result").waitForExistence(timeout: 5))
        XCTAssertTrue(e("support.purchase").isEnabled)
        app.terminate(); launch(); openSupport()
        XCTAssertTrue(e("support.offer.coffee").waitForExistence(timeout: 5))
        XCTAssertFalse(e("support.result").exists)
        XCTAssertFalse(e("support.check").exists)
        e("support.offer.coffee").tap(); XCTAssertTrue(e("support.purchase").isEnabled)
        capture("support-14-pending-fresh-cold-start")
        app.navigationBars["支持开发者"].buttons["关闭"].tap()
    }

    func testOldApprovalDoesNotDismissNewSupportSelection() throws {
        try storeKit(); try XCTUnwrap(session).askToBuyEnabled = true
        launch(); openSupport()
        XCTAssertTrue(e("support.offer.coffee").waitForExistence(timeout: 10))
        e("support.offer.coffee").tap(); e("support.purchase").tap()
        XCTAssertTrue(e("support.result").waitForExistence(timeout: 15))
        let transaction = try XCTUnwrap(try XCTUnwrap(session).allTransactions().first)
        app.navigationBars["支持开发者"].buttons["关闭"].tap(); openSupport()
        XCTAssertTrue(e("support.offer.encourage").waitForExistence(timeout: 10))
        e("support.offer.encourage").tap()
        try XCTUnwrap(session).approveAskToBuyTransaction(identifier: transaction.identifier)
        XCTAssertTrue(app.staticTexts["也谢谢你之前的支持。"].waitForExistence(timeout: 15))
        XCTAssertTrue(e("support.offer.encourage").isSelected)
        XCTAssertTrue(e("support.purchase").isEnabled)
        XCTAssertFalse(e("app.toast").exists)
        capture("support-17-old-approval-keeps-new-sheet")
    }

    func testCancellationReturnsQuietlyToSelection() {
        app.launchEnvironment["YUJI_TEST_SUPPORT_MODE"] = "cancelled"
        launch(); openSupport()
        XCTAssertTrue(e("support.offer.coffee").waitForExistence(timeout: 5))
        e("support.offer.coffee").tap(); e("support.purchase").tap()
        let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: e("support.purchase"))
        wait(for: [ready], timeout: 5)
        XCTAssertFalse(e("support.result").exists)
        XCTAssertFalse(app.staticTexts["咖啡收到啦"].exists)
        capture("support-09-cancelled-selection")
    }

    func testUnavailableProductsKeepExitAndAccountingUsable() {
        app.launchEnvironment["YUJI_TEST_SUPPORT_MODE"] = "unavailable"
        launch(); openSupport()
        XCTAssertTrue(app.buttons["重新获取"].waitForExistence(timeout: 5))
        XCTAssertFalse(e("support.purchase").exists)
        capture("support-10-unavailable")
        app.navigationBars["支持开发者"].buttons["关闭"].tap(); record()
        XCTAssertFalse(e("support.invitation.accept").exists)
    }

    func testPricesRemainVisibleDespiteLegacyConfirmationOverrideAndReopenFresh() {
        // The withdrawn workaround must not return through an old test flag.
        app.launchEnvironment["YUJI_TEST_CONFIRM_PRICE"] = "1"
        launch(); openSupport()
        let offer = e("support.offer.coffee")
        XCTAssertTrue(offer.waitForExistence(timeout: 10))
        XCTAssertEqual(offer.label, "一杯咖啡，¥18.00")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "¥18.00")).firstMatch.exists)
        XCTAssertFalse(e("support.confirmPriceNotice").exists)
        XCTAssertFalse(e("support.purchase").isEnabled)
        offer.tap()
        reveal(e("support.purchase")); XCTAssertEqual(e("support.purchase").label, "请一杯 · ¥18.00")
        XCTAssertTrue(e("support.purchase").isEnabled)
        capture("support-price-visible-after-withdrawal")
        app.navigationBars["支持开发者"].buttons["关闭"].tap()
        openSupport()
        XCTAssertTrue(offer.waitForExistence(timeout: 10))
        XCTAssertFalse(e("support.purchase").isEnabled)
        XCTAssertFalse(e("support.check").exists)
    }

    func testDarkThemeCarriesIntoSupportSheet() {
        // The populated isolated fixture already supports the existing dark appearance override.
        app.launchEnvironment.removeValue(forKey: "YUJI_TEST_STORE_MODE")
        app.launchEnvironment["YUJI_STRESS_DARK"] = "1"
        launch()
        app.tabBars.buttons["我的"].tap(); app.buttons["外观与反馈"].tap()
        e("theme.preset.plum").tap()
        app.terminate(); launch()
        openSupport()
        XCTAssertTrue(e("support.offer.coffee").waitForExistence(timeout: 5))
        e("support.offer.coffee").tap()
        capture("support-11-dark-plum")
    }

    func testMaximumDynamicTypeEntryAndPaymentStayReachable() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launch(); openSupport()
        let offer = e("support.offer.coffee")
        XCTAssertTrue(offer.waitForExistence(timeout: 5)); reveal(offer); offer.tap()
        reveal(e("support.purchase")); XCTAssertTrue(e("support.purchase").isEnabled)
        capture("support-12-maximum-type-payment")
        let button = e("support.purchase")
        XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX)
        XCTAssertGreaterThanOrEqual(button.frame.minX, app.frame.minX)
        app.navigationBars["支持开发者"].buttons["关闭"].tap()
    }

    func testMaximumDynamicTypeInvitationStaysDismissible() {
        app.launchEnvironment["YUJI_TEST_SUPPORT_RECORDS"] = "99"
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launch(); record()
        XCTAssertTrue(e("support.invitation.accept").waitForExistence(timeout: 10))
        reveal(e("support.invitation.dismiss"))
        capture("support-13-maximum-type-invitation")
        XCTAssertGreaterThanOrEqual(e("support.invitation.dismiss").frame.height, 44)
        e("support.invitation.dismiss").tap()
        XCTAssertFalse(e("support.invitation.accept").waitForExistence(timeout: 3))
    }
}
