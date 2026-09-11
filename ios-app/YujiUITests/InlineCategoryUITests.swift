import XCTest

final class InlineCategoryUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.useIsolatedFixture("YUJI_UI_TEST_SESSION")
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(element("entry.addCategory").waitForExistence(timeout: 10))
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func child(_ name: String) -> XCUIElement { element("category.child.\(name)") }
    private func parent(_ name: String) -> XCUIElement { element("category.parent.\(name)") }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testRowMajorLayoutSingleRowAndQuickCreate() {
        XCTAssertEqual(child("早餐").frame.minY, child("零食").frame.minY, accuracy: 2)
        XCTAssertGreaterThan(child("水果").frame.minY, child("早餐").frame.minY)
        XCTAssertLessThan(element("entry.key.1").frame.minX, 30)
        parent("娱乐").tap()
        XCTAssertEqual(child("影音游戏").frame.minY, child("电影演出").frame.minY, accuracy: 2)
        capture("01-entertainment-single-row")
        element("entry.addCategory").tap()
        let field = element("categories.name")
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("桌游")
        XCTAssertFalse(element("entry.key.1").exists)
        element("categories.save").tap()
        XCTAssertTrue(child("桌游").waitForExistence(timeout: 5))
        XCTAssertGreaterThan(child("桌游").frame.minY, child("影音游戏").frame.minY)
        XCTAssertTrue(element("entry.selectedCategory").label.contains("桌游"))
        // Small iPhones scroll the form while keeping the amount keypad fixed.
        for _ in 0..<5 {
            if element("entry.note").frame.maxY < element("entry.key.1").frame.minY { break }
            app.scrollViews["entry.form"].swipeUp()
        }
        XCTAssertLessThan(element("entry.note").frame.maxY, element("entry.key.1").frame.minY)
        element("entry.note").tap()
        XCTAssertFalse(element("entry.key.1").exists)
        capture("02-note-without-amount-keypad")
    }

    func testLongPressReorderUndoAndPersistence() {
        child("咖啡茶饮").tap()
        element("entry.key.3").tap(); element("entry.key.6").tap()
        child("咖啡茶饮").press(forDuration: 0.7, thenDragTo: child("早餐"))
        XCTAssertTrue(element("entry.undoOrder").waitForExistence(timeout: 5))
        XCTAssertLessThan(child("咖啡茶饮").frame.minX, child("早餐").frame.minX)
        capture("03-native-long-press-reordered")
        element("entry.undoOrder").tap()
        XCTAssertGreaterThan(child("咖啡茶饮").frame.minX, child("早餐").frame.minX)
        child("咖啡茶饮").press(forDuration: 0.7, thenDragTo: child("买菜"))
        XCTAssertTrue(element("entry.undoOrder").waitForExistence(timeout: 5))
        XCTAssertGreaterThan(child("咖啡茶饮").frame.minY, child("早餐").frame.minY)
        element("entry.editCategories").tap()
        XCTAssertTrue(element("entry.selectedCategory").label.contains("咖啡茶饮"))
        XCTAssertTrue(element("entry.amount").label.contains("36"))
        app.terminate(); app.launch()
        XCTAssertTrue(element("entry.addCategory").waitForExistence(timeout: 10))
        XCTAssertGreaterThan(child("咖啡茶饮").frame.minY, child("早餐").frame.minY)
        capture("04-order-after-relaunch")
    }

    func testParentReorderAndCrossPageDrag() {
        parent("餐饮").press(forDuration: 0.7, thenDragTo: parent("购物"))
        XCTAssertTrue(element("entry.undoOrder").waitForExistence(timeout: 5))
        // UIKit chooses the insertion slot around the drop center; verify movement and undo.
        XCTAssertGreaterThan(parent("餐饮").frame.minX, parent("出行").frame.minX)
        element("entry.undoOrder").tap()
        XCTAssertLessThan(parent("餐饮").frame.minX, parent("购物").frame.minX)
        let start = child("咖啡茶饮").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let edge = element("entry.children").coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.25))
        start.press(forDuration: 0.7, thenDragTo: edge, withVelocity: .slow, thenHoldForDuration: 2)
        XCTAssertTrue(element("entry.undoOrder").waitForExistence(timeout: 5))
        capture("06-native-cross-page-drag")
        app.terminate(); app.launch()
        XCTAssertTrue(element("entry.addCategory").waitForExistence(timeout: 10))
        app.buttons["下一页分类"].tap()
        XCTAssertTrue(child("咖啡茶饮").isHittable)
    }

    func testSearchLocatesSecondPage() {
        element("entry.allCategories").tap()
        let field = element("categories.search")
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("夜宵")
        app.buttons["夜宵"].tap()
        XCTAssertTrue(child("夜宵").waitForExistence(timeout: 5))
        XCTAssertTrue(child("夜宵").isHittable)
        XCTAssertTrue(element("entry.selectedCategory").label.contains("夜宵"))
        capture("05-search-locates-next-page")
    }
}
