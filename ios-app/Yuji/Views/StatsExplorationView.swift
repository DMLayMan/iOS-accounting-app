import SwiftUI
import YujiCore

/// Chart, category selection and transactions share one state on the statistics page.
struct CategoryAnalysisView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    let ledgerID: EntityID
    let range: ClosedRange<Day>
    var comparison: StatsEngine.Comparison? = nil
    @State private var kind: TransactionKind = .expense
    @State private var sort: StatsEngine.CategorySort = .amount
    @State private var categoryID: EntityID?
    @State private var showAllCategories = false
    @State private var largestFirst = false
    @State private var limit = 20
    private var stats: StatsEngine { state.stats(for: ledgerID) }
    private var parentID: EntityID? {
        guard let node = state.store.category(categoryID) else { return nil }
        return node.parentID ?? node.id
    }
    private var ringSelection: Binding<EntityID?> {
        Binding(get: { parentID }, set: { categoryID = $0 })
    }
    private var records: [YujiCore.Transaction] {
        let values = stats.categoryTransactions(range: range, kind: kind, categoryID: categoryID)
        return largestFirst ? values.sorted {
            $0.amountCents == $1.amountCents ? $0.id.raw < $1.id.raw : $0.amountCents > $1.amountCents
        } : values
    }
    var body: some View {
        let rows = stats.categoryGroups(range: range, kind: kind, sort: sort)
        let total = rows.reduce(Int64(0)) { $0 + $1.expense }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("收支去向").font(.headline)
                Spacer()
                Picker("收支口径", selection: $kind) {
                    Text("支出").tag(TransactionKind.expense); Text("收入").tag(TransactionKind.income)
                }.pickerStyle(.segmented).frame(width: 120).accessibilityIdentifier("stats.measure")
            }
            if let comparison, kind == .expense, comparison.status != .baseNotCovered,
               let current = comparison.currentRange, let base = comparison.baseRange {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(stats.categoryChanges(currentRange: current, baseRange: base)) { item in
                            Button { categoryID = item.id } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.name).font(.subheadline)
                                    Text("\(item.delta >= 0 ? "+" : "−")\(statsMoney(abs(item.delta)))")
                                        .font(.caption).monospacedDigit()
                                }.padding(12).background(parentID == item.id ? Design.selectedFill(scheme) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).accessibilityLabel("\(item.name)净支出变化 \(item.delta >= 0 ? "增加" : "减少") \(statsMoney(abs(item.delta)))")
                        }
                    }
                }
            }
            if rows.isEmpty {
                Text("这段时间没有\(kind.displayName)记录").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100).accessibilityIdentifier("stats.empty")
            } else {
                chartLayout {
                    if total > 0 && !typeSize.isAccessibilitySize {
                        DistributionRing(rows: rows.sorted { $0.id.raw < $1.id.raw }, total: total, selected: ringSelection, kind: kind)
                            .frame(maxWidth: .infinity)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(rows.prefix(showAllCategories || typeSize.isAccessibilitySize ? rows.count : 4).enumerated()), id: \.element.id) { index, row in
                            rankingRow(row, rank: index + 1, total: total)
                        }
                    }.frame(maxWidth: .infinity)
                }
                HStack {
                    if rows.count > 4 && !typeSize.isAccessibilitySize {
                        Button(showAllCategories ? "收起分类" : "全部 \(rows.count) 类") { showAllCategories.toggle() }
                            .accessibilityIdentifier("stats.moreCategories")
                    }
                    if rows.count <= 4 {
                        Text(kind == .expense ? "占比按支出 · 退款单列" : "占比按收入 · 不含转账")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        ForEach(StatsEngine.CategorySort.allCases.filter { kind == .expense || $0 != .refund }, id: \.self) { option in
                            Button("按\(option.rawValue)排序") { sort = option }.accessibilityIdentifier("stats.sort.\(option.rawValue)")
                        }
                    } label: { Label(sort.rawValue + "排序", systemImage: "arrow.down") }
                    .accessibilityIdentifier("stats.sort")
                }.font(.caption).frame(minHeight: 44)
            }
            Divider()
            recordsToolbarLayout {
                HStack(spacing: 8) {
                    Text("收支明细").font(.headline)
                    Text("\(records.count) 条").font(.caption).foregroundStyle(.secondary)
                }
                if !typeSize.isAccessibilitySize { Spacer() }
                HStack(spacing: 14) {
                    Menu {
                        Button("时间从新到旧") { largestFirst = false }.accessibilityIdentifier("stats.records.date")
                        Button("金额从高到低") { largestFirst = true }.accessibilityIdentifier("stats.records.amount")
                    } label: { Label(largestFirst ? "金额" : "时间", systemImage: "arrow.down").frame(minHeight: 44) }
                    .font(.caption).accessibilityIdentifier("stats.transactionSort")
                    .accessibilityLabel(largestFirst ? "金额从高到低" : "时间从新到旧")
                    if categoryID != nil {
                        Button("全部") { categoryID = nil }.font(.subheadline).frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("全部分类").accessibilityIdentifier("stats.resetFilters")
                    }
                }
            }.frame(minHeight: 44).id("transactions")
            if let parentID {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(state.store.category(parentID)?.name ?? "全部", id: parentID, prefix: "stats.childAll")
                        ForEach(state.store.categories(in: ledgerID, kind: kind, includeArchived: true).filter { $0.parentID == parentID }) { node in
                            filterChip(node.name, id: node.id)
                        }
                    }
                }.id(parentID)
            }
            summary
            if records.isEmpty {
                Text("当前筛选没有记录，试试其他分类。")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 20)
                    .accessibilityIdentifier("stats.drilldownEmpty")
            }
            // The surrounding statistics scroll already uses a lazy stack. A second
            // lazy stack can repeatedly invalidate its height when a large-type
            // category filter changes. This page starts with only 20 records.
            VStack(spacing: 0) {
                ForEach(records.prefix(limit)) { transaction in
                    NavigationLink {
                        TransactionDetailView(transactionID: transaction.id)
                    } label: {
                        TransactionRow(t: transaction, showsDate: true)
                    }.buttonStyle(.plain).accessibilityIdentifier("stats.transaction.\(transaction.id.raw)")
                    Divider()
                }
                if records.count > limit {
                    Button("再显示 \(min(20, records.count - limit)) 条 · 还有 \(records.count - limit) 条") { limit += 20 }
                        .font(.subheadline).frame(maxWidth: .infinity, minHeight: 48).accessibilityIdentifier("stats.loadMore")
                }
            }
        }
        .onChange(of: kind) { _ in categoryID = nil; sort = .amount; limit = 20 }
        .onChange(of: categoryID) { _ in limit = 20 }
        .onChange(of: range) { _ in limit = 20 }
    }
    private var recordsToolbarLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
    }
    private var chartLayout: AnyLayout {
        typeSize.isAccessibilitySize || showAllCategories ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
    }
    private func rankingRow(_ item: BreakdownItem, rank: Int, total: Int64) -> some View {
        Button { categoryID = parentID == item.id ? nil : item.id } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle().fill(statsCategoryColor(item.id)).frame(width: 6, height: 6)
                    Text(item.name).font(.subheadline.weight(parentID == item.id ? .semibold : .regular)).lineLimit(1)
                    Spacer(minLength: 0)
                    if parentID == item.id { Image(systemName: "checkmark").font(.caption2.bold()) }
                }
                HStack(spacing: 4) {
                    Text(sort == .count ? "\(item.count) 笔" : statsMoney(sort == .refund ? item.refund : item.expense))
                        .font(.caption).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                    Spacer(minLength: 0)
                    if total > 0 { Text(String(format: "%.0f%%", Double(item.expense) * 100 / Double(total))).font(.caption2).foregroundStyle(.secondary) }
                }
            }.foregroundStyle(parentID == item.id ? Design.primary(scheme) : .primary)
                .padding(.horizontal, 8).padding(.vertical, 7).frame(minHeight: 48)
                .background(parentID == item.id ? Design.selectedFill(scheme) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("stats.category.\(item.id.raw)")
            .accessibilityLabel("第 \(rank) 名，\(item.name)，\(statsMoney(item.expense))，\(item.count) 笔，退款 \(statsMoney(item.refund))")
            .accessibilityAddTraits(parentID == item.id ? [.isSelected] : [])
    }
    private func filterChip(_ title: String, id: EntityID, prefix: String = "stats.filter") -> some View {
        Button { categoryID = id } label: {
            Text(title).font(.subheadline.weight(categoryID == id ? .semibold : .regular))
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(categoryID == id ? Design.selectedFill(scheme) : Color(.secondarySystemBackground), in: Capsule())
                .foregroundStyle(categoryID == id ? Design.primary(scheme) : .primary)
        }.buttonStyle(.plain).accessibilityAddTraits(categoryID == id ? [.isSelected] : [])
            .accessibilityIdentifier("\(prefix).\(id.raw)")
    }
    private var summary: some View {
        let values = records
        let gross = values.filter { $0.kind == kind }.reduce(Int64(0)) { $0 + $1.amountCents }
        let refund = values.filter { $0.kind == .refund }.reduce(Int64(0)) { $0 + $1.amountCents }
        let title = categoryID.map { state.store.categoryPath($0) } ?? "全部\(kind.displayName)"
        return VStack(alignment: .leading, spacing: 6) {
            recordsToolbarLayout {
                Text(title).font(.subheadline.weight(.medium))
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Text(statsMoney(gross)).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                    .foregroundStyle(Design.money(kind))
                    .lineLimit(1).minimumScaleFactor(0.5)
            }
            if kind == .expense && refund > 0 {
                Text("退款 \(statsMoney(refund)) · 净支出 \(statsMoney(gross - refund))").font(.caption).foregroundStyle(.secondary)
            }
            StatsRangeLabel(range: range)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title)，\(kind.displayName) \(statsMoney(gross))，\(values.count) 条流水，\(statsRangeText(range))" + (kind == .expense ? "，退款 \(statsMoney(refund))，净支出 \(statsMoney(gross - refund))" : ""))
            .accessibilityIdentifier("stats.detailSummary")
    }
}

