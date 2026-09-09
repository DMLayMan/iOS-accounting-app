import SwiftUI

/// UI v2 视觉 token（白底、炭黑金额、少量鼠尾草绿）。
/// 明亮/深色取值见 PRD UI v2 §2.1。
enum Design {
    // 颜色
    static let sage = Color(red: 0x36/255.0, green: 0x79/255.0, blue: 0x61/255)      // #367961 主动作
    static let sageSageDark = Color(red: 0x9D/255.0, green: 0xCA/255.0, blue: 0xB0/255.0) // 深色主动作

    static func primary(_ scheme: ColorScheme) -> Color { scheme == .dark ? sageSageDark : sage }

    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0x17/255.0, green: 0x1B/255.0, blue: 0x19/255.0) : .white
    }
    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0x1E/255.0, green: 0x24/255.0, blue: 0x20/255.0) : .white
    }
    static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0xED/255.0, green: 0xF1/255.0, blue: 0xEC/255.0)
                       : Color(red: 0x25/255.0, green: 0x2A/255.0, blue: 0x28/255.0)
    }
    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0x98/255.0, green: 0xA4/255.0, blue: 0x9A/255.0)
                       : Color(red: 0x6B/255.0, green: 0x75/255.0, blue: 0x6C/255.0)
    }
    static func separator(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0x30/255.0, green: 0x38/255.0, blue: 0x31/255.0)
                       : Color(red: 0xEA/255.0, green: 0xEC/255.0, blue: 0xE8/255.0)
    }
    static func lightFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0x23/255.0, green: 0x2B/255.0, blue: 0x25/255.0)
                       : Color(red: 0xF3/255.0, green: 0xF5/255.0, blue: 0xF1/255.0)
    }
    static func selectedFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0x31/255.0, green: 0x4A/255.0, blue: 0x3B/255.0)
                       : Color(red: 0xE3/255.0, green: 0xEE/255.0, blue: 0xE7/255.0)
    }

    // 字号 token
    static let ledgerTitle: CGFloat = 27
    static let homeAmount: CGFloat = 51
    static let entryAmount: CGFloat = 46
    static let bodySize: CGFloat = 16
    static let captionSize: CGFloat = 13
    static let captionSmall: CGFloat = 12

    static let keyHeight: CGFloat = 47
    static let categoryRowHeight: CGFloat = 60
    static let saveHeight: CGFloat = 47
}

/// 低饱和分类底色（少量、克制）。
enum CategoryTint {
    static let palette: [Color] = [
        Color(red: 0xE9/255.0, green: 0xEF/255.0, blue: 0xEA/255.0),
        Color(red: 0xE7/255.0, green: 0xED/255.0, blue: 0xF1/255.0),
        Color(red: 0xF1/255.0, green: 0xEC/255.0, blue: 0xE6/255.0),
        Color(red: 0xEC/255.0, green: 0xE9/255.0, blue: 0xF0/255.0),
        Color(red: 0xEA/255.0, green: 0xF0/255.0, blue: 0xEE/255.0),
    ]
    static func tint(for id: EntityID) -> Color {
        let h = abs(id.raw.hashValue)
        return palette[h % palette.count]
    }
}

/// 等宽金额文本。
struct AmountText: View {
    let text: String
    var size: CGFloat = Design.bodySize
    var weight: Font.Weight = .semibold
    var color: Color? = nil
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight, design: .rounded))
            .monospacedDigit()
            .foregroundColor(color)
    }
}
