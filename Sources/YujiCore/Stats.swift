import Foundation

// MARK: - 期间汇总（PRD §7.1）

/// 一个期间的五项口径。单位：分。
public struct PeriodSummary: Equatable, Sendable {
    public let range: ClosedRange<Day>
    public var expense: Int64      // E(P) 消费
    public var refund: Int64       // R(P) 退款（发生期）
    public var netExpense: Int64   // N(P) = E − R，可为负
    public var income: Int64       // I(P)
    public var surplus: Int64      // S(P) = I − N
    // 转账与期初不计入以上五项。

    public init(range: ClosedRange<Day>, expense: Int64 = 0, refund: Int64 = 0, income: Int64 = 0) {
        self.range = range
        self.expense = expense; self.refund = refund; self.income = income
        self.netExpense = expense - refund
        self.surplus = income - (expense - refund)
    }
}

/// 维度分项（分类或标签）。
public struct BreakdownItem: Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var name: String        // 叶子/标签名
    public var pathName: String    // 完整路径
    public var expense: Int64      // 毛支出
    public var refund: Int64       // 归属该维度的退款
    public var net: Int64 { expense - refund }
    public var count: Int
}

/// 统计引擎。所有口径按交易发生日（PRD §7.1）。
public struct StatsEngine {
    let store: LedgerStore
    let ledgerID: EntityID

    public init(store: LedgerStore, ledgerID: EntityID) {
        self.store = store; self.ledgerID = ledgerID
    }

    /// 有效交易（未删除、未草稿）。
    private var active: [Transaction] { store.activeTransactions(in: ledgerID) }

    /// 共用收支聚合规则；分类分析中的退款归属由分类查询负责。
    public func summary(range: ClosedRange<Day>) -> PeriodSummary {
        let totals = TransactionTotals(active.filter { range.contains($0.date) })
        return PeriodSummary(range: range, expense: totals.expense, refund: totals.refund, income: totals.income)
    }

    /// 某自然月汇总。
    public func monthSummary(_ month: MonthKey) -> PeriodSummary {
        summary(range: month.fullRange)
    }

    // MARK: - 月度同比/环比（PRD §7.2）

    /// 比较结果。基期为零/负/未覆盖时不给百分比。
    public struct Comparison: Equatable, Sendable {
        public var current: Int64
        public var base: Int64
        public var delta: Int64          // C − B
        public var percent: Double?      // 仅 B > 0 时有值
        public var currentRange: ClosedRange<Day>? = nil
        public var baseRange: ClosedRange<Day>? = nil
        public var status: Status
        public enum Status: Equatable, Sendable {
            case ok
            case baseZero          // B=0
            case baseNegative      // B<0
            case baseNotCovered    // 基期无历史覆盖
            case unequalLength     // 月份天数不足，无法等长同期
        }
    }

    /// Earliest declared account start, including archived accounts. This is a lower bound,
    /// not a claim that the user has recorded every transaction since that date.
    public var recordingStart: Day? { store.accounts(in: ledgerID).map(\.startDay).min() }

    /// Current month compares equal progress; historical months compare full calendar months.
    public func momComparison(for month: MonthKey, today: Day) -> Comparison {
        monthComparison(month, base: month.previous, today: today)
    }

    public func yoyComparison(for month: MonthKey, today: Day) -> Comparison {
        monthComparison(month, base: MonthKey(year: month.year - 1, month: month.month), today: today)
    }

    private func monthComparison(_ month: MonthKey, base: MonthKey, today: Day) -> Comparison {
        guard month == today.monthKey else {
            return comparison(currentRange: month.fullRange, baseRange: base.fullRange)
        }
        let common = min(today.day, base.firstDay.daysInMonth)
        return comparison(currentRange: month.prefix(through: common), baseRange: base.prefix(through: common),
                          unequalLength: common < today.day)
    }

    public func comparison(currentRange: ClosedRange<Day>, baseRange: ClosedRange<Day>,
                           unequalLength: Bool = false) -> Comparison {
        let current = summary(range: currentRange).netExpense
        let base = summary(range: baseRange).netExpense
        let baseIsCovered = recordingStart.map { baseRange.lowerBound >= $0 } ?? false
        let status: Comparison.Status
        if !baseIsCovered { status = .baseNotCovered }
        else if unequalLength { status = .unequalLength }
        else if base == 0 { status = .baseZero }
        else if base < 0 { status = .baseNegative }
        else { status = .ok }
        return Comparison(current: current, base: base, delta: current - base,
                          percent: status == .ok ? Double(current - base) * 100 / Double(base) : nil,
                          currentRange: currentRange, baseRange: baseRange, status: status)
    }