private struct RingSegment: Shape {
    let start: Double
    let end: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2 - 15,
                 startAngle: .degrees(start * 360 - 90), endAngle: .degrees(end * 360 - 90), clockwise: false)
        return p.strokedPath(StrokeStyle(lineWidth: 25, lineCap: .butt))
    }
}
private struct DistributionRing: View {
    let rows: [BreakdownItem]
    let total: Int64
    @Binding var selected: EntityID?
    let kind: TransactionKind
    var body: some View {
        let chosen = rows.first { $0.id == selected }
        ZStack {
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                let start = Double(rows.prefix(index).reduce(Int64(0)) { $0 + $1.expense }) / Double(total)
                if row.expense > 0 {
                    RingSegment(start: start, end: start + Double(row.expense) / Double(total))
                        .fill(statsCategoryColor(row.id).opacity(selected == nil || selected == row.id ? 1 : 0.25))
                        .onTapGesture { selected = selected == row.id ? nil : row.id }
                        .accessibilityElement().accessibilityLabel("\(row.name)，\(statsMoney(row.expense))，占比 \(String(format: "%.1f", Double(row.expense) * 100 / Double(total))) 百分比")
                        .accessibilityAddTraits(.isButton).accessibilityAction { selected = row.id }
                        .accessibilityIdentifier("stats.slice.\(row.id.raw)")
                }
            }
            VStack(spacing: 5) {
                Text(chosen?.name ?? "合计").font(.caption).foregroundStyle(.secondary)
                Text(statsMoney(chosen?.expense ?? total)).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                    .foregroundStyle(Design.money(kind))
                if let chosen = chosen {
                    Text(String(format: "%.1f%%", Double(chosen.expense) * 100 / Double(total))).font(.caption)
                    Button("全部") { selected = nil }.font(.caption2).frame(minWidth: 44, minHeight: 32).accessibilityIdentifier("stats.clearSlice")
                } else { Text("点选联动明细").font(.caption2).foregroundStyle(.secondary) }
            }.frame(width: 106)
        }.frame(width: 156, height: 156)
    }
}
func statsCategoryColor(_ id: EntityID) -> Color {
    let hash = id.raw.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
    return Color(hue: Double(hash % 360) / 360, saturation: 0.48, brightness: 0.70)
}
