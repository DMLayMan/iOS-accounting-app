import SwiftUI
import Charts
import YujiCore

struct StatsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedComparison: String?
    @State private var basePeriod = false
    private var period: BrowsingPeriod { state.browsingPeriod }
    private var month: MonthKey? { period.month(today: state.today) }
    private var yearValue: Int? { period.year(today: state.today) }

    var body: some View {
        NavigationStack {
            Group {
                if let ledger = state.activeLedger {
                    let stats = state.stats(for: ledger.id)
                    ScrollView {
                        if let range = period.statisticsRange(today: state.today, earliest: state.browsingBounds.lowerBound) {
                            analysis(ledger: ledger, stats: stats, range: range)
                        } else {
                            VStack(spacing: 12) {
                                Text("这段时间尚未发生").font(.headline).accessibilityIdentifier("stats.futurePeriod")
                                Text("统计只计算截至今天的收支。未来日期的记录可在流水中查看。")
                                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                Button("回到本月") { state.browsingPeriod = .currentMonth }
                                    .frame(minHeight: 44).accessibilityIdentifier("stats.resetPeriod")
                            }.padding(24).frame(maxWidth: .infinity)
                        }
                    }.accessibilityIdentifier("stats.scroll")
                        .safeAreaInset(edge: .top, spacing: 0) {
                            PeriodNavigation(prefix: "stats")
                        }
                } else { EmptyLedgerView() }
            }
            .navigationTitle("统计").navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: period) { _ in selectedComparison = nil; basePeriod = false }
        .onChange(of: state.activeLedger?.id) { _ in
            selectedComparison = nil; basePeriod = false
        }
    }

    private func analysis(ledger: Ledger, stats: StatsEngine, range: ClosedRange<Day>) -> some View {
        let summary = stats.summary(range: range)
        let year = yearValue.map { stats.yearSummary($0, today: state.today) }
        return VStack(spacing: 24) {
            summaryHeader(summary)
            if month != nil || yearValue != nil {
                StatsBudgetView(ledgerID: ledger.id, period: month != nil ? .month : .year,
                                day: range.lowerBound, cutoff: range.upperBound)
            }
            if let month {
                adaptiveLayout {
                    comparisonLink("环比", stats.momComparison(for: month, today: state.today), ledger.id)
                    comparisonLink("同比", stats.yoyComparison(for: month, today: state.today), ledger.id)
                }
            } else if let year {
                comparisonLink("年度同比", year.yoy, ledger.id)
                MonthBarChart(months: year.months) { month in state.browsingPeriod = .month(month) }
            } else {
                Text("预算与同环比按月或年查看。当前图表和明细按所选范围汇总。")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let selectedComparison, let cmp = comparison(stats) {
                comparisonPanel(selectedComparison, cmp)
                CategoryAnalysisView(ledgerID: ledger.id,
                    range: (basePeriod ? cmp.baseRange : cmp.currentRange) ?? range, comparison: cmp)
                    .id("comparison-\(ledger.id.raw)-\(period)-\(selectedComparison)")
            } else {
                CategoryAnalysisView(ledgerID: ledger.id, range: range).id("\(ledger.id.raw)-\(period)")
            }
        }.padding(20)
    }

    private func comparison(_ stats: StatsEngine) -> StatsEngine.Comparison? {
        if let month {
            return selectedComparison == "环比" ? stats.momComparison(for: month, today: state.today)
                : stats.yoyComparison(for: month, today: state.today)
        }
        if let yearValue { return stats.yearSummary(yearValue, today: state.today).yoy }
        return nil
    }

    private func comparisonPanel(_ title: String, _ cmp: StatsEngine.Comparison) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title + "分析").font(.headline)
                Spacer()
                Button("收起") { selectedComparison = nil; basePeriod = false }
                    .font(.subheadline).accessibilityIdentifier("stats.closeComparison")
            }
            Text(cmp.status == .baseNotCovered ? "基期记录范围不足" : (cmp.delta == 0 ? "全部分类净支出持平" : "全部分类净支出\(cmp.delta > 0 ? "增加" : "减少") \(statsMoney(abs(cmp.delta)))"))
                .font(.subheadline).accessibilityIdentifier("stats.changeConclusion")
            Text(statsComparisonReason(cmp.status)).font(.caption).foregroundStyle(.secondary)
            Picker("对比时期", selection: $basePeriod) {
                Text("本期").tag(false); Text("基期").tag(true)
            }.pickerStyle(.segmented).accessibilityIdentifier("stats.comparisonPeriod")
            if let range = basePeriod ? cmp.baseRange : cmp.currentRange { StatsRangeLabel(range: range) }
            Text("下方图表与明细随时期、分类一起切换。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 8)
    }

    private func summaryHeader(_ s: PeriodSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            adaptiveLayout {
                Text("净支出").font(.subheadline).foregroundStyle(.secondary)
                if !typeSize.isAccessibilitySize { Spacer() }
                StatsRangeLabel(range: s.range)
            }
            Text(statsMoney(s.netExpense)).font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .foregroundStyle(Design.netExpense(s.netExpense))
                .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1).accessibilityIdentifier("stats.net")
            Text("支出 \(statsMoney(s.expense)) − 退款 \(statsMoney(s.refund))")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            adaptiveLayout {
                summaryValue("收入", s.income, color: Design.income)
                if !typeSize.isAccessibilitySize { Spacer() }
                summaryValue("结余", s.surplus)
            }.padding(.top, 6)
        }
    }
    private var adaptiveLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }
    private func summaryValue(_ title: String, _ amount: Int64, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(statsMoney(amount)).font(.headline).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                .foregroundStyle(color)
        }
    }
    private func comparisonLink(_ title: String, _ cmp: StatsEngine.Comparison, _ ledgerID: EntityID) -> some View {
        Button {
            selectedComparison = selectedComparison == title ? nil : title
            basePeriod = false
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack { Text(title).font(.caption); Spacer(); Image(systemName: selectedComparison == title ? "chevron.up" : "chevron.down").font(.caption2) }.foregroundStyle(.secondary)
                Text(cmp.percent.map { String(format: "%+.1f%%", $0) } ?? "暂不计算")
                    .font(.title3.weight(.semibold)).foregroundStyle(.primary)
                Text(cmp.status == .ok ? "\(cmp.delta >= 0 ? "增加" : "减少") \(statsMoney(abs(cmp.delta)))" : statsComparisonReason(cmp.status))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityIdentifier("stats.compare.\(title)")
    }
}

