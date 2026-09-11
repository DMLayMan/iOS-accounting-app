import Foundation

public enum AccentTheme: String, Codable, CaseIterable, Sendable {
    case sage, ocean, plum, rose, amber, graphite, custom

    public var name: String {
        switch self {
        case .sage: return "青竹"
        case .ocean: return "海蓝"
        case .plum: return "暮紫"
        case .rose: return "烟玫"
        case .amber: return "琥珀"
        case .graphite: return "石墨"
        case .custom: return "自定义"
        }
    }
    public var rgb: Int {
        switch self {
        case .sage, .custom: return 0x367961
        case .ocean: return 0x376CA0
        case .plum: return 0x7B5D9A
        case .rose: return 0xA15470
        case .amber: return 0x91621F
        case .graphite: return 0x586272
        }
    }
}

/// sRGB contrast is kept independent of UI rendering and persistence.
public struct ThemeRGB: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(hex: Int) {
        red = Double((hex >> 16) & 255) / 255
        green = Double((hex >> 8) & 255) / 255
        blue = Double(hex & 255) / 255
    }
    private init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }
    public func mixed(with other: ThemeRGB, fraction: Double) -> ThemeRGB {
        let t = min(max(fraction, 0), 1)
        return ThemeRGB(red: red + (other.red - red) * t,
                        green: green + (other.green - green) * t,
                        blue: blue + (other.blue - blue) * t)
    }
    public var luminance: Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    public func contrast(with other: ThemeRGB) -> Double {
        (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
    }
    public func accessibleAccent(dark: Bool) -> ThemeRGB {
        let target = ThemeRGB(hex: dark ? 0xFFFFFF : 0)
        let backgrounds = (dark ? [0x000000, 0x1C1C1E, 0x2C2C2E] : [0xFFFFFF, 0xF2F2F7]).map(ThemeRGB.init(hex:))
        let base = dark ? mixed(with: target, fraction: 0.42) : self
        for step in 0...100 {
            let candidate = base.mixed(with: target, fraction: Double(step) / 100)
            if backgrounds.allSatisfy({ background in
                candidate.contrast(with: background) >= 4.6
                    && candidate.contrast(with: background.mixed(with: candidate, fraction: dark ? 0.16 : 0.10)) >= 4.6
            }) { return candidate }
        }
        return target
    }
}

extension AppSettings {
    public var accentRGB: Int { accentTheme == .custom ? customAccentRGB : accentTheme.rgb }
}
