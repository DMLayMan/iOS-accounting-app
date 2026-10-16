import XCTest
import UIKit
import YujiCore
@testable import Yuji

final class AccessibilityCompatibilityTests: XCTestCase {
    func testCategoryCatalogSymbolsExistOnRunningOSAndHaveSpokenNames() {
        for icon in CategoryIcon.all {
            XCTAssertNotNil(UIImage(systemName: icon.id), "Missing on \(UIDevice.current.systemVersion): \(icon.id)")
            XCTAssertEqual(CategorySymbol.accessibilityName(for: icon.id), icon.name)
        }
        for name in ["早餐", "午餐晚餐", "咖啡茶饮", "零食", "水果", "外卖", "饮品", "买菜", "甜品", "火锅", "聚餐", "夜宵", "服饰", "数码", "房租水电", "家居用品", "门诊药品", "影音游戏", "游戏", "运动健身", "旅行休闲", "公共交通", "打车", "加油停车", "工资", "理财收益"] {
            let symbol = CategorySymbol.name(for: name)
            XCTAssertNotNil(UIImage(systemName: symbol), "Missing on \(UIDevice.current.systemVersion): \(symbol)")
            XCTAssertNotEqual(CategorySymbol.accessibilityName(for: symbol), "其他", name)
        }
    }

    func testSpokenDayIncludesYearMonthAndDayAcrossYearBoundary() {
        XCTAssertEqual(spokenDayText(Day(year: 2025, month: 12, day: 31)), "2025年12月31日")
        XCTAssertEqual(spokenDayText(Day(year: 2026, month: 1, day: 1)), "2026年1月1日")
    }
}