struct MonthBarChart: View {
    let months: [MonthKey: PeriodSummary]
    let select: (MonthKey) -> Void
    var body: some View {
        let sorted = months.keys.sorted()
        VStack(alignment: .leading, spacing: 12) {
            Text("逐月净支出").font(.headline)
            Text("金额单位：元 · 负值表示退款多于支出").font(.caption).foregroundStyle(.secondary)
            Chart {
                ForEach(sorted, id: \.self) { month in
                BarMark(x: .value("月份", month.month), y: .value("净支出（元）", Double(months[month]!.netExpense) / 100))
                    .foregroundStyle(Design.netExpense(months[month]!.netExpense))
                    .cornerRadius(3)
                    .accessibilityLabel("\(month.month) 月")
                    .accessibilityValue(statsMoney(months[month]!.netExpense))
                }
                RuleMark(y: .value("零", 0)).foregroundStyle(Color.secondary.opacity(0.3))
            }
            .chartXScale(domain: 0.5...12.5)
            .chartXAxis { AxisMarks(values: sorted.map(\.month)) }
            .frame(height: 164)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded { value in
                        let x = value.location.x - geometry[proxy.plotAreaFrame].origin.x
                        if let m: Double = proxy.value(atX: x), let month = sorted.first(where: { $0.month == Int(m.rounded()) }) { select(month) }
                    })
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sorted, id: \.self) { month in
                        Button { select(month) } label: {
                            VStack(spacing: 3) {
                                Text("\(month.month) 月").font(.caption.weight(.semibold))
                                Text(statsMoney(months[month]!.netExpense)).font(.caption2).monospacedDigit()
                            }.padding(10).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).accessibilityIdentifier("stats.month.\(month.month)")
                    }
                }
            }
        }
    }
}
