import SwiftUI
import YujiCore

/// P02 流水：按日分组、日合计、筛选、进入详情。
struct FeedView: View {
    @EnvironmentObject var state: AppState
    @State private var showSearch = false
    @State private var filter: TransactionFilter?

    var body: some View {
        NavigationStack {
            Group {
                if let ledger = state.activeLedger {
                    content(ledger: ledger)
                } else {
                    EmptyLedgerView()
                }
            }
            .navigationTitle("流水")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                }
            }
            .sheet(isPresented: $showSearch) {
                SearchFilterView(ledgerID: state.activeLedger?.id ?? EntityID("x"), applied: { f in filter = f })
            }
        }
    }

    @ViewBuilder
    private func content(ledger: Ledger) -> some View {
        let txns = filtered(ledgerID: ledger.id)
        if txns.isEmpty {
            QuietEmptyView(message: filter != nil ? "没有符合筛选的记录" : "还没有记录")
        } else {
            let groups = groupedByDay(txns)
            List {
                ForEach(groups.indices, id: \.self) { i in
                    let day = groups[i].0
                    let items = groups[i].1
                    Section {
                        ForEach(items) { t in
                            NavigationLink {
                                TransactionDetailView(transactionID: t.id)
                            } label: {
                                TransactionRow(t: t)
                            }
                        }
                    } header: {
                        HStack {
                            Text(dayText(day)).font(.system(size: Design.captionSize))
                            Spacer()
                            Text("净 ¥\(Money(dayNet(items)).yuanDescription)")
                                .font(.system(size: Design.captionSmall))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func filtered(ledgerID: EntityID) -> [Transaction] {
        var txns = state.store.activeTransactions(in: ledgerID)
        if let f = filter {
            txns = txns.filter { t in
                if let kind = f.kind, t.kind != kind { return false }
                if let acc = f.accountID, t.accountID != acc, t.transferToAccountID != acc { return false }
                if let cat = f.categoryID, t.categoryID != cat { return false }
                if !f.tagIDs.isEmpty {
                    let set = Set(t.tagIDs)
                    if f.tagMatchAll ? !Set(f.tagIDs).isSubset(of: set) : set.intersection(f.tagIDs).isEmpty { return false }
                }
                if let r = f.range, !r.contains(t.date) { return false }
                if let min = f.minCents, t.amountCents < min { return false }
                if let max = f.maxCents, t.amountCents > max { return false }
                if let q = f.query, !q.isEmpty {
                    let inNote = t.note.localizedCaseInsensitiveContains(q)
                    let inCat = (t.categoryID.flatMap { state.store.category($0)?.name.contains(q) }) ?? false
                    if !inNote && !inCat { return false }
                }
                return true
            }
        }
        return txns.sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
    }

    private func groupedByDay(_ txns: [Transaction]) -> [(Day, [Transaction])] {
        var dict: [Day: [Transaction]] = [:]
        for t in txns { dict[t.date, default: []].append(t) }
        return dict.sorted { $0.key > $1.key }.map { ($0.key, $0.value) }
    }
    private func dayText(_ d: Day) -> String { String(format: "%02d-%02d", d.month, d.day) }
    private func dayNet(_ items: [Transaction]) -> Int64 {
        items.reduce(0) { acc, t in
            switch t.kind {
            case .expense: return acc - t.amountCents
            case .income, .refund: return acc + t.amountCents
            case .transfer: return acc
            }
        }
    }
}

/// 筛选条件定义（搜索/批量/统计下钻共用同一口径，PRD §10）。
struct TransactionFilter: Equatable {
    var query: String?
    var kind: TransactionKind?
    var accountID: EntityID?
    var categoryID: EntityID?
    var tagIDs: [EntityID] = []
    var tagMatchAll: Bool = false
    var range: ClosedRange<Day>?
    var minCents: Int64?
    var maxCents: Int64?
}
