import Foundation

extension StatsEngine {
    public enum CategorySort: String, CaseIterable, Sendable {
        case amount = "金额", count = "笔数", refund = "退款"
    }

    /// Expense rows include refunds, on the refund date and original expense category.
    /// Income rows contain income only. Transfers never enter this exploration.
    public func categoryTransactions(range: ClosedRange<Day>, kind: TransactionKind,
                                     categoryID: EntityID? = nil) -> [Transaction] {
        guard kind == .expense || kind == .income else { return [] }
        return store.activeTransactions(in: ledgerID).filter { t in
            range.contains(t.date) && (t.kind == kind || (kind == .expense && t.kind == .refund)) &&
            (categoryID.map { store.matchesCategory(t, id: $0) } ?? true)
        }.sorted { a, b in
            if a.date != b.date { return a.date > b.date }
            if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
            return a.id.raw < b.id.raw
        }
    }

    /// Root -> parent groups; parent -> leaves. Archived categories remain in history.
    /// Gross expense / income is the nonnegative denominator used by distribution charts.
    public func categoryGroups(range: ClosedRange<Day>, kind: TransactionKind = .expense,
                               parentID: EntityID? = nil, sort: CategorySort = .amount) -> [BreakdownItem] {
        let leaves = categoryBreakdown(range: range, kind: kind)
        var groups: [EntityID: BreakdownItem] = [:]
        for leaf in leaves {
            let parent = store.category(leaf.id)?.parentID
            if let parentID = parentID {
                if parent == parentID { groups[leaf.id] = leaf }
            } else {
                let id = parent ?? leaf.id
                let name = store.category(id)?.name ?? leaf.name
                var row = groups[id] ?? BreakdownItem(id: id, name: name, pathName: name, expense: 0, refund: 0, count: 0)
                row.expense += leaf.expense; row.refund += leaf.refund; row.count += leaf.count
                groups[id] = row
            }
        }
        return groups.values.sorted { a, b in
            let av: Int64, bv: Int64
            switch sort {
            case .amount: av = a.expense; bv = b.expense
            case .count: av = Int64(a.count); bv = Int64(b.count)
            case .refund: av = a.refund; bv = b.refund
            }
            return av == bv ? a.id.raw < b.id.raw : av > bv
        }
    }

    public struct CategoryChange: Identifiable, Sendable {
        public var id: EntityID
        public var name: String
        public var current: Int64
        public var base: Int64
        public var delta: Int64 { current - base }
    }

    /// Signed contributions conserve the net-expense delta, including refund-only groups.
    public func categoryChanges(currentRange: ClosedRange<Day>, baseRange: ClosedRange<Day>) -> [CategoryChange] {
        let current = Dictionary(uniqueKeysWithValues: categoryGroups(range: currentRange).map { ($0.id, $0) })
        let base = Dictionary(uniqueKeysWithValues: categoryGroups(range: baseRange).map { ($0.id, $0) })
        return Set(current.keys).union(base.keys).map { id in
            CategoryChange(id: id, name: current[id]?.name ?? base[id]?.name ?? "未分类",
                           current: current[id]?.net ?? 0, base: base[id]?.net ?? 0)
        }.sorted { abs($0.delta) == abs($1.delta) ? $0.id.raw < $1.id.raw : abs($0.delta) > abs($1.delta) }
    }
}
