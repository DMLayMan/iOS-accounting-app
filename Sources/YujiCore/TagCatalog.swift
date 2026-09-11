import Foundation

extension LedgerStore {
    public func matchingTag(in ledgerID: EntityID, name: String) -> TagNode? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return tags(in: ledgerID).first {
            $0.isLeaf && $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(normalized, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    /// Quick creation uses the same IDs as management and historical transactions.
    @discardableResult
    public func createQuickTag(ledgerID: EntityID, name: String) throws -> TagNode {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.nameEmpty }
        if let existing = matchingTag(in: ledgerID, name: trimmed) {
            if let parent = tag(existing.parentID), parent.archived {
                try archiveTag(parent.id, archived: false)
            }
            try archiveTag(existing.id, archived: false)
            return tag(existing.id)!
        }
        let parent: TagNode
        if let existing = tags(in: ledgerID, includeArchived: false).first(where: { !$0.isLeaf && $0.name == "自定义" }) {
            parent = existing
        } else {
            parent = try createTag(ledgerID: ledgerID, parentID: nil, name: "自定义")
        }
        return try createTag(ledgerID: ledgerID, parentID: parent.id, name: trimmed)
    }

    public func suggestedTags(in ledgerID: EntityID, limit: Int = 6) -> [TagNode] {
        var recent: [EntityID: Date] = [:]
        for transaction in activeTransactions(in: ledgerID) {
            for id in transaction.tagIDs {
                recent[id] = max(recent[id] ?? .distantPast, transaction.updatedAt)
            }
        }
        return Array(tags(in: ledgerID, includeArchived: false)
            .filter { $0.isLeaf && tag($0.parentID)?.archived == false }
            .sorted {
                let lhs = recent[$0.id] ?? .distantPast, rhs = recent[$1.id] ?? .distantPast
                return lhs == rhs ? $0.sortOrder < $1.sortOrder : lhs > rhs
            }.prefix(max(0, limit)))
    }

    public func tagReferenceCount(_ id: EntityID) -> Int {
        data.transactions.filter { $0.tagIDs.contains(id) }.count
            + data.drafts.filter { $0.tagIDs.contains(id) }.count
    }
}
