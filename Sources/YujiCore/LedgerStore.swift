import Foundation

/// 账本领域服务：持有全量数据并执行所有业务不变量。
/// 视图层不直接改数据，只调用这里的方法；所有变更在内存中完成后由 repository 原子落盘。
/// 规则来源：PRD §3–§7、§10。
public final class LedgerStore {
    public private(set) var data: LedgerData

    public init(data: LedgerData = LedgerData()) {
        self.data = data
    }

    // MARK: - 便捷查询

    public func ledger(_ id: EntityID) -> Ledger? { data.ledgers.first { $0.id == id } }
    public func account(_ id: EntityID?) -> Account? { id.flatMap { id in data.accounts.first { $0.id == id } } }
    public func category(_ id: EntityID?) -> CategoryNode? { id.flatMap { id in data.categories.first { $0.id == id } } }
    public func tag(_ id: EntityID?) -> TagNode? { id.flatMap { id in data.tags.first { $0.id == id } } }
    public func transaction(_ id: EntityID) -> Transaction? { data.transactions.first { $0.id == id } }

    public var activeLedger: Ledger? {
        if let id = data.activeLedgerID, let l = ledger(id) { return l }
        return data.ledgers.first { !$0.archived } ?? data.ledgers.first
    }

    public func accounts(in ledgerID: EntityID, includeArchived: Bool = true) -> [Account] {
        data.accounts
            .filter { $0.ledgerID == ledgerID && (includeArchived || !$0.archived) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    public func categories(in ledgerID: EntityID, kind: TransactionKind, includeArchived: Bool = true) -> [CategoryNode] {
        data.categories
            .filter { $0.ledgerID == ledgerID && $0.kind == kind && (includeArchived || !$0.archived) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    public func tags(in ledgerID: EntityID, includeArchived: Bool = true) -> [TagNode] {
        data.tags
            .filter { $0.ledgerID == ledgerID && (includeArchived || !$0.archived) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// 有效（未删除）交易。
    public func activeTransactions(in ledgerID: EntityID) -> [Transaction] {
        data.transactions.filter { $0.ledgerID == ledgerID && $0.isActive }
    }

    public func trashedTransactions(in ledgerID: EntityID) -> [Transaction] {
        data.transactions.filter { $0.ledgerID == ledgerID && !$0.isActive }
    }

    // MARK: - 账本 CRUD（US01/US02）

    @discardableResult
    public func createLedger(name: String) throws -> Ledger {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.nameEmpty }
        let order = (data.ledgers.map(\.sortOrder).max() ?? -1) + 1
        let ledger = Ledger(name: trimmed, sortOrder: order)
        data.ledgers.append(ledger)
        if data.activeLedgerID == nil { data.activeLedgerID = ledger.id }
        // 默认账户：现金、银行卡
        let today = Day(from: Date())
        data.accounts.append(Account(ledgerID: ledger.id, name: "现金", startDay: today, sortOrder: 0))
        data.accounts.append(Account(ledgerID: ledger.id, name: "银行卡", startDay: today, sortOrder: 1))
        seedDefaultCategoriesAndTags(ledgerID: ledger.id, today: today)
        return ledger
    }

    /// 默认两级分类/标签种子（只在新建账本时；不用于同步对端，PRD/arch：稳定键驱动）。
    private func seedDefaultCategoriesAndTags(ledgerID: EntityID, today: Day) {
        func addCategory(_ kind: TransactionKind, _ parent: String, _ children: [String]) {
            let p = CategoryNode(ledgerID: ledgerID, kind: kind, name: parent,
                                 sortOrder: data.categories.filter { $0.ledgerID == ledgerID }.count)
            data.categories.append(p)
            for (i, c) in children.enumerated() {
                data.categories.append(CategoryNode(ledgerID: ledgerID, kind: kind, parentID: p.id,
                                                    name: c, sortOrder: p.sortOrder + 1 + i))
            }
        }
        addCategory(.expense, "餐饮", ["早餐", "午餐晚餐", "咖啡茶饮", "零食"])
        addCategory(.expense, "出行", ["公共交通", "打车", "加油停车"])
        addCategory(.expense, "购物", ["日用百货", "服饰", "数码"])
        addCategory(.expense, "居家", ["房租水电", "家居用品"])
        addCategory(.expense, "娱乐", ["影音游戏", "运动健身"])
        addCategory(.expense, "医疗", ["门诊药品"])
        addCategory(.expense, "其他支出", ["未细分"])
        addCategory(.income, "工作收入", ["工资", "奖金"])
        addCategory(.income, "其他收入", ["理财收益", "未细分"])

        func addTag(_ parent: String, _ children: [String]) {
            let p = TagNode(ledgerID: ledgerID, name: parent,
                            sortOrder: data.tags.filter { $0.ledgerID == ledgerID }.count)
            data.tags.append(p)
            for (i, c) in children.enumerated() {
                data.tags.append(TagNode(ledgerID: ledgerID, parentID: p.id, name: c, sortOrder: p.sortOrder + 1 + i))
            }
        }
        addTag("对象", ["自己", "家人", "朋友"])
        addTag("场景", ["通勤", "居家", "聚会"])
        addTag("项目", ["未细分"])
    }

    public func renameLedger(_ id: EntityID, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.nameEmpty }
        guard let i = data.ledgers.firstIndex(where: { $0.id == id }) else { throw DomainError.notFound("账本") }
        data.ledgers[i].name = trimmed
    }

    public func archiveLedger(_ id: EntityID, archived: Bool) throws {
        guard let i = data.ledgers.firstIndex(where: { $0.id == id }) else { throw DomainError.notFound("账本") }
        data.ledgers[i].archived = archived
        // 归档当前账本时切到另一个可用账本
        if archived && data.activeLedgerID == id {
            data.activeLedgerID = data.ledgers.first { !$0.archived }?.id
        }
    }

    /// 仅真正空白（无任何流水，含回收站）且非唯一可用账本可删除（PRD §3.1/US01）。
    /// 种子账户/分类/标签随账本一并清除；被交易引用的账户只随「含流水」判定拦截。
    public func deleteLedger(_ id: EntityID) throws {
        guard let i = data.ledgers.firstIndex(where: { $0.id == id }) else { throw DomainError.notFound("账本") }
        let hasTxn = data.transactions.contains { $0.ledgerID == id }   // 含有效与已删
        if hasTxn { throw DomainError.ledgerHasDataCannotDelete }
        let activeCount = data.ledgers.filter { !$0.archived }.count
        if !data.ledgers[i].archived && activeCount <= 1 { throw DomainError.mustKeepOneLedger }
        // 级联清除该账本的种子账户/分类/标签/草稿（均无交易引用）
        data.accounts.removeAll { $0.ledgerID == id }
        data.categories.removeAll { $0.ledgerID == id }
        data.tags.removeAll { $0.ledgerID == id }
        data.drafts.removeAll { $0.ledgerID == id }
        data.ledgers.remove(at: i)
        if data.activeLedgerID == id { data.activeLedgerID = data.ledgers.first?.id }
    }

    public func switchLedger(_ id: EntityID) throws {
        guard ledger(id) != nil else { throw DomainError.notFound("账本") }
        data.activeLedgerID = id
    }

    // MARK: - 账户（US03/US04）

    @discardableResult
    public func createAccount(ledgerID: EntityID, name: String, openingBalanceCents: Int64 = 0,
                              startDay: Day? = nil) throws -> Account {
        guard ledger(ledgerID) != nil else { throw DomainError.notFound("账本") }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.nameEmpty }
        let acc = Account(ledgerID: ledgerID, name: trimmed, openingBalanceCents: openingBalanceCents,
                          startDay: startDay ?? Day(from: Date()),
                          sortOrder: data.accounts.filter { $0.ledgerID == ledgerID }.count)
        data.accounts.append(acc)
        return acc
    }

    public func updateAccountOpening(_ id: EntityID, openingCents: Int64, startDay: Day) throws {
        guard let i = data.accounts.firstIndex(where: { $0.id == id }) else { throw DomainError.notFound("账户") }
        // 流水不能早于起点：若收紧起点到已有交易之前则拒绝。
        let earliest = data.transactions
            .filter { $0.isActive && $0.date < startDay
                && ($0.accountID == id || $0.transferToAccountID == id) }
        if !earliest.isEmpty {
            throw DomainError.dateBeforeAccountStart("记账起点不能晚于已有流水日期")
        }
        data.accounts[i].openingBalanceCents = openingCents
        data.accounts[i].startDay = startDay
        data.accounts[i].updatedAt = Date()
    }

    public func archiveAccount(_ id: EntityID, archived: Bool) throws {
        guard let i = data.accounts.firstIndex(where: { $0.id == id }) else { throw DomainError.notFound("账户") }
        data.accounts[i].archived = archived
        data.accounts[i].updatedAt = Date()
    }

    public func renameAccount(_ id: EntityID, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.nameEmpty }
        guard let i = data.accounts.firstIndex(where: { $0.id == id }) else { throw DomainError.notFound("账户") }
        data.accounts[i].name = trimmed
        data.accounts[i].updatedAt = Date()
    }

    /// 无任何引用的空账户可删除（PRD §3.2）。
    public func deleteAccount(_ id: EntityID) throws {
        guard let i = data.accounts.firstIndex(where: { $0.id == id }) else { throw DomainError.notFound("账户") }
        let referenced = data.transactions.contains { t in
            t.accountID == id || t.transferToAccountID == id
        }
        if referenced { throw DomainError.accountReferencedCannotDelete }
        data.accounts.remove(at: i)
    }

    /// 当前余额 = 期初 + 收入 − 支出 + 退款 + 转入 − 转出（PRD §3.2）。期初/转账不进收支统计。
    public func balance(accountID: EntityID, upTo day: Day? = nil) -> Int64 {
        guard let acc = account(accountID) else { return 0 }
        var bal = acc.openingBalanceCents
        for t in data.transactions where t.isActive && t.date <= (day ?? Day(year: 9999, month: 12, day: 31)) {
            if t.kind == .income && t.accountID == accountID { bal += t.amountCents }
            else if t.kind == .expense && t.accountID == accountID { bal -= t.amountCents }
            else if t.kind == .refund && t.accountID == accountID { bal += t.amountCents }
            else if t.kind == .transfer {
                if t.accountID == accountID { bal -= t.amountCents }          // 转出
                if t.transferToAccountID == accountID { bal += t.amountCents } // 转入
            }
        }
        return bal
    }

    // MARK: - 分类 / 标签维护（US05/US06）

    @discardableResult
    public func createCategory(ledgerID: EntityID, kind: TransactionKind, parentID: EntityID?,
                               name: String) throws -> CategoryNode {
        guard ledger(ledgerID) != nil else { throw DomainError.notFound("账本") }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.nameEmpty }
        if kind != .expense && kind != .income { throw DomainError.categoryKindMismatch }
        if let pid = parentID {
            guard let p = category(pid) else { throw DomainError.parentNotFound }
            guard p.ledgerID == ledgerID && p.kind == kind && p.parentID == nil else {
                throw DomainError.invalidParent("分类分组无效")
            }
        }
        let node = CategoryNode(ledgerID: ledgerID, kind: kind, parentID: parentID, name: trimmed,
                                sortOrder: data.categories.filter { $0.ledgerID == ledgerID }.count)
        data.categories.append(node)
        return node
    }

    public func renameCategory(_ id: EntityID, name: String) throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw DomainError.nameEmpty }
        guard let i = data.categories.firstIndex(where: { $0.id == id }) else { throw DomainError.notFound("分类") }
        data.categories[i].name = name
    }

    public func archiveCategory(_ id: EntityID, archived: Bool) throws {
        guard let i = data.categories.firstIndex(where: { $0.id == id }) else { throw DomainError.notFound("分类") }
        data.categories[i].archived = archived
        // 归档一级连同下级
        if data.categories[i].parentID == nil {
            for j in data.categories.indices where data.categories[j].parentID == id {
                data.categories[j].archived = archived
            }
        }
    }

    public func deleteCategory(_ id: EntityID) throws {
        guard let i = data.categories.firstIndex(where: { $0.id == id }) else { throw DomainError.notFound("分类") }
        let referenced = data.transactions.contains { $0.categoryID == id }
        if referenced { throw DomainError.categoryReferencedCannotDelete }
        // 一级：连同未引用的叶子删除
        if data.categories[i].parentID == nil {
            let children = data.categories.filter { $0.parentID == id }
            for c in children where !data.transactions.contains(where: { $0.categoryID == c.id }) {
                data.categories.removeAll { $0.id == c.id }
            }
        }
        data.categories.remove(at: data.categories.firstIndex { $0.id == id }!)
    }

    @discardableResult
    public func createTag(ledgerID: EntityID, parentID: EntityID?, name: String) throws -> TagNode {
        guard ledger(ledgerID) != nil else { throw DomainError.notFound("账本") }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.nameEmpty }
        if let pid = parentID {
            guard let p = tag(pid) else { throw DomainError.parentNotFound }
            guard p.ledgerID == ledgerID && p.parentID == nil else { throw DomainError.invalidParent("标签分组无效") }
        }
        let node = TagNode(ledgerID: ledgerID, parentID: parentID, name: trimmed,
                           sortOrder: data.tags.filter { $0.ledgerID == ledgerID }.count)
        data.tags.append(node)
        return node
    }

    public func renameTag(_ id: EntityID, name: String) throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw DomainError.nameEmpty }
        guard let i = data.tags.firstIndex(where: { $0.id == id }) else { throw DomainError.notFound("标签") }
        data.tags[i].name = name
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
        guard let i = data.tags.firstIndex(where: { $0.id == id }) else { throw DomainError.notFound("标签") }
        let referenced = data.transactions.contains { $0.tagIDs.contains(id) }
        if referenced { throw DomainError.tagReferencedCannotDelete }
        if data.tags[i].parentID == nil {
            let children = data.tags.filter { $0.parentID == id }
            for c in children where !data.transactions.contains(where: { $0.tagIDs.contains(c.id) }) {
                data.tags.removeAll { $0.id == c.id }
            }
        }
        data.tags.remove(at: data.tags.firstIndex { $0.id == id }!)
    }

    // MARK: - 交易写入校验

    /// 校验一笔（新建或编辑后的）交易是否合法。返回归一化后的交易或抛错。
    /// `existing`：编辑时为原交易（用于退款额度、改类型等约束）。
    private func validate(_ t: Transaction, existing: Transaction?, operationID: String) throws {
        // 幂等：同一 operationID 已提交 → 拒绝重复（PRD §6.1）。
        if data.appliedOperations.contains(operationID) && existing?.operationID != operationID {
            throw DomainError.duplicateOperation
        }
        guard let ledger = ledger(t.ledgerID) else { throw DomainError.notFound("账本") }
        if ledger.archived { throw DomainError.archivedLedgerNoNewTransactions }

        // 金额：普通录入为正且在产品范围内。
        guard t.amountCents >= Money.minProductCents else {
            throw DomainError.invalidAmount("金额需大于 ¥0.00")
        }
        guard t.amountCents <= Money.maxProductCents else {
            throw DomainError.invalidAmount("金额超出上限 ¥999,999,999.99")
        }

        // 账户校验
        guard let acc = account(t.accountID), acc.ledgerID == t.ledgerID else {
            throw DomainError.accountNotFound
        }
        if acc.archived { throw DomainError.accountArchived }

        switch t.kind {
        case .expense, .income:
            // 分类必填、同账本、同收支类型、叶子、未归档
            guard let catID = t.categoryID else { throw DomainError.categoryRequired(t.kind == .expense ? "支出" : "收入") }
            guard let cat = category(catID) else { throw DomainError.categoryRequired("有效") }
            guard cat.ledgerID == t.ledgerID else { throw DomainError.ledgerMismatch("分类不属于当前账本") }
            guard cat.kind == t.kind else { throw DomainError.categoryKindMismatch }
            guard cat.parentID != nil else { throw DomainError.invalidParent("请选择具体的二级分类") }
            if cat.archived { throw DomainError.categoryArchived }
            // 标签必须同账本
            for tid in t.tagIDs {
                guard let tg = tag(tid), tg.ledgerID == t.ledgerID else {
                    throw DomainError.ledgerMismatch("标签不属于当前账本")
                }
            }
            // 发生日不早于账户起点
            if t.date < acc.startDay {
                throw DomainError.dateBeforeAccountStart("日期不能早于账户记账起点 \(acc.startDay.month)/\(acc.startDay.day)")
            }

        case .transfer:
            guard let toID = t.transferToAccountID else { throw DomainError.targetAccountUnavailable }
            guard toID != t.accountID else { throw DomainError.sameTransferAccount }
            guard let to = account(toID), to.ledgerID == t.ledgerID else { throw DomainError.targetAccountUnavailable }
            if to.archived { throw DomainError.accountArchived }
            if t.date < acc.startDay || t.date < to.startDay {
                throw DomainError.dateBeforeAccountStart("日期不能早于账户记账起点")
            }

        case .refund:
            guard let origID = t.originalExpenseID else { throw DomainError.refundRequiresOriginalExpense }
            guard let orig = transaction(origID) else { throw DomainError.refundRequiresOriginalExpense }
            guard orig.isActive else { throw DomainError.refundRequiresOriginalExpense }
            guard orig.kind == .expense else { throw DomainError.refundOriginalNotExpense }
            guard orig.ledgerID == t.ledgerID else { throw DomainError.ledgerMismatch("原支出不属于当前账本") }
            if t.date < orig.date { throw DomainError.refundDateBeforeOriginal }
            if t.date < acc.startDay {
                throw DomainError.dateBeforeAccountStart("日期不能早于账户记账起点")
            }
            // 累计有效退款（不含正在编辑的自身）不得超过原支出
            let refunded = totalRefunds(forExpense: origID, excluding: existing?.id)
            if refunded + t.amountCents > orig.amountCents {
                let remaining = orig.amountCents - refunded
                throw DomainError.refundExceedsRemaining("退款超出剩余可退额度（还可退 ¥\(Money(max(0,remaining)).yuanDescription)）")
            }
        }
    }

    /// 某原支出的有效退款合计（可排除某笔，用于编辑自身）。
    public func totalRefunds(forExpense expenseID: EntityID, excluding excludeID: EntityID? = nil) -> Int64 {
        data.transactions
            .filter { $0.isActive && $0.kind == .refund && $0.originalExpenseID == expenseID && $0.id != excludeID }
            .reduce(0) { $0 + $1.amountCents }
    }

    // MARK: - 创建 / 编辑交易（US07–US11, US19）

    @discardableResult
    public func addTransaction(_ t: Transaction) throws -> Transaction {
        try validate(t, existing: nil, operationID: t.operationID)
        var saved = t
        saved.revision = 1
        data.transactions.append(saved)
        data.appliedOperations.append(t.operationID)
        return saved
    }

    /// 编辑：一次保存更新全部影响；稳定 ID 不变；关联退款约束先检查，失败原交易不变（PRD §6.1/§5）。
    @discardableResult
    public func updateTransaction(_ id: EntityID, apply: (inout Transaction) -> Void) throws -> Transaction {
        guard let idx = data.transactions.firstIndex(where: { $0.id == id }) else {
            throw DomainError.notFound("记录")
        }
        let original = data.transactions[idx]
        var candidate = original
        apply(&candidate)
        // ledgerID 不可通过普通编辑改变（跨账本移动走专用关系组流程，PRD §6.4）。
        candidate.ledgerID = original.ledgerID
        candidate.id = original.id
        candidate.operationID = original.operationID
        candidate.revision = original.revision + 1
        candidate.updatedAt = Date()

        // 有退款的支出：不能改类型；减少金额不得低于已退总额；不能随意改账户。
        if original.kind == .expense {
            let refunds = totalRefunds(forExpense: original.id)
            if refunds > 0 {
                if candidate.kind != .expense { throw DomainError.expenseHasRefundsCannotChangeType }
                if candidate.amountCents < refunds { throw DomainError.expenseHasRefundsCannotChangeAmount }
                if candidate.accountID != original.accountID {
                    throw DomainError.ledgerMismatch("已有退款的支出不能更换付款账户")
                }
                if candidate.date > refundsLatestDate(expenseID: original.id) ?? candidate.date {
                    // 修改原日期不得使任何退款早于原支出
                }
                // 改日期不得晚于/导致退款早于原支出：新日期不得晚于最早退款日
                if let earliestRefund = earliestRefundDate(expenseID: original.id), candidate.date > earliestRefund {
                    throw DomainError.refundDateBeforeOriginal
                }
            }
        }
        // 转账不能通过只改一条分录变成支出（类型转换需显式且无关联）
        if original.kind == .transfer && candidate.kind != .transfer {
            throw DomainError.expenseHasRefundsCannotChangeType
        }

        try validate(candidate, existing: original, operationID: candidate.operationID)
        data.transactions[idx] = candidate
        return candidate
    }

    private func earliestRefundDate(expenseID: EntityID) -> Day? {
        data.transactions
            .filter { $0.isActive && $0.kind == .refund && $0.originalExpenseID == expenseID }
            .map(\.date).min()
    }
    private func refundsLatestDate(expenseID: EntityID) -> Day? {
        data.transactions
            .filter { $0.isActive && $0.kind == .refund && $0.originalExpenseID == expenseID }
            .map(\.date).max()
    }

    // MARK: - 删除 / 恢复（US21/US22）

    /// 逻辑删除。转账整体；有有效退款的支出拦截。
    public func deleteTransaction(_ id: EntityID) throws {
        guard let idx = data.transactions.firstIndex(where: { $0.id == id }) else {
            throw DomainError.notFound("记录")
        }
        let t = data.transactions[idx]
        if t.kind == .expense && totalRefunds(forExpense: t.id) > 0 {
            throw DomainError.expenseHasRefundsCannotDelete
        }
        data.transactions[idx].deletedAt = Date()
    }

    /// 撤销删除（短时撤销/回收站恢复共用）。恢复重新校验退款额度与引用（PRD §6.2）。
    public func restoreTransaction(_ id: EntityID) throws {
        guard let idx = data.transactions.firstIndex(where: { $0.id == id }) else {
            throw DomainError.notFound("回收站记录")
        }
        let t = data.transactions[idx]
        guard t.deletedAt != nil else { return } // 幂等：重复恢复只恢复一次

        // 引用对象仍存在且有效
        guard let acc = account(t.accountID) else { throw DomainError.restoreBlocked("付款账户已不存在") }
        if acc.archived { throw DomainError.restoreBlocked("账户「\(acc.name)」已归档，请先恢复账户") }
        if t.kind == .transfer {
            guard let toAcc = account(t.transferToAccountID) else { throw DomainError.restoreBlocked("转入账户已不存在") }
            if toAcc.archived { throw DomainError.restoreBlocked("转入账户已归档，请先恢复账户") }
            if t.date < acc.startDay || t.date < toAcc.startDay {
                throw DomainError.restoreBlocked("日期早于账户记账起点")
            }
        } else if t.date < acc.startDay {
            throw DomainError.restoreBlocked("日期早于账户记账起点，请先调整起点")
        }
        if (t.kind == .expense || t.kind == .income), category(t.categoryID) == nil {
            throw DomainError.restoreBlocked("分类已不存在")
        }
        if t.kind == .refund {
            guard let origID = t.originalExpenseID, let orig = transaction(origID), orig.isActive, orig.kind == .expense else {
                throw DomainError.restoreBlocked("原支出已删除或无效，请先恢复原支出")
            }
            if t.date < orig.date { throw DomainError.restoreBlocked("退款日期早于原支出") }
            let refunded = totalRefunds(forExpense: orig.id) // 不含自身（自身仍 deleted）
            if refunded + t.amountCents > orig.amountCents {
                throw DomainError.restoreBlocked("恢复后退款将超出原支出额度，请先处理其他退款")
            }
        }
        data.transactions[idx].deletedAt = nil
    }

    /// 物理删除（回收站“永久删除”，P0 仅在回收站二次确认）。
    public func purgeTransaction(_ id: EntityID) throws {
        guard let idx = data.transactions.firstIndex(where: { $0.id == id }) else {
            throw DomainError.notFound("记录")
        }
        data.transactions.remove(at: idx)
    }

    // MARK: - 批量操作（US23）：整批成功或整批不变

    public struct BatchChange {
        public var categoryID: EntityID?
        public var addTagIDs: [EntityID]
        public var removeTagIDs: [EntityID]
        public var delete: Bool
        public init(categoryID: EntityID? = nil, addTagIDs: [EntityID] = [],
                    removeTagIDs: [EntityID] = [], delete: Bool = false) {
            self.categoryID = categoryID; self.addTagIDs = addTagIDs
            self.removeTagIDs = removeTagIDs; self.delete = delete
        }
    }

    /// 预检：返回阻塞项描述。空数组表示可整批执行。所有操作必须在同一账本上下文内（PRD §3.1）。
    public func precheckBatch(ledgerID: EntityID, ids: [EntityID], change: BatchChange) -> [String] {
        var blockers: [String] = []
        // 目标对象先做统一校验
        if let catID = change.categoryID {
            if let cat = category(catID) {
                if cat.ledgerID != ledgerID { blockers.append("目标分类不属于当前账本") }
                if cat.parentID == nil { blockers.append("请选择具体的二级分类") }
            } else { blockers.append("目标分类不存在") }
        }
        for tid in change.addTagIDs {
            if let tg = tag(tid) {
                if tg.ledgerID != ledgerID { blockers.append("标签「\(tg.name)」不属于当前账本") }
                if tg.parentID == nil { blockers.append("请选择二级标签") }
                if tg.archived { blockers.append("标签「\(tg.name)」已归档") }
            } else { blockers.append("标签不存在") }
        }
        for id in ids {
            guard let t = transaction(id), t.isActive else { blockers.append("有记录不存在或已删除"); continue }
            if t.ledgerID != ledgerID { blockers.append("记录不属于当前账本"); continue }
            if change.delete {
                if t.kind == .expense && totalRefunds(forExpense: t.id) > 0 {
                    blockers.append("支出 \(t.money.yuanDescription) 有退款，需整组处理")
                }
            }
            if let catID = change.categoryID, (t.kind == .expense || t.kind == .income) {
                guard let cat = category(catID) else { blockers.append("目标分类不存在"); continue }
                if cat.kind != t.kind { blockers.append("分类与「\(t.money.yuanDescription)」类型不匹配") }
                if cat.archived { blockers.append("目标分类已归档") }
            }
        }
        return blockers
    }

    /// 执行批量：任一阻塞则整批不变。
    public func applyBatch(ledgerID: EntityID, ids: [EntityID], change: BatchChange) throws {
        let blockers = precheckBatch(ledgerID: ledgerID, ids: ids, change: change)
        if !blockers.isEmpty { throw DomainError.batchBlocked(blockers) }
        // 通过预检 → 整批应用
        for id in ids {
            guard let idx = data.transactions.firstIndex(where: { $0.id == id }) else { continue }
            if change.delete {
                data.transactions[idx].deletedAt = Date()
                continue
            }
            if let catID = change.categoryID, data.transactions[idx].kind == .expense
                || data.transactions[idx].kind == .income {
                data.transactions[idx].categoryID = catID
            }
            var tags = data.transactions[idx].tagIDs
            for add in change.addTagIDs where !tags.contains(add) { tags.append(add) }
            tags.removeAll { change.removeTagIDs.contains($0) }
            data.transactions[idx].tagIDs = tags
            data.transactions[idx].revision += 1
            data.transactions[idx].updatedAt = Date()
        }
    }

    // MARK: - 草稿（US20）

    public func saveDraft(_ draft: Draft) {
        data.drafts.removeAll { $0.ledgerID == draft.ledgerID }
        data.drafts.append(draft)
    }
    public func draft(for ledgerID: EntityID) -> Draft? { data.drafts.first { $0.ledgerID == ledgerID } }
    public func clearDraft(for ledgerID: EntityID) { data.drafts.removeAll { $0.ledgerID == ledgerID } }

    // MARK: - 设置

    public func updateSettings(_ apply: (inout AppSettings) -> Void) {
        apply(&data.settings)
    }
}
