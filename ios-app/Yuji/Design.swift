import SwiftUI
import UIKit
import YujiCore

/// Theme accents express actions; financial colors retain their meaning across themes.
enum Design {
    static func primary(_ scheme: ColorScheme) -> Color { .accentColor }
    static func themeAccent(_ settings: AppSettings, _ scheme: ColorScheme) -> Color {
        let rgb = ThemeRGB(hex: settings.accentRGB).accessibleAccent(dark: scheme == .dark)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
    static func background(_ scheme: ColorScheme) -> Color { Color(.systemBackground) }
    static func surface(_ scheme: ColorScheme) -> Color { Color(.systemBackground) }
    static func primaryText(_ scheme: ColorScheme) -> Color { .primary }
    static func secondaryText(_ scheme: ColorScheme) -> Color { .secondary }
    static func separator(_ scheme: ColorScheme) -> Color { Color(.separator) }
    static func lightFill(_ scheme: ColorScheme) -> Color { Color(.secondarySystemBackground) }
    static func selectedFill(_ scheme: ColorScheme) -> Color { .accentColor.opacity(scheme == .dark ? 0.16 : 0.10) }

    static let expense = semantic(light: 0xA65332, dark: 0xE8AB8A)
    static let income = semantic(light: 0x237A68, dark: 0x95CEB8)
    static let refund = semantic(light: 0x516FA1, dark: 0xA6BDE5)
    static func money(_ kind: TransactionKind) -> Color {
        switch kind {
        case .expense: return expense
        case .income: return income
        case .refund: return refund
        case .transfer: return .secondary
        }
    }
    static func netExpense(_ cents: Int64) -> Color { cents == 0 ? .primary : (cents < 0 ? refund : expense) }
    private static func semantic(light: Int, dark: Int) -> Color {
        Color(UIColor { traits in
            let rgb = ThemeRGB(hex: traits.userInterfaceStyle == .dark ? dark : light)
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
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

/// 等宽金额文本。
struct AmountText: View {
    @ScaledMetric private var textScale = 1.0
    let text: String
    var size: CGFloat = Design.bodySize
    var weight: Font.Weight = .semibold
    var color: Color? = nil
    var body: some View {
        Text(text)
            .font(.system(size: size * textScale, weight: weight, design: .rounded))
            .monospacedDigit()
            .foregroundColor(color)
            .lineLimit(1).minimumScaleFactor(0.5)
    }
}

struct SolidActionStyle: ButtonStyle {
    @Environment(\.yujiAccent) private var accent
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(enabled ? (scheme == .dark ? Color.black : Color.white) : Color.secondary)
            .background(enabled ? accent : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct CleanSheetSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) { content.presentationBackground(Color(.systemBackground)) }
        else { content.background(Color(.systemBackground)) }
    }
}

/// A page-bound decision avoids stacking an alert/popover over another task sheet.
struct FormExitGuard: ViewModifier {
    let isDirty: Bool
    @Binding var requested: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    func body(content: Content) -> some View {
        content.disabled(requested).interactiveDismissDisabled(isDirty)
            .safeAreaInset(edge: .bottom) {
                if requested {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("放弃这次修改？").font(.headline)
                        Text("已保存的内容不会改变。").font(.subheadline).foregroundStyle(.secondary)
                        actionsLayout {
                            Button("继续编辑") { requested = false }
                                .buttonStyle(SolidActionStyle()).accessibilityIdentifier("form.keepEditing")
                            Button("放弃修改", role: .destructive) { dismiss() }
                                .font(.body).frame(maxWidth: .infinity, minHeight: 50)
                                .accessibilityIdentifier("form.discard")
                        }
                    }.padding(20).background(Color(.systemBackground))
                }
            }
    }
    private var actionsLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
    }
}

struct AppAccentModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let settings: AppSettings
    func body(content: Content) -> some View {
        let accent = Design.themeAccent(settings, scheme)
        content.accentColor(accent).tint(accent).environment(\.yujiAccent, accent)
    }
}

/// Resolve the product accent before custom button styles enter system sheet containers.
private struct YujiAccentKey: EnvironmentKey {
    static let defaultValue = Color("AccentColor")
}
extension EnvironmentValues {
    var yujiAccent: Color {
        get { self[YujiAccentKey.self] }
        set { self[YujiAccentKey.self] = newValue }
    }
}
