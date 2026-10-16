import XCTest
import SwiftUI
import UIKit
import YujiCore
@testable import Yuji

final class ThemeRenderingTests: XCTestCase {
    func testSemanticColorsRemainReadableInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            var environment = EnvironmentValues()
            environment.colorScheme = style == .dark ? .dark : .light
            var resolved: [String] = []
            for color in [Design.expense, Design.income, Design.refund, Design.secondary] {
                // Resolve in the actual SwiftUI environment. On iOS 17, bridging
                // Color back to UIColor first freezes it in the current appearance.
                let value = color.resolve(in: environment)
                XCTAssertEqual(value.opacity, 1)
                let hex = (Int((value.red * 255).rounded()) << 16) | (Int((value.green * 255).rounded()) << 8) | Int((value.blue * 255).rounded())
                let rgb = ThemeRGB(hex: hex)
                for surface in style == .dark ? [0x000000, 0x1C1C1E, 0x2C2C2E] : [0xFFFFFF, 0xF2F2F7] {
                    XCTAssertGreaterThanOrEqual(rgb.contrast(with: ThemeRGB(hex: surface)), 4.5, "style=\(style.rawValue), foreground=\(String(hex, radix: 16)), surface=\(String(surface, radix: 16))")
                }
                resolved.append(String(hex))
            }
            XCTAssertEqual(Set(resolved).count, 4)
        }
    }
}
