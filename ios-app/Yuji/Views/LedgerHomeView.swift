import SwiftUI
import YujiCore

/// P01 总览：当前账本/月份；本月净支出大数字；预算摘要；最近记录；草稿恢复条。
struct LedgerHomeView: View {
    @EnvironmentObject var state: AppState
    @State private var showLedgerSwitch = false
    @State private var showEntry = false
    @State private var showTransfer = false

    var body: some View {
        Group {
            if let ledger = state.activeLedger {
                content(ledger: ledger)
            } else {
                EmptyLedgerView()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { showLedgerSwitch = true } label: {
                    HStack(spacing: 4) {
                        Text(state.activeLedger?.name ?? "余记")
                            .font(.system(size: Design.ledgerTitle - 10, weight: .bold))
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .accessibilityLabel("切换账本")
            }
        }
        .sheet(isPresented: $showLedgerSwitch) { LedgerSwitcherView() }
        .sheet(isPresented: $showEntry) { EntryContainerView() }
        .sheet(isPresented: $showTransfer) { TransferView() }
    }

    @ViewBuilder
    private func content(ledger: Ledger) -> some View {
        let stats = state.stats(for: ledger.id)
        let month = state.currentMonth
        let summary = stats.monthSummary(month)
        let recent = Array(state.store.activeTransactions(in: ledger.id)
            .sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }.prefix(8))
        let draft = state.store.draft(for: ledger.id)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 本月净支出：大数字
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(month.year) 年 \(month.month) 月 · 净支出")
                        .font(.system(size: Design.captionSize))
                        .foregroundColor(.secondary)
                    AmountText(text: "¥\(Money(summary.netExpense).yuanDescription)",
                               size: Design.homeAmount, weight: .bold)
                        .accessibilityLabel("本月净支出 \(Money(summary.netExpense).formatted(style: .plain))")
                    Text("支出 ¥\(Money(summary.expense).yuanDescription)  ·  退款 ¥\(Money(summary.refund).yuanDescription)")
                        .font(.system(size: Design.captionSmall))
                        .foregroundColor(.secondary)
                    Text("收入 ¥\(Money(summary.income).yuanDescription)  ·  结余 ¥\(Money(summary.surplus).yuanDescription)")
                        .font(.system(size: Design.captionSmall))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // 账户余额速览
                AccountStripView(ledgerID: ledger.id)

                // 快捷动作：转账
                HStack(spacing: 12) {
                    Button { showTransfer = true } label: {
                        Label("转账", systemImage: "arrow.left.arrow.right")
                            .font(.system(size: Design.bodySize, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Design.lightFill(ColorScheme.light)))
                            .foregroundColor(.primary)
                    }
                    NavigationLink {
                        StatsView()
                    } label: {
                        Label("看统计", systemImage: "chart.bar")
                            .font(.system(size: Design.bodySize, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Design.lightFill(ColorScheme.light)))
                            .foregroundColor(.primary)
                    }
                }
                .padding(.horizontal, 20)

                // 草稿恢复条
                if draft != nil {
                    Button { showEntry = true } label: {
                        HStack {
                            Image(systemName: "pencil.line")
                            Text("继续上次未完成的记录")
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12))
                        }
                        .font(.system(size: Design.bodySize))
                        .foregroundColor(Design.sage)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Design.selectedFill(ColorScheme.light)))
                        .padding(.horizontal, 20)
                    }
                    .accessibilityHint("打开后恢复未保存的金额、分类与备注")
                }

                // 最近记录
                VStack(alignment: .leading, spacing: 4) {
                    Text("最近记录")
                        .font(.system(size: Design.bodySize, weight: .semibold))
                        .padding(.horizontal, 20)
                    if recent.isEmpty {
                        QuietEmptyView(message: "还没有记录，点底部 ＋ 记第一笔")
                            .padding(.horizontal, 20)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(recent) { t in
                                NavigationLink {
                                    TransactionDetailView(transactionID: t.id)
                                } label: {
                                    TransactionRow(t: t)
                                }
                                .buttonStyle(.plain)
                                Divider().padding(.leading, 20)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                Spacer(minLength: 80)
            }
        }
    }
}

struct AccountStripView: View {
    let ledgerID: EntityID
    @EnvironmentObject var state: AppState
    var body: some View {
        let accounts = state.store.accounts(in: ledgerID, includeArchived: false)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(accounts) { acc in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(acc.name).font(.system(size: Design.captionSmall)).foregroundColor(.secondary)
                        AmountText(text: "¥\(Money(state.store.balance(accountID: acc.id)).yuanDescription)",
                                   size: 18, weight: .semibold)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

/// 流水行：分类为主标题，备注辅助；金额右对齐；统一线性图标。
struct TransactionRow: View {
    let t: Transaction
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Design.primary(scheme))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Design.lightFill(scheme)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: Design.bodySize)).foregroundColor(.primary)
                if let sub = subtitle, !sub.isEmpty {
                    Text(sub).font(.system(size: Design.captionSmall)).foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            AmountText(text: amountText, size: Design.bodySize, weight: .semibold,
                       color: amountColor)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var iconName: String {
        switch t.kind {
        case .expense: return "fork.knife"
        case .income: return "arrow.down.circle"
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
        switch t.kind {
        case .expense: return .primary
        case .income, .refund: return Design.sage
        case .transfer: return .secondary
        }
    }
}

struct QuietEmptyView: View {
    let message: String
    var body: some View {
        HStack {
            Spacer()
            Text(message).font(.system(size: Design.captionSize)).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.vertical, 32)
            Spacer()
        }
    }
}

struct EmptyLedgerView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("还没有账本").font(.system(size: 20, weight: .semibold))
            Text("在「我的 → 我的账本」创建一个账本开始记账").font(.system(size: 14)).foregroundColor(.secondary)
            Spacer()
        }
    }
}
