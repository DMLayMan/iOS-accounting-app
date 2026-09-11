import SwiftUI
import YujiCore

/// 时间固定在流水上方，周期与其他筛选取交集，返回单笔时保留条件。
struct FeedView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showSearch = false
    private var period: BrowsingPeriod { state.browsingPeriod }
    @State private var filter: TransactionFilter?
    @State private var listRevision = UUID()

    private var query: TransactionFilter {
        var value = filter ?? TransactionFilter()
        value.range = period.range(today: state.today)
        return value
    }
    var body: some View {
        NavigationStack {
            Group {
                if let ledger = state.activeLedger {
                    let records = state.store.transactions(in: ledger.id, matching: query)
                    recordList(records)
                        .safeAreaInset(edge: .top, spacing: 0) { timeControls(records) }
                } else { EmptyLedgerView() }
            }
            .navigationTitle("流水").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSearch = true } label: { Image(systemName: "magnifyingglass").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("搜索与筛选").accessibilityIdentifier("feed.search")
                }
            }
            .sheet(isPresented: $showSearch) {
                SearchFilterView(ledgerID: state.activeLedgerID ?? "", initial: filter) { value in
                    var cleaned = value
                    cleaned.range = nil
                    if cleaned.query?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { cleaned.query = nil }
                    filter = cleaned == TransactionFilter() ? nil : cleaned
                }
            }
            .onChange(of: period) { _ in listRevision = UUID() }
            .onChange(of: filter) { _ in listRevision = UUID() }
            .onChange(of: state.activeLedger?.id) { _ in filter = nil; listRevision = UUID() }
        }
    }
    private func timeControls(_ records: [YujiCore.Transaction]) -> some View {
        let totals = TransactionTotals(records)
        return VStack(alignment: .leading, spacing: 0) {
            PeriodNavigation(prefix: "feed")
            VStack(alignment: .leading, spacing: 6) {
                if case .custom(let range) = period, !typeSize.isAccessibilitySize {
                    Text(statsRangeText(range)).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("feed.customRange")
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if !typeSize.isAccessibilitySize {
                        (Text("净支出 \(statsMoney(totals.netExpense))").foregroundColor(Design.netExpense(totals.netExpense))
                         + Text(" · ").foregroundColor(.secondary)
                         + Text("收入 \(statsMoney(totals.income))").foregroundColor(Design.income))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("feed.totals")
                        Spacer(minLength: 0)
                    }
                    Text("\(records.count) 笔").font(.caption).foregroundStyle(.secondary)
                        .fixedSize().accessibilityIdentifier("feed.count")
                }
                if let filter {
                    HStack {
                        Text(filterDescription(filter)).font(.caption).lineLimit(2)
                        Spacer()
                        Button("清除筛选") { self.filter = nil }.font(.caption).frame(minHeight: 44).accessibilityIdentifier("feed.clearFilter")
                    }
                }
            }.padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 10)
        }.background(Color(.systemBackground))
            .overlay(alignment: .bottom) { Divider() }
    }
    @ViewBuilder private func recordList(_ records: [YujiCore.Transaction]) -> some View {
        if records.isEmpty {
            VStack(spacing: 12) {
                Text("这段时间没有符合条件的记录").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .accessibilityIdentifier("feed.empty")
                Button("查看全部流水") { filter = nil; state.browsingPeriod = .all }.frame(minHeight: 44).accessibilityIdentifier("feed.resetAll")
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
        } else {
            let groups = Dictionary(grouping: records, by: \.date)
            let days = groups.keys.sorted(by: >)
            List {
                ForEach(days, id: \.self) { day in
                    let items = groups[day] ?? []
                    Section {
                        ForEach(items) { transaction in
                            NavigationLink { TransactionDetailView(transactionID: transaction.id) } label: { TransactionRow(t: transaction) }
                                .accessibilityIdentifier("feed.transaction.\(transaction.id.raw)")
                        }
                    } header: {
                        HStack {
                            Text(statsDayText(day)).font(.caption)
                            Spacer()
                            if !typeSize.isAccessibilitySize {
                                Text("结余 \(statsMoney(TransactionTotals(items).surplus))").font(.caption)
                            }
                        }.textCase(nil).padding(.vertical, 5)
                    }
                }
            }.listStyle(.plain).id(listRevision).accessibilityIdentifier("feed.list")
        }
    }
    private func filterDescription(_ filter: TransactionFilter) -> String {
        var parts: [String] = []
        if let kind = filter.kind { parts.append(kind.displayName) }
        if let category = filter.categoryID { parts.append(state.store.categoryPath(category)) }
        if let query = filter.query, !query.isEmpty { parts.append(query) }
        return parts.joined(separator: " · ")
    }
}
