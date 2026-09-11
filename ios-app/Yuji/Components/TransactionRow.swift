import SwiftUI
import YujiCore

/// 流水行：分类为主标题，备注辅助；金额右对齐；统一线性图标。
struct TransactionRow: View {
    let t: YujiCore.Transaction
    var showsDate = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        rowLayout {
            HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Design.money(t.kind))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Design.money(t.kind).opacity(scheme == .dark ? 0.12 : 0.07)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).lineLimit(2).foregroundColor(.primary)
                if let sub = subtitle, !sub.isEmpty {
                    Text(sub).font(.caption).foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(amountText).font(.system(.body, design: .rounded).weight(.semibold)).monospacedDigit()
                .foregroundColor(amountColor).lineLimit(1).minimumScaleFactor(0.6).layoutPriority(1)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var rowLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
    }
    private var iconName: String {
        switch t.kind {
        case .expense, .income: return state.store.category(t.categoryID).map { CategorySymbol.name(for: $0) } ?? "square.grid.2x2"
        case .refund: return "arrow.uturn.backward.circle"
        case .transfer: return "arrow.left.arrow.right"
        }
    }
    private var title: String {
        if t.kind == .transfer { return "转账" }
        if t.kind == .refund { return "退款" }
        if let cid = t.categoryID, let c = state.store.category(cid) { return c.name }
        return t.kind.displayName
    }
    private var subtitle: String? {
        let parts: [String] = [
            showsDate ? statsDayText(t.date) : nil,
            state.store.account(t.accountID)?.name,
            t.note
        ].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    private var amountText: String {
        let m = Money(t.amountCents)
        switch t.kind {
        case .expense: return "-¥\(m.yuanDescription)"
        case .income: return "+¥\(m.yuanDescription)"
        case .refund: return "+¥\(m.yuanDescription)"
        case .transfer: return "¥\(m.yuanDescription)"
        }
    }
    private var amountColor: Color? {
        Design.money(t.kind)
    }
}
