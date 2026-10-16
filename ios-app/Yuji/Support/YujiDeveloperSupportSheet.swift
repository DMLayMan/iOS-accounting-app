import SwiftUI
import DeveloperSupportKit
import EngagementPromptKit

struct YujiDeveloperSupportSheet: View {
    let presentation: DeveloperSupportCoordinator.Presentation
    @EnvironmentObject private var support: DeveloperSupportCoordinator
    @Environment(\.colorScheme) private var scheme
    @Environment(\.yujiAccent) private var accent

    var body: some View {
        switch presentation {
        case .support:
            DeveloperSupportSheet(model: support.model, appearance: .init(
                background: Color(uiColor: .systemGroupedBackground),
                surface: Color(uiColor: .secondarySystemGroupedBackground),
                secondary: Color.primary.opacity(0.7),
                accent: accent, onAccent: scheme == .dark ? .black : .white), pricePresentation: .localized)
        case .invitation:
            EngagementPromptView(skin: .init(
                title: "已经记下 100 笔",
                message: "好用的话，请开发者喝杯咖啡吧。\n支持与否，都能继续好好记账。",
                acceptLabel: "请一杯咖啡", dismissLabel: "继续记账",
                secondary: Color.primary.opacity(0.7),
                accent: accent, onAccent: scheme == .dark ? .black : .white),
                onAccept: { support.acceptInvitation() }, onDismiss: { support.presentation = nil })
        }
    }

}
