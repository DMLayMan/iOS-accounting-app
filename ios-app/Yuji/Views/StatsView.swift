import SwiftUI
import Charts
import YujiCore

struct StatsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedComparison: String?
    @State private var basePeriod = false
    @State private var authorFilter: StatsEngine.AuthorFilter = .all
    private var period: BrowsingPeriod { state.browsingPeriod }
    private var month: MonthKey? { period.month(today: state.today) }
    private var yearValue: Int? { period.year(today: state.today) }

    var body: some View {
        NavigationStack {
            Group {
                if let ledger = state.activeLedger {
                    let stats = state.stats(for: ledger.id, authorFilter: authorFilter)
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
            selectedComparison = nil; basePeriod = false; authorFilter = .all
        }
    }

    private func analysis(ledger: Ledger, stats: StatsEngine, range: ClosedRange<Day>) -> some View {
        let summary = stats.summary(range: range)
        let year = yearValue.map { stats.yearSummary($0, today: state.today) }
        return VStack(spacing: 20) {
            authorPicker(ledger.id)
            summaryHeader(summary)
            if authorFilter == .all, month != nil || yearValue != nil {
                StatsBudgetView(ledgerID: ledger.id, period: month != nil ? .month : .year,
                                day: range.lowerBound, cutoff: range.upperBound)
            } else if authorFilter != .all {
                Text("预算按整个账本计算，选择「全部记账人」查看。")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    range: (basePeriod ? cmp.baseRange : cmp.currentRange) ?? range, comparison: cmp,
                    authorFilter: authorFilter, authorLabel: authorFilter == .all ? nil : authorTitle(ledger.id),
                    clearAuthor: { authorFilter = .all })
                    .id("comparison-\(ledger.id.raw)-\(period)-\(selectedComparison)")
            } else {
                CategoryAnalysisView(ledgerID: ledger.id, range: range, authorFilter: authorFilter,
                    authorLabel: authorFilter == .all ? nil : authorTitle(ledger.id), clearAuthor: { authorFilter = .all })
                    .id("\(ledger.id.raw)-\(period)")
            }
        }.padding(20)
    }

    private func authorOptions(_ ledgerID: EntityID) -> [(identity: String, label: String)] {
        // Use the complete ledger history so changing time cannot remove a selected person.
        let records = state.store.activeTransactions(in: ledgerID)
            .filter { $0.kind == .expense || $0.kind == .income || $0.kind == .refund }
        let identities = Set(records.compactMap(\.authorID)).sorted()
        let names = identities.map { state.personName($0, ledgerID: ledgerID, marksSelf: true) }
        return zip(identities, names).map { identity, name in
            let duplicates = identities.filter { state.personName($0, ledgerID: ledgerID, marksSelf: true) == name }
            let label = duplicates.count > 1 ? "\(name) · \((duplicates.firstIndex(of: identity) ?? 0) + 1)" : name
            return (identity: identity, label: label)
        }
    }
    private func authorTitle(_ ledgerID: EntityID) -> String {
        switch authorFilter {
        case .all: return "全部记账人"
        case .unknown: return "未知记账人"
        case .person(let identity):
            return authorOptions(ledgerID).first { $0.identity == identity }?.label
                ?? state.personName(identity, ledgerID: ledgerID, marksSelf: true)
        }
    }
    private func authorPicker(_ ledgerID: EntityID) -> some View {
        let records = state.store.activeTransactions(in: ledgerID).filter { $0.kind.affectsFlow }
        let options = authorOptions(ledgerID)
        let title = authorTitle(ledgerID)
        return VStack(alignment: .leading, spacing: 4) {
            if typeSize.isAccessibilitySize {
                HStack(alignment: .firstTextBaseline) {
                    Text("记账人").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    if authorFilter != .all { clearAuthorButton }
                }
            }
            HStack(alignment: .top, spacing: 16) {
                Menu {
                    Picker("记账人", selection: $authorFilter) {
                        Text("全部记账人").tag(StatsEngine.AuthorFilter.all)
                        ForEach(options, id: \.identity) { option in
                            Text(option.label).tag(StatsEngine.AuthorFilter.person(option.identity))
                        }
                        if records.contains(where: { $0.authorID == nil }) || authorFilter == .unknown {
                            Text("未知记账人").tag(StatsEngine.AuthorFilter.unknown)
                        }
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if !typeSize.isAccessibilitySize { Image(systemName: "person.crop.circle") }
                        Text(title).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                    }.font(.subheadline).frame(minHeight: 44)
                }.accessibilityLabel("记账人，\(title)").accessibilityIdentifier("stats.authorFilter")
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !typeSize.isAccessibilitySize, authorFilter != .all {
                    clearAuthorButton.fixedSize()
                }
            }
            if authorFilter != .all {
                Text("按记录创建人统计，不代表实际付款人。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var clearAuthorButton: some View {
        Button("清除") { authorFilter = .all }
            .font(.subheadline).frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("清除记账人筛选").accessibilityIdentifier("stats.clearAuthor")
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
                if let percent = cmp.percent {
                    Text(String(format: "%+.1f%%", percent)).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                    Text("\(cmp.delta >= 0 ? "增加" : "减少") \(statsMoney(abs(cmp.delta)))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(statsComparisonReason(cmp.status))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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
