import SwiftUI
import YujiCore

/// 统计：月（净支出大数字 + 同环比）/ 年（YTD + 逐月 + 年度同比），分类/标签下钻。
struct StatsView: View {
    @EnvironmentObject var state: AppState
    @State private var period: Period = .month
    @State private var anchor: MonthKey

    enum Period { case month, year }

    init() {
        let d = Day(from: Date())
        _anchor = State(initialValue: d.monthKey)
    }

    var body: some View {
        NavigationStack {
            if let ledger = state.activeLedger {
                let stats = state.stats(for: ledger.id)
                ScrollView {
                    VStack(spacing: 20) {
                        Picker("", selection: $period) {
                            Text("月").tag(Period.month)
                            Text("年").tag(Period.year)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                        .padding(.top, 8)

                        if period == .month {
                            monthView(stats: stats)
                        } else {
                            yearView(stats: stats)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 80)
                }
                .navigationTitle("统计")
            } else {
                EmptyLedgerView()
            }
        }
    }

    // MARK: 月

    @ViewBuilder
    private func monthView(stats: StatsEngine) -> some View {
        // 当前未结束月份取 1..today（与同环比同进度口径一致）；历史完整月取整月（PRD §7.2）。
        let isCurrent = anchor == state.today.monthKey
        let s = isCurrent ? stats.summary(range: anchor.prefix(through: state.today.day))
                          : stats.monthSummary(anchor)
        VStack(alignment: .leading, spacing: 8) {
            // 月份切换
            HStack {
                Button { anchor = anchor.previous } label: {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text("\(anchor.year) 年 \(anchor.month) 月").font(.system(size: 18, weight: .semibold))
                Spacer()
                Button { anchor = anchor.next } label: { Image(systemName: "chevron.right") }
            }
            .padding(.vertical, 4)

            Text(isCurrent ? "净支出 · 截至 \(state.today.month)/\(state.today.day) 已记账" : "净支出")
                .font(.system(size: Design.captionSize)).foregroundColor(.secondary)
            AmountText(text: "¥\(Money(s.netExpense).yuanDescription)", size: 44, weight: .bold)
            Text("支出 ¥\(Money(s.expense).yuanDescription) − 退款 ¥\(Money(s.refund).yuanDescription)")
                .font(.system(size: Design.captionSmall)).foregroundColor(.secondary)
            Text("收入 ¥\(Money(s.income).yuanDescription)  ·  结余 ¥\(Money(s.surplus).yuanDescription)")
                .font(.system(size: Design.captionSmall)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        comparisonCard(title: "环比（对比上月同期）",
                       cmp: stats.momComparison(for: anchor, today: state.today))
        comparisonCard(title: "同比（对比去年同期）",
                       cmp: stats.yoyComparison(for: anchor, today: state.today))

        breakdownSection(stats: stats, range: s.range)
    }

    private func comparisonCard(title: String, cmp: StatsEngine.Comparison) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: Design.captionSize)).foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("¥\(Money(cmp.current).yuanDescription)")
                    .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                if let p = cmp.percent {
                    let up = cmp.delta >= 0
                    Text(String(format: "%@%.1f%%", up ? "+" : "", p))
                        .font(.system(size: Design.bodySize, weight: .semibold))
                        .foregroundColor(up ? .primary : Design.sage)
                } else {
                    Text(reasonText(cmp.status)).font(.system(size: Design.captionSmall)).foregroundColor(.secondary)
                }
            }
            Text("基期 ¥\(Money(cmp.base).yuanDescription)，变化 ¥\(Money(cmp.delta).yuanDescription)")
                .font(.system(size: Design.captionSmall)).foregroundColor(.secondary)
            Text("已记录的收支变化，不代表消费行为判断").font(.system(size: 11)).foregroundColor(.secondary.opacity(0.8))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    private func reasonText(_ status: StatsEngine.Comparison.Status) -> String {
        switch status {
        case .ok: return ""
        case .baseZero: return "基期为 0，无增长率"
        case .baseNegative: return "基期为负值，无增长率"
        case .baseNotCovered: return "基期数据未覆盖"
        case .unequalLength: return "基期月份天数不足，按共同天数比较，不显示增长率"
        }
    }

    // MARK: 年

    @ViewBuilder
    private func yearView(stats: StatsEngine) -> some View {
        let ys = stats.yearSummary(anchor.year, today: state.today)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { anchor = MonthKey(year: anchor.year - 1, month: anchor.month) } label: {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text("\(anchor.year) 年\(ys.isCurrentYear ? " · 截至 \(state.today.month)/\(state.today.day)" : "")")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button { anchor = MonthKey(year: anchor.year + 1, month: anchor.month) } label: {
                    Image(systemName: "chevron.right")
                }
            }
            Text(ys.isCurrentYear ? "YTD 净支出" : "全年净支出")
                .font(.system(size: Design.captionSize)).foregroundColor(.secondary)
            AmountText(text: "¥\(Money(ys.total.netExpense).yuanDescription)", size: 44, weight: .bold)

            comparisonCard(title: "年度同比（对比去年同期）", cmp: ys.yoy)

            // 逐月趋势（条形 + 可访问列表）
            VStack(alignment: .leading, spacing: 8) {
                Text("逐月净支出").font(.system(size: Design.bodySize, weight: .semibold))
                MonthBarChart(months: ys.months)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        breakdownSection(stats: stats, range: ys.ytdRange)
    }

    // MARK: 分类 / 标签

    @ViewBuilder
    private func breakdownSection(stats: StatsEngine, range: ClosedRange<Day>) -> some View {
        let cats = stats.categoryBreakdown(range: range)
        let tags = stats.tagBreakdown(range: range)
        let totalNet = cats.reduce(0) { $0 + $1.net }

        VStack(alignment: .leading, spacing: 10) {
            Text("分类支出").font(.system(size: Design.bodySize, weight: .semibold))
            if cats.isEmpty {
                Text("该期间暂无支出").font(.system(size: Design.captionSize)).foregroundColor(.secondary)
            } else {
                ForEach(cats) { item in
                    BreakdownRow(name: item.pathName, net: item.net, total: totalNet,
                                 expense: item.expense, refund: item.refund)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

        VStack(alignment: .leading, spacing: 10) {
            Text("标签支出").font(.system(size: Design.bodySize, weight: .semibold))
            Text("标签可重叠，各项不可直接相加").font(.system(size: 11)).foregroundColor(.secondary)
            if tags.isEmpty {
                Text("该期间暂无带标签支出").font(.system(size: Design.captionSize)).foregroundColor(.secondary)
            } else {
                ForEach(tags) { item in
                    BreakdownRow(name: item.pathName, net: item.net, total: totalNet,
                                 expense: item.expense, refund: item.refund)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}

struct BreakdownRow: View {
    let name: String
    let net: Int64
    let total: Int64
    let expense: Int64
    let refund: Int64
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(name).font(.system(size: Design.bodySize))
                Spacer()
                Text("¥\(Money(net).yuanDescription)").font(.system(size: Design.bodySize, weight: .semibold))
                    .monospacedDigit()
            }
            // 占当前筛选净支出比例；分母为正才显示
            if total > 0 {
                GeometryReader { geo in
                    let ratio = max(0, min(1, Double(max(0, net)) / Double(total)))
                    Rectangle().fill(Design.sage.opacity(0.75))
                        .frame(width: geo.size.width * ratio)
                }
                .frame(height: 6)
                .background(RoundedRectangle(cornerRadius: 3).fill(Design.sage.opacity(0.12)))
            }
            if refund > 0 {
                Text("支出 ¥\(Money(expense).yuanDescription) · 退款 ¥\(Money(refund).yuanDescription)")
                    .font(.system(size: 11)).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// 逐月条形图；同时提供可读数值（VoiceOver 读出金额）。
struct MonthBarChart: View {
    let months: [MonthKey: PeriodSummary]
    var body: some View {
        let sorted = months.sorted { $0.key < $1.key }
        let maxV = max(1, sorted.map { max(0, $0.value.netExpense) }.max() ?? 1)
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(sorted.indices, id: \.self) { i in
                    let mk = sorted[i].key
                    let s = sorted[i].value
                    VStack(spacing: 2) {
                        Rectangle()
                            .fill(Design.sage.opacity(0.75))
                            .frame(width: 14, height: barHeight(s.netExpense, max: maxV))
                            .accessibilityLabel("\(mk.month) 月净支出 \(Money(s.netExpense).formatted(style: .plain))")
                        Text("\(mk.month)").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 120, alignment: .bottom)
        }
    }
    private func barHeight(_ v: Int64, max: Int64) -> CGFloat {
        CGFloat(max(0, v)) / CGFloat(max) * 100
    }
}
