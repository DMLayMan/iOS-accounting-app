import SwiftUI
import YujiCore

/// 账本只展示累计汇总；逐笔查看交给流水，按期间分析交给统计。
struct LedgerHomeView: View {
    var openStats: () -> Void = {}
    var openFeed: () -> Void = {}
    @EnvironmentObject private var state: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showLedgerSwitch = false
    @State private var showCreateLedger = false
    @State private var showEntry = false
    @State private var showTransfer = false
    @State private var showBudget = false

    var body: some View {
        Group {
            if let ledger = state.activeLedger { content(ledger) }
            else { EmptyLedgerView() }
        }
        .navigationTitle("账本").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLedgerSwitch) { LedgerSwitcherView() }
        .sheet(isPresented: $showCreateLedger) { NavigationStack { LedgerCreateView() } }
        .sheet(isPresented: $showEntry) { EntryContainerView() }
        .sheet(isPresented: $showTransfer) { TransferView() }
        .sheet(isPresented: $showBudget) { if let ledger = state.activeLedger { LedgerBudgetEditor(ledgerID: ledger.id) } }
    }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 1 : 2)
    }
    private var actionLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 20))
    }
    private func content(_ ledger: Ledger) -> some View {
        let overview = state.store.overview(in: ledger.id, through: state.today)
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Label(ledger.name, systemImage: "book.closed")
                        .font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("ledger.currentName")
                    actionLayout {
                        Button { showLedgerSwitch = true } label: { Label("切换账本", systemImage: "arrow.left.arrow.right") }
                            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
                            .frame(minHeight: 44).accessibilityIdentifier("ledger.switch")
                        Button { showCreateLedger = true } label: { Label("新建账本", systemImage: "plus") }
                            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
                            .frame(minHeight: 44).accessibilityIdentifier("ledger.create")
                    }.font(.subheadline).frame(minHeight: 44)
                    if ledger.archived {
                        Text("已归档 · 可以查看和导出历史记录").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("累计收支").font(.headline)
                        Spacer()
                        if !ledger.archived {
                            Button("预算") { showBudget = true }.font(.subheadline).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("ledger.budget")
                        }
                        Button("看统计", action: openStats).font(.subheadline).frame(minHeight: 44)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("累计结余").font(.subheadline).foregroundStyle(.secondary)
                        AmountText(text: statsMoney(overview.totals.surplus), size: 38, weight: .semibold)
                            .accessibilityIdentifier("ledger.surplus")
                    }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        metric("累计收入", cents: overview.totals.income, id: "ledger.income", color: Design.income)
                        metric("累计净支出", cents: overview.totals.netExpense, id: "ledger.netExpense", color: Design.netExpense(overview.totals.netExpense))
                    }
                    Text("支出 \(statsMoney(overview.totals.expense)) · 退款 \(statsMoney(overview.totals.refund))")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(overview.firstRecord.map { "首笔 \(statsDayText($0)) · 截至 \(statsDayText(state.today))" } ?? "还没有记录，记下第一笔后开始累计。")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("ledger.coverage")
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("账户余额").font(.headline)
                        Spacer()
                        NavigationLink("管理", destination: AccountListView()).font(.subheadline).frame(minWidth: 44, minHeight: 44)
                    }
                    metric("合计（含期初余额）", cents: overview.balance, id: "ledger.balance")
                    ForEach(overview.balances) { item in
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.account.name + (item.account.archived ? " · 已归档" : ""))
                                .font(.subheadline).foregroundStyle(.secondary)
                            Spacer(minLength: 12)
                            Text(statsMoney(item.cents)).font(.subheadline.monospacedDigit())
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }.padding(.vertical, 4)
                    }
                    if overview.balances.isEmpty {
                        NavigationLink("新增账户", destination: AccountListView()).frame(minHeight: 44)
                    }
                    if !ledger.archived {
                        Button { showTransfer = true } label: { Label("转账", systemImage: "arrow.left.arrow.right").frame(minHeight: 44) }
                            .font(.subheadline)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("记录概况").font(.headline)
                        Spacer()
                        Button("查看流水", action: openFeed).font(.subheadline).frame(minHeight: 44).accessibilityIdentifier("ledger.openFeed")
                    }
                    Text("\(overview.recordCount) 笔记录 · \(overview.recordedDays) 个记账日")
                        .font(.subheadline).accessibilityIdentifier("ledger.recordCount")
                    if let latest = overview.lastRecord {
                        Text("最近记账 \(statsDayText(latest))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if state.store.draft(for: ledger.id) != nil && !ledger.archived {
                    Button { showEntry = true } label: {
                        Label("继续上次未完成的记录", systemImage: "pencil.line")
                            .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                            .background(Design.selectedFill(scheme), in: RoundedRectangle(cornerRadius: 14))
                    }.accessibilityHint("草稿不计入累计收支")
                }
            }.padding(20)
        }.accessibilityIdentifier("ledger.scroll")
    }
    private func metric(_ title: String, cents: Int64, id: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            AmountText(text: statsMoney(cents), size: 23, weight: .semibold, color: color)
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(title) \(statsMoney(cents))").accessibilityIdentifier(id)
    }
}

struct QuietEmptyView: View {
    let message: String
    var body: some View {
        HStack {
            Spacer()
            Text(message).font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.vertical, 32)
            Spacer()
        }
    }
}

struct EmptyLedgerView: View {
    @State private var showCreate = false
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("还没有账本").font(.system(size: 20, weight: .semibold))
            Text("创建账本，开始记录你的收支。").font(.subheadline).foregroundColor(.secondary)
            Button("新建账本") { showCreate = true }.buttonStyle(.borderedProminent)
            Spacer()
        }.sheet(isPresented: $showCreate) { NavigationStack { LedgerCreateView() } }
    }
}
