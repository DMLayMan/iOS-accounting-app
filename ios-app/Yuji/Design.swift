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
    static func secondaryText(_ scheme: ColorScheme) -> Color { secondary }
    /// Opaque text colors retain 4.5:1 contrast on the app's grouped and plain surfaces.
    static let secondary = semantic(light: 0x62666B, dark: 0xB8BAC0)
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
        case .transfer: return secondary
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

extension View {
    /// Apply to the content inside a Button/NavigationLink, not outside the control.
    func minimumTouchTarget() -> some View {
        frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }
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

/// A form-owned completion bar stays above the keyboard without SwiftUI's
/// InputAccessoryBar, whose initial sizing produces a runtime issue on iOS 26/27.
/// The caller owns focus/visibility and excludes any child form or exit decision.
struct KeyboardCompletionBar: ViewModifier {
    let visible: Bool
    var title = "完成输入"
    let complete: () -> Void
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if visible {
                HStack {
                    Spacer()
                    Button(action: complete) {
                        Text(title).font(.body.weight(.semibold))
                            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }.accessibilityIdentifier("keyboard.complete")
                }.padding(.horizontal, 20).background(Color(.systemBackground))
            }
        }
    }
}

/// A page-bound decision avoids stacking an alert/popover over another task sheet.
struct FormExitGuard: ViewModifier {
    let isDirty: Bool
    @Binding var requested: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @AccessibilityFocusState private var decisionFocused: Bool
    func body(content: Content) -> some View {
        content.disabled(requested).accessibilityHidden(requested).interactiveDismissDisabled(isDirty)
            .safeAreaInset(edge: .bottom) {
                if requested {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("放弃这次修改？").font(.headline).accessibilityAddTraits(.isHeader)
                            .accessibilityFocused($decisionFocused).onAppear { decisionFocused = true }
                        Text("已保存的内容不会改变。").font(.subheadline).foregroundStyle(.secondary)
                        actionsLayout {
                            Button("继续编辑") { requested = false }
                                .buttonStyle(SolidActionStyle()).accessibilityIdentifier("form.keepEditing")
                            Button(role: .destructive) { dismiss() } label: {
                                Text("放弃修改").font(.body).frame(maxWidth: .infinity, minHeight: 50).contentShape(Rectangle())
                            }
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

/// System presentations may reset the ambient tint. Resolve the app theme at
/// every presentation root, rather than letting individual pages invent colors.
struct ThemedPresentationRoot<Content: View>: View {
    @ObservedObject var state: AppState
    let content: Content
    var body: some View {
        content.modifier(AppAccentModifier(settings: state.store.data.settings))
            .environmentObject(state)
            .environment(\.locale, Locale(identifier: "zh_CN"))
    }
}

private struct YujiBooleanSheet<Sheet: View>: ViewModifier {
    @EnvironmentObject private var state: AppState
    let isPresented: Binding<Bool>
    let onDismiss: (() -> Void)?
    let sheetContent: () -> Sheet
    func body(content: Content) -> some View {
        let presentingState = state
        return content.sheet(isPresented: isPresented, onDismiss: onDismiss) {
            ThemedPresentationRoot(state: presentingState, content: sheetContent())
        }
    }
}

private struct YujiItemSheet<Item: Identifiable, Sheet: View>: ViewModifier {
    @EnvironmentObject private var state: AppState
    let item: Binding<Item?>
    let onDismiss: (() -> Void)?
    let sheetContent: (Item) -> Sheet
    func body(content: Content) -> some View {
        let presentingState = state
        return content.sheet(item: item, onDismiss: onDismiss) {
            ThemedPresentationRoot(state: presentingState, content: sheetContent($0))
        }
    }
}

extension View {
    func yujiSheet<Sheet: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                               @ViewBuilder content: @escaping () -> Sheet) -> some View {
        modifier(YujiBooleanSheet(isPresented: isPresented, onDismiss: onDismiss, sheetContent: content))
    }

    func yujiSheet<Item: Identifiable, Sheet: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                   @ViewBuilder content: @escaping (Item) -> Sheet) -> some View {
        modifier(YujiItemSheet(item: item, onDismiss: onDismiss, sheetContent: content))
    }
}
