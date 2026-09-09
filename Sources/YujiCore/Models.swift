import Foundation

// MARK: - 标识与时间

/// 稳定实体 ID。改名不改 ID；编辑不通过删除重建改变 ID（PRD §6.1）。
public struct EntityID: Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
    public init(stringLiteral value: String) { self.raw = value }
    public static func new() -> EntityID { EntityID(UUID().uuidString) }
}

/// 记账发生日（PRD §7.1：按发生期分组，旅行/系统时区变化不使历史流水跨日）。
/// 以账本日历的年月日存储，不存绝对时刻，避免时区漂移。
public struct Day: Hashable, Codable, Sendable, Comparable {
    public var year: Int
    public var month: Int   // 1...12
    public var day: Int     // 1...31

    public init(year: Int, month: Int, day: Int) {
        self.year = year; self.month = month; self.day = day
    }

    public static func < (l: Day, r: Day) -> Bool {
        if l.year != r.year { return l.year < r.year }
        if l.month != r.month { return l.month < r.month }
        return l.day < r.day
    }

    /// 月份键（同年月）。
    public var monthKey: MonthKey { MonthKey(year: year, month: month) }

    public var nextDay: Day {
        let cal = Calendar.current
        if let d = cal.date(from: DateComponents(year: year, month: month, day: day)),
           let n = cal.date(byAdding: .day, value: 1, to: d) {
            return Day(from: n, calendar: cal)
        }
        return self
    }

    /// 由 Date（按给定日历）取日。
    public init(from date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = c.year ?? 1970; self.month = c.month ?? 1; self.day = c.day ?? 1
    }

    public func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    /// 该月天数。
    public var daysInMonth: Int {
        let cal = Calendar.current
        let dc = DateComponents(year: year, month: month, day: 1)
        if let d = cal.date(from: dc),
           let range = cal.range(of: .day, in: .month, for: d) {
            return range.count
        }
        return 30
    }
}

/// 自然月键。
public struct MonthKey: Hashable, Codable, Sendable, Comparable {
    public var year: Int
    public var month: Int
    public init(year: Int, month: Int) { self.year = year; self.month = month }

    public static func < (l: MonthKey, r: MonthKey) -> Bool {
        l.year != r.year ? l.year < r.year : l.month < r.month
    }

    public var firstDay: Day { Day(year: year, month: month, day: 1) }
    /// 该月最后一天。
    public var lastDay: Day { Day(year: year, month: month, day: firstDay.daysInMonth) }

    /// 上一个自然月。
    public var previous: MonthKey {
        month == 1 ? MonthKey(year: year - 1, month: 12) : MonthKey(year: year, month: month - 1)
    }

    /// 下一个自然月。
    public var next: MonthKey {
        month == 12 ? MonthKey(year: year + 1, month: 1) : MonthKey(year: year, month: month + 1)
    }

    /// 区间：本月 1 日到第 d 日（用于当前月部分比较）。
    public func prefix(through d: Int) -> ClosedRange<Day> {
        let end = min(max(d, 1), firstDay.daysInMonth)
        return firstDay...Day(year: year, month: month, day: end)
    }

    /// 完整月区间。
    public var fullRange: ClosedRange<Day> { firstDay...lastDay }
}

// MARK: - 账本

public struct Ledger: Hashable, Codable, Identifiable, Sendable {
    public var id: EntityID
    public var name: String
    public var currencyCode: String       // 首版 "CNY"
    public var archived: Bool
    public var sortOrder: Int
    public var createdAt: Date

    public init(id: EntityID = .new(), name: String, currencyCode: String = "CNY",
                archived: Bool = false, sortOrder: Int = 0, createdAt: Date = Date()) {
        self.id = id; self.name = name; self.currencyCode = currencyCode
        self.archived = archived; self.sortOrder = sortOrder; self.createdAt = createdAt
    }
}

// MARK: - 账户

public struct Account: Hashable, Codable, Identifiable, Sendable {
    public var id: EntityID
    public var ledgerID: EntityID
    public var name: String
    /// 期初余额（分），可为负（PRD §3.2：允许负余额但标明非完整负债模型）。
    public var openingBalanceCents: Int64
    /// 记账起点：普通交易发生日不得早于此日。
    public var startDay: Day
    public var archived: Bool
    public var sortOrder: Int
    public var updatedAt: Date

    public init(id: EntityID = .new(), ledgerID: EntityID, name: String,
                openingBalanceCents: Int64 = 0, startDay: Day, archived: Bool = false,
                sortOrder: Int = 0, updatedAt: Date = Date()) {
        self.id = id; self.ledgerID = ledgerID; self.name = name
        self.openingBalanceCents = openingBalanceCents; self.startDay = startDay
        self.archived = archived; self.sortOrder = sortOrder; self.updatedAt = updatedAt
    }
}

// MARK: - 分类与标签节点

/// 收支维度。
public enum TransactionKind: String, Hashable, Codable, Sendable, CaseIterable {
    case expense
    case income
    case refund
    case transfer

    public var displayName: String {
        switch self {
        case .expense: return "支出"
        case .income: return "收入"
        case .refund: return "退款"
        case .transfer: return "转账"
        }
    }
    /// 是否进入统计的收支口径。退款单独计；转账、期初不进入。
    public var affectsFlow: Bool { self == .expense || self == .income || self == .refund }
}

