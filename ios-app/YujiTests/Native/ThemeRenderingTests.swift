import XCTest
import SwiftUI
import UIKit
import YujiCore
@testable import Yuji

final class ThemeRenderingTests: XCTestCase {
    func testSemanticColorsRemainReadableInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            var resolved: [String] = []
            for color in [Design.expense, Design.income, Design.refund] {
                let ui = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                XCTAssertTrue(ui.getRed(&r, green: &g, blue: &b, alpha: &a))
                let hex = (Int((r * 255).rounded()) << 16) | (Int((g * 255).rounded()) << 8) | Int((b * 255).rounded())
                let rgb = ThemeRGB(hex: hex)
                for surface in style == .dark ? [0x000000, 0x1C1C1E, 0x2C2C2E] : [0xFFFFFF, 0xF2F2F7] {
                    XCTAssertGreaterThanOrEqual(rgb.contrast(with: ThemeRGB(hex: surface)), 4.5)
                }
                resolved.append(String(hex))
            }
            XCTAssertEqual(Set(resolved).count, 3)
        }
    }
}
