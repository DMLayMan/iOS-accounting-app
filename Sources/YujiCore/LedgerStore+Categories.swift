import Foundation

extension LedgerStore {
    // MARK: - 分类 / 标签维护（US05/US06）

    @discardableResult
    public func createCategory(ledgerID: EntityID, kind: TransactionKind, parentID: EntityID?,
                               name: String) throws -> CategoryNode {
        guard ledger(ledgerID) != nil else { throw DomainError.notFound("账本") }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.nameEmpty }
        if kind != .expense && kind != .income { throw DomainError.categoryKindMismatch }
        try validateCategoryName(trimmed, ledgerID: ledgerID, kind: kind, parentID: parentID)
        if let pid = parentID {
            guard let p = category(pid) else { throw DomainError.parentNotFound }
            guard p.ledgerID == ledgerID && p.kind == kind && p.parentID == nil else {
                throw DomainError.invalidParent("分类分组无效")
            }
            guard !p.archived else { throw DomainError.categoryArchived }
        }
        let node = CategoryNode(ledgerID: ledgerID, kind: kind, parentID: parentID, name: trimmed,
                                sortOrder: data.categories.filter { $0.ledgerID == ledgerID }.count)
        data.categories.append(node)
        return node
    }

    /// Accept a complete permutation of visible siblings; validate everything before writing.
    /// Sorting never changes identity, hierarchy, transaction references, or other ledgers.
    public func reorderCategories(ledgerID: EntityID, kind: TransactionKind,
                                  parentID: EntityID?, orderedIDs: [EntityID]) throws {
        guard ledger(ledgerID) != nil else { throw DomainError.notFound("账本") }
        guard kind == .expense || kind == .income else { throw DomainError.categoryKindMismatch }
        if let parentID {
            guard let parent = category(parentID), parent.ledgerID == ledgerID,
                  parent.kind == kind, !parent.isLeaf else { throw DomainError.invalidParent("分类分组无效") }
            guard !parent.archived else { throw DomainError.categoryArchived }
        }
        let siblings = categories(in: ledgerID, kind: kind, includeArchived: false)
            .filter { $0.parentID == parentID }
        guard orderedIDs.count == siblings.count, Set(orderedIDs).count == orderedIDs.count,
              Set(orderedIDs) == Set(siblings.map(\.id)) else {
            throw DomainError.invalidParent("分类列表已变化，请重新调整顺序")
        }
        let ranks = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { ($0.element, $0.offset) })
        for index in data.categories.indices {
            if let rank = ranks[data.categories[index].id] { data.categories[index].sortOrder = rank }
        }
    }

    public func renameCategory(_ id: EntityID, name: String) throws {
        guard let node = category(id) else { throw DomainError.notFound("分类") }
        try editCategory(id, name: name, parentID: node.parentID)
    }

    public func setCategorySymbol(_ id: EntityID, symbolName: String?) throws {
        guard let i = data.categories.firstIndex(where: { $0.id == id }) else { throw DomainError.notFound("分类") }
        guard symbolName == nil || CategoryIcon.all.contains(where: { $0.id == symbolName }) else {
            throw DomainError.invalidParent("请选择列表中的分类图标")
        }
        data.categories[i].symbolName = symbolName
    }

    public func editCategory(_ id: EntityID, name: String, parentID: EntityID?) throws {
        guard let i = data.categories.firstIndex(where: { $0.id == id }) else { throw DomainError.notFound("分类") }
        let node = data.categories[i]
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard node.isLeaf == (parentID != nil) else { throw DomainError.invalidParent("一级分组与二级分类不能互相转换") }
        if let pid = parentID {
            guard let parent = category(pid), !parent.isLeaf, parent.ledgerID == node.ledgerID,
                  parent.kind == node.kind else { throw DomainError.invalidParent("请选择同一账本、同一收支类型的一级分组") }
            if parent.archived && pid != node.parentID { throw DomainError.categoryArchived }
        }
        try validateCategoryName(trimmed, ledgerID: node.ledgerID, kind: node.kind, parentID: parentID, excluding: id)
        data.categories[i].name = trimmed
        data.categories[i].parentID = parentID
    }

    private func validateCategoryName(_ name: String, ledgerID: EntityID, kind: TransactionKind,
                                      parentID: EntityID?, excluding id: EntityID? = nil) throws {
        guard !name.isEmpty else { throw DomainError.nameEmpty }
        if data.categories.contains(where: { $0.id != id && $0.ledgerID == ledgerID && $0.kind == kind &&
            $0.parentID == parentID && $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            throw DomainError.duplicateCategoryName
        }
    }

    public func setCategoryPinned(_ id: EntityID, pinned: Bool) throws {
        guard let i = data.categories.firstIndex(where: { $0.id == id }), data.categories[i].isLeaf else {
            throw DomainError.notFound("二级分类")
        }
        let node = data.categories[i]
        guard !pinned || (!node.archived && category(node.parentID)?.archived == false) else { throw DomainError.categoryArchived }
        let pins = categories(in: node.ledgerID, kind: node.kind).filter { $0.pinnedOrder != nil && $0.id != id }
        guard !pinned || pins.count < 4 else { throw DomainError.categoryPinLimit }
        data.categories[i].pinnedOrder = pinned ? (node.pinnedOrder ?? ((pins.compactMap(\.pinnedOrder).max() ?? -1) + 1)) : nil
    }

    public func archiveCategory(_ id: EntityID, archived: Bool) throws {
        guard let i = data.categories.firstIndex(where: { $0.id == id }) else { throw DomainError.notFound("分类") }
        if !archived, let pid = data.categories[i].parentID, category(pid)?.archived == true {
            throw DomainError.invalidParent("请先恢复所属一级分组")
        }
        data.categories[i].archived = archived
        if archived { data.categories[i].pinnedOrder = nil }
        // 归档一级连同下级
        if data.categories[i].parentID == nil {
            for j in data.categories.indices where data.categories[j].parentID == id {
                data.categories[j].archived = archived
                if archived { data.categories[j].pinnedOrder = nil }
            }
        }
    }

    public func deleteCategory(_ id: EntityID) throws {
        guard category(id) != nil else { throw DomainError.notFound("分类") }
        guard categoryReferenceCount(id) == 0 else { throw DomainError.categoryReferencedCannotDelete }
        data.categories.removeAll { $0.id == id || $0.parentID == id }
    }

    @discardableResult
    public func createTag(ledgerID: EntityID, parentID: EntityID?, name: String) throws -> TagNode {
        guard ledger(ledgerID) != nil else { throw DomainError.notFound("账本") }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.nameEmpty }
        if let pid = parentID {
            guard let p = tag(pid) else { throw DomainError.parentNotFound }
            guard p.ledgerID == ledgerID && p.parentID == nil else { throw DomainError.invalidParent("标签分组无效") }
            guard matchingTag(in: ledgerID, name: trimmed) == nil else { throw DomainError.duplicateTagName }
        }
        let node = TagNode(ledgerID: ledgerID, parentID: parentID, name: trimmed,
                           sortOrder: data.tags.filter { $0.ledgerID == ledgerID }.count)
        data.tags.append(node)
        return node
    }

    public func renameTag(_ id: EntityID, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.nameEmpty }
        guard let i = data.tags.firstIndex(where: { $0.id == id }) else { throw DomainError.notFound("标签") }
        if data.tags[i].isLeaf, let existing = matchingTag(in: data.tags[i].ledgerID, name: trimmed), existing.id != id {
            throw DomainError.duplicateTagName
        }
        data.tags[i].name = trimmed
    }

    public func archiveTag(_ id: EntityID, archived: Bool) throws {
        guard let i = data.tags.firstIndex(where: { $0.id == id }) else { throw DomainError.notFound("标签") }
        data.tags[i].archived = archived
        if data.tags[i].parentID == nil {
            for j in data.tags.indices where data.tags[j].parentID == id {
                data.tags[j].archived = archived
            }
        }
    }

    public func deleteTag(_ id: EntityID) throws {
        guard tag(id) != nil else { throw DomainError.notFound("标签") }
        let ids = Set([id] + data.tags.filter { $0.parentID == id }.map(\.id))
        let referenced = data.transactions.contains { !ids.isDisjoint(with: $0.tagIDs) }
            || data.drafts.contains { !ids.isDisjoint(with: $0.tagIDs) }
        if referenced { throw DomainError.tagReferencedCannotDelete }
        data.tags.removeAll { ids.contains($0.id) }
    }

}