/// 分类树（支出/收入各一棵）。两级：parentID == nil 为一级分组，否则为二级叶子。
public struct CategoryNode: Hashable, Codable, Identifiable, Sendable {
    public var id: EntityID
    public var ledgerID: EntityID
    public var kind: TransactionKind        // .expense 或 .income
    public var parentID: EntityID?          // nil = 一级
    public var name: String
    public var archived: Bool
    public var sortOrder: Int

    public init(id: EntityID = .new(), ledgerID: EntityID, kind: TransactionKind,
                parentID: EntityID? = nil, name: String, archived: Bool = false, sortOrder: Int = 0) {
        self.id = id; self.ledgerID = ledgerID; self.kind = kind; self.parentID = parentID
        self.name = name; self.archived = archived; self.sortOrder = sortOrder
    }

    public var isLeaf: Bool { parentID != nil }
}

/// 标签树（两级，跨收支类型）。
public struct TagNode: Hashable, Codable, Identifiable, Sendable {
    public var id: EntityID
    public var ledgerID: EntityID
    public var parentID: EntityID?
    public var name: String
    public var archived: Bool
    public var sortOrder: Int

    public init(id: EntityID = .new(), ledgerID: EntityID, parentID: EntityID? = nil,
                name: String, archived: Bool = false, sortOrder: Int = 0) {
        self.id = id; self.ledgerID = ledgerID; self.parentID = parentID
        self.name = name; self.archived = archived; self.sortOrder = sortOrder
    }

    public var isLeaf: Bool { parentID != nil }
}

// MARK: - 交易

/// 一笔交易。
/// - 支出/收入：kind、amountCents(正)、accountID、categoryID(叶子)、tagIDs。
/// - 转账：kind=.transfer，accountID=转出账户，transferToAccountID=转入账户；一次提交整体生效。
/// - 退款：kind=.refund，accountID=退款到账账户，amountCents(正)、originalExpenseID=原支出。
public struct Transaction: Hashable, Codable, Identifiable, Sendable {
    public var id: EntityID
    public var ledgerID: EntityID
    /// 幂等操作 ID：同一操作重试不重复记账（PRD §6.1 / 保存中断样本）。
    public var operationID: String
    public var revision: Int

    public var kind: TransactionKind
    /// 金额（分，正数）。方向由 kind 决定。
    public var amountCents: Int64
    /// 发生日（非创建时间）。
    public var date: Day

    /// 主账户：支出付款/收入收款/退款到账/转账转出。
    public var accountID: EntityID
    /// 转账转入账户（仅 transfer）。
    public var transferToAccountID: EntityID?
    /// 叶子分类（支出/收入必填；退款分类跟随原支出）。
    public var categoryID: EntityID?
    /// 二级标签（可多选、可跨组）。
    public var tagIDs: [EntityID]
    public var note: String
    /// 退款关联的原支出 ID（仅 refund）。
    public var originalExpenseID: EntityID?
    /// 录入时的原始表达式（可选审阅信息，不参与统计）。
    public var expression: String?

    public var createdAt: Date
    public var updatedAt: Date
    /// 逻辑删除时间；nil = 有效。回收站保留（PRD §6.2）。
    public var deletedAt: Date?

    public var isActive: Bool { deletedAt == nil }

    public var money: Money { Money(amountCents) }

    public init(id: EntityID = .new(), ledgerID: EntityID, operationID: String = UUID().uuidString,
                revision: Int = 1, kind: TransactionKind, amountCents: Int64, date: Day,
                accountID: EntityID, transferToAccountID: EntityID? = nil,
                categoryID: EntityID? = nil, tagIDs: [EntityID] = [], note: String = "",
                originalExpenseID: EntityID? = nil, expression: String? = nil,
                createdAt: Date = Date(), updatedAt: Date = Date(), deletedAt: Date? = nil) {
        self.id = id; self.ledgerID = ledgerID; self.operationID = operationID; self.revision = revision
        self.kind = kind; self.amountCents = amountCents; self.date = date
        self.accountID = accountID; self.transferToAccountID = transferToAccountID
        self.categoryID = categoryID; self.tagIDs = tagIDs; self.note = note
        self.originalExpenseID = originalExpenseID; self.expression = expression
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}

// MARK: - 草稿

/// 录入草稿（未保存不影响流水/余额/统计；PRD §6.1）。
public struct Draft: Hashable, Codable, Sendable {
    public var ledgerID: EntityID
    public var kind: TransactionKind
    public var expression: String        // 金额表达式原样保留
    public var date: Day
    public var accountID: EntityID?
    public var transferToAccountID: EntityID?
    public var categoryID: EntityID?
    public var tagIDs: [EntityID]
    public var note: String
    public var originalExpenseID: EntityID?
    public var updatedAt: Date

    public init(ledgerID: EntityID, kind: TransactionKind = .expense, expression: String = "",
                date: Day, accountID: EntityID? = nil, transferToAccountID: EntityID? = nil,
                categoryID: EntityID? = nil, tagIDs: [EntityID] = [], note: String = "",
                originalExpenseID: EntityID? = nil, updatedAt: Date = Date()) {
        self.ledgerID = ledgerID; self.kind = kind; self.expression = expression; self.date = date
        self.accountID = accountID; self.transferToAccountID = transferToAccountID
        self.categoryID = categoryID; self.tagIDs = tagIDs; self.note = note
        self.originalExpenseID = originalExpenseID; self.updatedAt = updatedAt
    }
}
