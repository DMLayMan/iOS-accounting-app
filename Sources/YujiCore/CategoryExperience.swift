import Foundation

extension LedgerStore {
    public func categoryReferenceCount(_ id: EntityID) -> Int {
        let ids = Set(data.categories.filter { $0.id == id || $0.parentID == id }.map(\.id))
        return data.transactions.filter { $0.categoryID.map(ids.contains) ?? false }.count
            + data.drafts.filter { $0.categoryID.map(ids.contains) ?? false }.count
            + data.ledgers.flatMap { $0.budgetRules ?? [] }.filter { $0.categoryID.map(ids.contains) ?? false }.count
    }

    public func categoryPath(_ id: EntityID?) -> String {
        guard let node = category(id) else { return "选择分类" }
        return category(node.parentID).map { "\($0.name) · \(node.name)" } ?? node.name
    }

    public func effectiveCategory(for transaction: Transaction) -> CategoryNode? {
        if transaction.kind == .refund, let original = transaction.originalExpenseID.flatMap(self.transaction) {
            return category(original.categoryID)
        }
        return category(transaction.categoryID)
    }

    public func matchesCategory(_ transaction: Transaction, id: EntityID) -> Bool {
        guard let node = effectiveCategory(for: transaction) else { return false }
        return node.id == id || node.parentID == id
    }

    /// Notes are deliberately excluded: they are private annotations, not query dimensions.
    public func matchesCategoryQuery(_ transaction: Transaction, query: String) -> Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        guard let node = effectiveCategory(for: transaction) else { return false }
        return categoryPath(node.id).localizedCaseInsensitiveContains(text)
    }

    /// Local, deterministic ranking. No note/amount/location inference, no network, no future data.
    /// Daily frequency is capped at 3; a 14-day half-life favours recent habits over isolated edits.
    public func recommendedCategories(in ledgerID: EntityID, kind: TransactionKind,
                                      today: Day, limit: Int = 6) -> [CategoryNode] {
        let leaves = categories(in: ledgerID, kind: kind, includeArchived: false)
            .filter { $0.isLeaf && category($0.parentID)?.archived == false }
        let allowed = Set(leaves.map(\.id))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var daily: [EntityID: [Day: Int]] = [:]
        for t in activeTransactions(in: ledgerID) where t.kind == kind && t.date <= today {
            guard let id = t.categoryID, allowed.contains(id),
                  let age = calendar.dateComponents([.day], from: t.date.date(calendar: calendar), to: today.date(calendar: calendar)).day,
                  age >= 0 && age < 90 else { continue }
            daily[id, default: [:]][t.date, default: 0] += 1
        }
        let scores = daily.mapValues { days in
            // Sorting avoids dictionary iteration order affecting equal-score ranking.
            days.keys.sorted().reduce(0.0) { score, day in
                let age = calendar.dateComponents([.day], from: day.date(calendar: calendar), to: today.date(calendar: calendar)).day ?? 90
                return score + Double(min(3, days[day] ?? 0)) * pow(0.5, Double(age) / 14)
            }
        }
        return Array(leaves.sorted { a, b in
            if a.pinnedOrder != b.pinnedOrder { return (a.pinnedOrder ?? Int.max) < (b.pinnedOrder ?? Int.max) }
            let sa = scores[a.id] ?? 0, sb = scores[b.id] ?? 0
            if sa != sb { return sa > sb }
            if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
            return a.id.raw < b.id.raw
        }.prefix(max(0, limit)))
    }
}