    // MARK: - 年度（PRD §7.3）

    public struct YearSummary: Equatable, Sendable {
        public var year: Int
        public var isCurrentYear: Bool
        public var ytdRange: ClosedRange<Day>
        public var total: PeriodSummary          // YTD 或全年
        public var months: [MonthKey: PeriodSummary]
        /// 年度同比：YTD 对去年同期（共同月日窗口）。
        public var yoy: Comparison
    }

    public func yearSummary(_ year: Int, today: Day) -> YearSummary {
        let isCurrent = year == today.year
        let endDay: Day = isCurrent ? today : Day(year: year, month: 12, day: 31)
        let range = Day(year: year, month: 1, day: 1)...endDay
        let total = summary(range: range)

        var months: [MonthKey: PeriodSummary] = [:]
        for m in 1...12 {
            let mk = MonthKey(year: year, month: m)
            if isCurrent && m > today.month { break }
            // 当前年的当前月取到 today；其余取整月
            if isCurrent && m == today.month {
                months[mk] = summary(range: mk.prefix(through: today.day))
            } else if !isCurrent || m < today.month {
                months[mk] = monthSummary(mk)
            }
        }

        // 年度同比 YTD：去年 01-01 到去年同月日。闰年：若今天是 02-29 而去年非闰年，
        // 比较双方用 01-01–02-28 共同窗口（该年 02-29 仍保留在主 YTD 总额中，PRD §7.3）。
        var yoy: Comparison
        if isCurrent {
            let isLeapDay = (today.month == 2 && today.day == 29)
            let commonDay = isLeapDay ? 28 : today.day
            let curCompareRange = Day(year: year, month: 1, day: 1)...Day(year: year, month: today.month, day: commonDay)
            let lastYearEnd = Day(year: year - 1, month: today.month, day: commonDay)
            let lyRange = Day(year: year - 1, month: 1, day: 1)...lastYearEnd
            yoy = comparison(currentRange: curCompareRange, baseRange: lyRange)
        } else {
            let lyRange = Day(year: year - 1, month: 1, day: 1)...Day(year: year - 1, month: 12, day: 31)
            yoy = comparison(currentRange: range, baseRange: lyRange)
        }

        return YearSummary(year: year, isCurrentYear: isCurrent, ytdRange: range,
                           total: total, months: months, yoy: yoy)
    }

    // MARK: - 分类分析（PRD §7.5：叶子互斥，一级=叶子并集，守恒）

    /// 按叶子分类分项。退款归属原支出的分类（PRD §7.1：月分类退款分析取原支出维度，金额发生期为退款日）。
    public func categoryBreakdown(range: ClosedRange<Day>, kind: TransactionKind = .expense) -> [BreakdownItem] {
        var byLeaf: [EntityID: (exp: Int64, ref: Int64, count: Int)] = [:]

        for t in active where range.contains(t.date) {
            if t.kind == kind, let catID = t.categoryID {
                var e = byLeaf[catID] ?? (0, 0, 0)
                e.exp += t.amountCents; e.count += 1
                byLeaf[catID] = e
            }
            if kind == .expense, t.kind == .refund, let origID = t.originalExpenseID, let orig = store.transaction(origID),
               orig.kind == .expense, let catID = orig.categoryID {
                // 退款按发生期计入，但归属原支出分类
                if range.contains(t.date) {
                    var e = byLeaf[catID] ?? (0, 0, 0)
                    e.ref += t.amountCents
                    byLeaf[catID] = e
                }
            }
        }

        return byLeaf.map { (id, v) in
            let cat = store.category(id)
            let parent = cat.flatMap { store.category($0.parentID) }
            let name = cat?.name ?? "未分类"
            let path = parent.map { "\($0.name) · \(name)" } ?? name
            return BreakdownItem(id: id, name: name, pathName: path,
                                 expense: v.exp, refund: v.ref, count: v.count)
        }
        .sorted { $0.net == $1.net ? $0.id.raw < $1.id.raw : $0.net > $1.net }
    }

