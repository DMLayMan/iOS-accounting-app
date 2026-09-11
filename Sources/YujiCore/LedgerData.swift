import Foundation

/// 领域错误：全部面向用户可解释（PRD §11/§6：清楚的错误、阻塞项可见）。
public enum DomainError: Swift.Error, Equatable {
    case notFound(String)
    case ledgerMismatch(String)
    case mustKeepOneLedger
    case ledgerHasDataCannotDelete
    case accountReferencedCannotDelete
    case categoryReferencedCannotDelete
    case tagReferencedCannotDelete
    case categoryRequired(String)
    case categoryKindMismatch
    case categoryArchived
    case accountArchived
    case accountNotFound
    case sameTransferAccount
    case invalidAmount(String)
    case dateBeforeAccountStart(String)
    case refundRequiresOriginalExpense
    case refundOriginalNotExpense
    case refundExceedsRemaining(String)        // 超过剩余可退额度
    case refundDateBeforeOriginal
    case expenseHasRefundsCannotDelete
    case expenseHasRefundsCannotChangeAmount
    case expenseHasRefundsCannotChangeType
    case targetAccountUnavailable
    case duplicateOperation
    case archivedLedgerNoNewTransactions
    case nodeArchivedCannotUse
    case parentNotFound
    case invalidParent(String)
    case nameEmpty
    case duplicateTagName
    case duplicateCategoryName
    case categoryPinLimit
    case batchBlocked([String])
    case crossLedgerGroupIncomplete(String)
    case restoreBlocked(String)

    public var message: String {
        switch self {
        case .notFound(let o): return "找不到\(o)"
        case .ledgerMismatch(let m): return m
        case .mustKeepOneLedger: return "至少保留一个可用账本"
        case .ledgerHasDataCannotDelete: return "该账本含数据，只能归档，不能直接删除"
        case .accountReferencedCannotDelete: return "该账户已有流水，请改用归档"
        case .categoryReferencedCannotDelete: return "该分类已被使用，请改用归档或迁移引用"
        case .tagReferencedCannotDelete: return "该标签已被使用，请改用归档或迁移引用"
        case .categoryRequired(let k): return "请选择\(k)分类"
        case .categoryKindMismatch: return "分类与收支类型不匹配"
        case .categoryArchived: return "所选分类已归档，请重新选择"
        case .accountArchived: return "所选账户已归档，请重新选择"
        case .accountNotFound: return "请选择账户"
        case .sameTransferAccount: return "转出和转入账户不能相同"
        case .invalidAmount(let m): return m
        case .dateBeforeAccountStart(let m): return m
        case .refundRequiresOriginalExpense: return "退款必须关联一笔原支出"
        case .refundOriginalNotExpense: return "退款只能关联支出记录"
        case .refundExceedsRemaining(let m): return m
        case .refundDateBeforeOriginal: return "退款日期不能早于原支出日期"
        case .expenseHasRefundsCannotDelete: return "该支出已有退款，请先处理退款再删除"
        case .expenseHasRefundsCannotChangeAmount: return "该支出已有退款，减少后的金额不能低于已退总额"
        case .expenseHasRefundsCannotChangeType: return "该支出已有退款，不能直接改为其他类型"
        case .targetAccountUnavailable: return "目标账户不可用"
        case .duplicateOperation: return "该操作已处理，请勿重复保存"
        case .archivedLedgerNoNewTransactions: return "账本已归档，不能新增记录"
        case .nodeArchivedCannotUse: return "该节点已归档，不能用于新记录"
        case .parentNotFound: return "找不到所属分组"
        case .invalidParent(let m): return m
        case .nameEmpty: return "名称不能为空"
        case .duplicateTagName: return "已有同名标签，请选择现有标签"
        case .duplicateCategoryName: return "同一分组已有同名分类，请使用现有分类"
        case .categoryPinLimit: return "最多置顶 4 个分类，请先取消一个置顶"
        case .batchBlocked(let items): return "有 \(items.count) 项无法处理，整批未更改：\(items.joined(separator: "；"))"
        case .crossLedgerGroupIncomplete(let m): return m
        case .restoreBlocked(let m): return m
        }
    }
}

/// 全量数据快照（用于持久化与备份恢复；PRD §10）。
public struct LedgerData: Codable, Sendable {
    public var schemaVersion: Int
    public var ledgers: [Ledger]
    public var accounts: [Account]
    public var categories: [CategoryNode]
    public var tags: [TagNode]
    public var transactions: [Transaction]
    public var drafts: [Draft]                 // 每个账本至多一个活动草稿
    public var activeLedgerID: EntityID?
    public var settings: AppSettings
    /// 幂等去重：已提交的 operationID（PRD §6.1 防重复保存）。
    public var appliedOperations: [String]
    public var lastBackupAt: Date?
    public var lastRestoreVerifiedAt: Date?
    /// Local recovery-point pointer committed atomically with a successful restore.
    public var recoveryBackupID: String?

    public static let currentSchemaVersion = 3

    public init(schemaVersion: Int = currentSchemaVersion,
                ledgers: [Ledger] = [], accounts: [Account] = [],
                categories: [CategoryNode] = [], tags: [TagNode] = [],
                transactions: [Transaction] = [], drafts: [Draft] = [],
                activeLedgerID: EntityID? = nil, settings: AppSettings = AppSettings(),
                appliedOperations: [String] = [], lastBackupAt: Date? = nil,
                lastRestoreVerifiedAt: Date? = nil) {
        self.schemaVersion = schemaVersion
        self.ledgers = ledgers; self.accounts = accounts
        self.categories = categories; self.tags = tags
        self.transactions = transactions; self.drafts = drafts
        self.activeLedgerID = activeLedgerID; self.settings = settings
        self.appliedOperations = appliedOperations
        self.lastBackupAt = lastBackupAt; self.lastRestoreVerifiedAt = lastRestoreVerifiedAt
    }
}

public struct AppSettings: Codable, Sendable {
    public var hapticsEnabled: Bool
    public var reduceMotion: Bool
    public var appearance: AppearanceMode      // 由系统深浅色派生；这里记录偏好
    public var icloudEnabled: Bool             // P1，默认关；开启前不影响 P0
    public var accentTheme: AccentTheme
    public var customAccentRGB: Int
    public init(hapticsEnabled: Bool = true, reduceMotion: Bool = false,
                appearance: AppearanceMode = .system, icloudEnabled: Bool = false,
                accentTheme: AccentTheme = .sage, customAccentRGB: Int = 0x367961) {
        self.hapticsEnabled = hapticsEnabled; self.reduceMotion = reduceMotion
        self.appearance = appearance; self.icloudEnabled = icloudEnabled
        self.accentTheme = accentTheme
        self.customAccentRGB = (0...0xFFFFFF).contains(customAccentRGB) ? customAccentRGB : 0x367961
    }

    private enum CodingKeys: String, CodingKey {
        case hapticsEnabled, reduceMotion, appearance, icloudEnabled, accentTheme, customAccentRGB
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(hapticsEnabled: try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true,
                  reduceMotion: try c.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? false,
                  appearance: try c.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? .system,
                  icloudEnabled: try c.decodeIfPresent(Bool.self, forKey: .icloudEnabled) ?? false,
                  accentTheme: (try c.decodeIfPresent(String.self, forKey: .accentTheme)).flatMap(AccentTheme.init(rawValue:)) ?? .sage,
                  customAccentRGB: try c.decodeIfPresent(Int.self, forKey: .customAccentRGB) ?? 0x367961)
    }
}

public enum AppearanceMode: String, Codable, Sendable {
    case system, light, dark
}
