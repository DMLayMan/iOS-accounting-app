import SwiftUI
import UIKit
import YujiCore

struct ThemeSettingsSections: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    var onCustomColor: () -> Void
    private var settings: AppSettings { state.store.data.settings }

    var body: some View {
        Group {
        Section("显示模式") {
            Picker("外观", selection: Binding(get: { settings.appearance }, set: { value in
                state.perform { state.store.updateSettings { $0.appearance = value } }
            })) {
                Text("系统").tag(AppearanceMode.system)
                Text("浅色").tag(AppearanceMode.light)
                Text("深色").tag(AppearanceMode.dark)
            }.pickerStyle(.segmented).accessibilityIdentifier("theme.appearance")
        }
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 3), spacing: 8) {
                ForEach(AccentTheme.allCases.filter { $0 != .custom }, id: \.self) { theme in
                    let selected = settings.accentTheme == theme
                    Button { apply(theme) } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle().fill(Design.themeAccent(AppSettings(accentTheme: theme), scheme)).frame(width: 30, height: 30)
                                if selected { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(scheme == .dark ? Color.black : Color.white) }
                            }
                            Text(theme.name).font(.caption.weight(selected ? .semibold : .regular)).foregroundStyle(.primary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(selected ? Design.selectedFill(scheme) : .clear, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityLabel(theme.name)
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                        .accessibilityIdentifier("theme.preset.\(theme.rawValue)")
                }
            }.padding(.vertical, 4)
            Button(action: onCustomColor) {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3").foregroundStyle(Color.accentColor)
                    Text("自定义颜色").foregroundStyle(.primary)
                    Spacer()
                    if settings.accentTheme == .custom {
                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                    }
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }.frame(minHeight: 44)
            }.accessibilityValue(settings.accentTheme == .custom ? "已选择" : "未选择")
                .accessibilityIdentifier("theme.custom")
            HStack {
                Text("当前主题").foregroundStyle(.secondary)
                Spacer()
                Text(settings.accentTheme.name).accessibilityIdentifier("theme.current")
                    .accessibilityValue(String(format: "#%06X", settings.accentRGB))
            }.font(.caption)
        } header: { Text("主题色") } footer: {
            Text("用于按钮和选中状态。自定义颜色关闭选色器后应用，深浅色会自动调整明暗。")
        }
        Section {
            previewLayout {
                preview("支出", amount: "−¥128.00", color: Design.expense, icon: "arrow.up.right")
                if !typeSize.isAccessibilitySize { Spacer() }
                preview("收入", amount: "+¥3,200.00", color: Design.income, icon: "arrow.down.left")
            }.padding(.vertical, 4)
            HStack(spacing: 16) {
                Label("退款", systemImage: "arrow.uturn.backward").foregroundStyle(Design.refund)
                Label("转账", systemImage: "arrow.left.arrow.right").foregroundStyle(.secondary)
            }.font(.caption)
        } header: { Text("收支颜色") } footer: {
            Text("支出暖橙、收入青绿、退款蓝色。更换主题后含义保持一致，金额同时保留正负号。")
        }
        }
    }

    private var previewLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
    }
    private func preview(_ title: String, amount: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(amount).font(.headline).monospacedDigit().foregroundStyle(color)
        }
    }
    private func apply(_ theme: AccentTheme, rgb: Int? = nil) {
        state.perform {
            state.store.updateSettings {
                $0.accentTheme = theme
                if let rgb { $0.customAccentRGB = rgb }
            }
        }
    }
}

/// The system editor keeps color dragging in memory; only Done writes the setting.
struct NativeThemeColorPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let rgb: Int
    let apply: (Int) -> Bool
    func makeCoordinator() -> Coordinator { Coordinator(owner: self) }
    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        return host
    }
    func updateUIViewController(_ host: UIViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.owner = self
        guard isPresented, host.presentedViewController == nil, !coordinator.presenting else { return }
        coordinator.presenting = true
        // Present the system controller directly. SwiftUI sheet containment hides its close control.
        DispatchQueue.main.async {
            guard coordinator.owner.isPresented, host.view.window != nil else { coordinator.presenting = false; return }
            let picker = UIColorPickerViewController()
            let value = ThemeRGB(hex: coordinator.owner.rgb)
            picker.selectedColor = UIColor(red: value.red, green: value.green, blue: value.blue, alpha: 1)
            picker.supportsAlpha = false
            picker.delegate = coordinator
            picker.modalPresentationStyle = .pageSheet
            host.present(picker, animated: !UIAccessibility.isReduceMotionEnabled)
            picker.presentationController?.delegate = coordinator
        }
    }
    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
        var owner: NativeThemeColorPicker
        var presenting = false
        init(owner: NativeThemeColorPicker) { self.owner = owner }
        func colorPickerViewControllerDidFinish(_ controller: UIColorPickerViewController) {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
            guard controller.selectedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
            let byte: (CGFloat) -> Int = { Int((min(max($0, 0), 1) * 255).rounded()) }
            _ = owner.apply((byte(red) << 16) | (byte(green) << 8) | byte(blue))
            owner.isPresented = false
            presenting = false
        }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            owner.isPresented = false
            presenting = false
        }
    }
}
