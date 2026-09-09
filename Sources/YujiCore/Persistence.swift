import Foundation

/// 仓储协议：所有变更先在内存 LedgerStore 完成，再由 repository 原子落盘（PRD §6.1：无半笔交易）。
public protocol LedgerRepository {
    func load() throws -> LedgerData?
    func save(_ data: LedgerData) throws
}

/// JSON 文件仓储：写入临时文件后原子 rename，避免中断产生半文件（PRD US31/US30）。
public final class JSONFileRepository: LedgerRepository {
    public let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(url: URL) {
        self.url = url
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        self.encoder = e
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        self.decoder = d
    }

    /// 默认位置：Application Support/Yuji/ledger.json（iOS）；测试可注入临时 URL。
    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("Yuji", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ledger.json")
    }

    public func load() throws -> LedgerData? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return nil }
        return try decoder.decode(LedgerData.self, from: data)
    }

    public func save(_ data: LedgerData) throws {
        let bytes = try encoder.encode(data)
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try bytes.write(to: tmp, options: .atomic)
        // 原子替换
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }
}

/// 备份/恢复服务（PRD §10 / US30）。
/// 完整备份覆盖所有账本、账户及期初、分类/标签、有效与已删交易、设置、结构版本与校验清单。
/// 恢复先在隔离副本验证结构/数量/关系/余额，校验通过再交给调用方切换；失败保持原库。
public enum BackupService {

    public struct BackupFile: Codable {
        public var format: String            // "yuji-backup"
        public var formatVersion: Int
        public var createdAt: Date
        public var data: LedgerData
        /// 校验清单：实体数量与金额合计，恢复时核对。
        public var checksum: Checksum

        public struct Checksum: Codable, Sendable {
            public var ledgerCount: Int
            public var accountCount: Int
            public var transactionCount: Int
            public var activeTransactionCount: Int
            public var trashedTransactionCount: Int
            public var sumExpenseCents: Int64
            public var sumRefundCents: Int64
            public var sumIncomeCents: Int64
        }
    }

    public static func makeBackup(from store: LedgerStore, now: Date = Date()) throws -> BackupFile {
        let d = store.data
        let active = d.transactions.filter { $0.isActive }
        let checksum = BackupFile.Checksum(
            ledgerCount: d.ledgers.count,
            accountCount: d.accounts.count,
            transactionCount: d.transactions.count,
            activeTransactionCount: active.count,
            trashedTransactionCount: d.transactions.count - active.count,
            sumExpenseCents: active.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountCents },
            sumRefundCents: active.filter { $0.kind == .refund }.reduce(0) { $0 + $1.amountCents },
            sumIncomeCents: active.filter { $0.kind == .income }.reduce(0) { $0 + $1.amountCents }
        )
        var data = d
        data.lastBackupAt = now
        return BackupFile(format: "yuji-backup", formatVersion: LedgerData.currentSchemaVersion,
                          createdAt: now, data: data, checksum: checksum)
    }

    public static func encode(_ backup: BackupFile) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return try e.encode(backup)
    }

    public static func decode(_ data: Data) throws -> BackupFile {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(BackupFile.self, from: data)
    }

    public enum RestoreError: Swift.Error, Equatable {
        case badFormat
        case unsupportedVersion(Int)
        case checksumMismatch(String)
        case orphanReference(String)
        case refundExceedsExpense(String)
        public var message: String {
            switch self {
            case .badFormat: return "备份文件格式无法识别"
            case .unsupportedVersion(let v): return "备份版本（\(v)）不受支持"
            case .checksumMismatch(let m): return "备份校验未通过：\(m)"
            case .orphanReference(let m): return "备份存在无归属记录：\(m)"
            case .refundExceedsExpense(let m): return "备份退款超出原支出：\(m)"
            }
        }
    }

    /// 在隔离数据上校验；通过返回可用的 LedgerData，失败抛错（原库不动）。
    public static func validate(backup: BackupFile) throws -> LedgerData {
        guard backup.format == "yuji-backup" else { throw RestoreError.badFormat }
        guard backup.formatVersion <= LedgerData.currentSchemaVersion else {
            throw RestoreError.unsupportedVersion(backup.formatVersion)
        }
        let d = backup.data
        let active = d.transactions.filter { $0.isActive }

        // 1) 校验清单数量
        let cs = backup.checksum
        if cs.ledgerCount != d.ledgers.count { throw RestoreError.checksumMismatch("账本数量") }
        if cs.accountCount != d.accounts.count { throw RestoreError.checksumMismatch("账户数量") }
        if cs.transactionCount != d.transactions.count { throw RestoreError.checksumMismatch("交易数量") }
        if cs.activeTransactionCount != active.count { throw RestoreError.checksumMismatch("有效交易数量") }
        let sumExp = active.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountCents }
        let sumRef = active.filter { $0.kind == .refund }.reduce(0) { $0 + $1.amountCents }
        let sumInc = active.filter { $0.kind == .income }.reduce(0) { $0 + $1.amountCents }
        if sumExp != cs.sumExpenseCents { throw RestoreError.checksumMismatch("支出合计") }
        if sumRef != cs.sumRefundCents { throw RestoreError.checksumMismatch("退款合计") }
        if sumInc != cs.sumIncomeCents { throw RestoreError.checksumMismatch("收入合计") }

        // 2) 引用完整性：交易引用的账本/账户/分类必须存在
        let ledgerIDs = Set(d.ledgers.map(\.id))
        let accountIDs = Set(d.accounts.map(\.id))
        let categoryIDs = Set(d.categories.map(\.id))
        let txnByID = Dictionary(d.transactions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for t in d.transactions {
            guard ledgerIDs.contains(t.ledgerID) else { throw RestoreError.orphanReference("交易所属账本缺失") }
            guard accountIDs.contains(t.accountID) else { throw RestoreError.orphanReference("交易账户缺失") }
            if let to = t.transferToAccountID, !accountIDs.contains(to) {
                throw RestoreError.orphanReference("转账转入账户缺失")
            }
            if (t.kind == .expense || t.kind == .income), let c = t.categoryID, !categoryIDs.contains(c) {
                throw RestoreError.orphanReference("交易分类缺失")
            }
            if t.kind == .refund {
                guard let origID = t.originalExpenseID, let orig = txnByID[origID] else {
                    throw RestoreError.orphanReference("退款缺少原支出")
                }
                if orig.kind != .expense { throw RestoreError.orphanReference("退款原记录不是支出") }
            }
        }

        // 3) 退款额度：每笔原支出的有效退款合计不得超过其金额
        for t in active where t.kind == .expense {
            let refunded = active.filter { $0.kind == .refund && $0.originalExpenseID == t.id }
                .reduce(0) { $0 + $1.amountCents }
            if refunded > t.amountCents {
                throw RestoreError.refundExceedsExpense("原支出 ¥\(t.money.yuanDescription) 退款合计 ¥\(Money(refunded).yuanDescription)")
            }
        }
        return d
    }
}