    // MARK: - 标签分析（PRD §7.5/§4：按交易 ID 去重，父标签=后代并集，重叠不相加）

    /// 按二级标签分项。一笔交易多标签时出现在多个标签下；父标签金额为后代命中交易 ID 并集（去重）。
    public func tagBreakdown(range: ClosedRange<Day>) -> [BreakdownItem] {
        // 收集区间内支出与退款（退款归属原支出标签）
        func tagsAndAmount(for t: Transaction) -> (tags: [EntityID], exp: Int64, ref: Int64) {
            switch t.kind {
            case .expense:
                return (t.tagIDs, t.amountCents, 0)
            case .refund:
                // 归属原支出标签
                if let origID = t.originalExpenseID, let orig = store.transaction(origID), orig.kind == .expense {
                    return (orig.tagIDs, 0, t.amountCents)
                }
                return ([], 0, t.amountCents)
            default:
                return ([], 0, 0)
            }
        }

        // 按标签聚合净额需要"交易去重"：同一标签下同一交易只计一次（退款按退款交易 ID）。
        // 支出按支出交易 ID 去重；退款按退款交易 ID 去重。
        var expByTag: [EntityID: [EntityID: Int64]] = [:]   // tag -> txnID -> amount
        var refByTag: [EntityID: [EntityID: Int64]] = [:]
        var countByTag: [EntityID: Int] = [:]

        for t in active where range.contains(t.date) {
            let (tags, exp, ref) = tagsAndAmount(for: t)
            for tagID in Set(tags) {  // 一笔交易内同标签去重
                if exp != 0 {
                    expByTag[tagID, default: [:]][t.id] = exp
                    countByTag[tagID, default: 0] += 1
                }
                if ref != 0 {
                    refByTag[tagID, default: [:]][t.id] = ref
                }
            }
        }

        // 叶子标签分项
        let leafTags = store.tags(in: ledgerID).filter { $0.parentID != nil }
        return leafTags.map { tag in
            let exp = expByTag[tag.id]?.values.reduce(0, +) ?? 0
            let ref = refByTag[tag.id]?.values.reduce(0, +) ?? 0
            let parent = store.tag(tag.parentID)
            let path = parent.map { "\($0.name) · \(tag.name)" } ?? tag.name
            return BreakdownItem(id: tag.id, name: tag.name, pathName: path,
                                 expense: exp, refund: ref, count: countByTag[tag.id] ?? 0)
        }
        .filter { $0.expense > 0 || $0.refund > 0 }
        .sorted { $0.net > $1.net }
    }

    /// 一级（父）标签汇总：后代标签命中的交易 ID 并集去重（PRD §7.5）。
    public func parentTagNet(parentID: EntityID, range: ClosedRange<Day>) -> Int64 {
        let childIDs = Set(store.tags(in: ledgerID).filter { $0.parentID == parentID }.map(\.id))
        var expTxns: [EntityID: Int64] = [:]
        var refTxns: [EntityID: Int64] = [:]
        for t in active where range.contains(t.date) {
            if t.kind == .expense, !Set(t.tagIDs).intersection(childIDs).isEmpty {
                expTxns[t.id] = t.amountCents
            }
            if t.kind == .refund, let origID = t.originalExpenseID, let orig = store.transaction(origID),
               !Set(orig.tagIDs).intersection(childIDs).isEmpty {
                refTxns[t.id] = t.amountCents
            }
        }
        return expTxns.values.reduce(0, +) - refTxns.values.reduce(0, +)
    }

    /// 标签筛选：任一/全部（PRD §4 规则 5）。返回命中交易集合。
    public func transactions(matchingAnyTag tagIDs: Set<EntityID>, range: ClosedRange<Day>? = nil) -> [Transaction] {
        active.filter { t in
            if let r = range, !r.contains(t.date) { return false }
            return (t.kind == .expense || t.kind == .income) && !Set(t.tagIDs).intersection(tagIDs).isEmpty
        }
    }
    public func transactions(matchingAllTag tagIDs: Set<EntityID>, range: ClosedRange<Day>? = nil) -> [Transaction] {
        active.filter { t in
            if let r = range, !r.contains(t.date) { return false }
            return (t.kind == .expense || t.kind == .income) && tagIDs.isSubset(of: Set(t.tagIDs))
        }
    }
}
