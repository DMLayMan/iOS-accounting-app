import Foundation

/// One isolated CloudKit zone per book. Names and nicknames never identify a workspace.
public struct CloudAddress: Codable, Hashable, Sendable {
    public enum Scope: String, Codable, Sendable { case `private`, shared }
    public var container: String
    public var environment: String
    public var scope: Scope
    public var zoneName: String
    public var ownerName: String
    public init(container: String, environment: String = "Development", scope: Scope = .private, zoneName: String, ownerName: String = "__defaultOwner__") {
        self.container = container; self.environment = environment; self.scope = scope; self.zoneName = zoneName; self.ownerName = ownerName
    }
}

/// Only shared business data, deliberately excluding preferences, drafts and other books.
public struct CloudLedgerSnapshot: Codable, Equatable, Sendable {
    public var formatVersion = 1
    public var ledger: Ledger
    public var accounts: [Account]
    public var categories: [CategoryNode]
    public var tags: [TagNode]
    public var transactions: [Transaction]
    public init(data: LedgerData, ledgerID: EntityID) throws {
        guard let book = data.ledgers.first(where: { $0.id == ledgerID }) else { throw DomainError.notFound("账本") }
        ledger = book
        accounts = data.accounts.filter { $0.ledgerID == ledgerID }.sorted { $0.id.raw < $1.id.raw }
        categories = data.categories.filter { $0.ledgerID == ledgerID }.sorted { $0.id.raw < $1.id.raw }
        tags = data.tags.filter { $0.ledgerID == ledgerID }.sorted { $0.id.raw < $1.id.raw }
        transactions = data.transactions.filter { $0.ledgerID == ledgerID }.sorted { $0.id.raw < $1.id.raw }
    }
    public func materialized() -> LedgerData {
        LedgerData(ledgers: [ledger], accounts: accounts, categories: categories, tags: tags, transactions: transactions,
                   activeLedgerID: ledger.id, appliedOperations: transactions.map(\.operationID))
    }
    public func validate() throws {
        guard formatVersion == 1 else { throw DomainError.restoreBlocked("云端账本版本暂不支持，请更新 App") }
        try LedgerValidation.validate(materialized())
        var names = Set<String>()
        for category in categories {
            let key = category.kind.rawValue + "|" + (category.parentID?.raw ?? "") + "|" + category.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard names.insert(key).inserted else { throw DomainError.duplicateCategoryName }
        }
    }
    public func encoded() throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; e.dateEncodingStrategy = .iso8601
        return try e.encode(self)
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 40_000_000 else { throw DomainError.restoreBlocked("云端账本超过本版本可处理的大小") }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let value = try d.decode(Self.self, from: data); try value.validate(); return value
    }
    public func matches(_ other: Self) -> Bool { (try? encoded()) == (try? other.encoded()) }
}

public struct CloudRemote: Sendable {
    public var snapshot: CloudLedgerSnapshot
    /// Opaque CKRecord system fields, used for compare-and-swap, never a device clock.
    public var version: Data
    public var writable: Bool
    public init(snapshot: CloudLedgerSnapshot, version: Data, writable: Bool = true) {
        self.snapshot = snapshot; self.version = version; self.writable = writable
    }
}

public enum CloudSyncError: Error, Equatable {
    case unavailable, notSignedIn, offline, conflict, revoked, invalid(String)
    public var message: String {
        switch self {
        case .unavailable: return "此安装包尚未配置 iCloud。账本仍可在本机使用。"
        case .notSignedIn: return "请先在系统设置登录 iCloud，再重试。"
        case .offline: return "暂时无法连接 iCloud，本机修改已保留，联网后重试。"
        case .conflict: return "其他设备刚更新了账本，请重新同步。"
        case .revoked: return "共享权限已改变或账本已停止共享。本机副本已保留。"
        case .invalid(let message): return message
        }
    }
}

@MainActor public protocol CloudTransport: AnyObject {
    var supportsPeople: Bool { get }
    func myPerson() async throws -> CloudPerson
    func saveMyPerson(_ person: CloudPerson) async throws
    func people(at address: CloudAddress) async throws -> [CloudPerson]
    func publishMyPerson(_ person: CloudPerson, at address: CloudAddress) async throws
    var configuration: CloudAddress { get }
    func accountID() async throws -> String
    func addresses() async throws -> [CloudAddress]
    func fetch(_ address: CloudAddress) async throws -> CloudRemote?
    func save(_ snapshot: CloudLedgerSnapshot, at address: CloudAddress, version: Data?) async throws -> CloudRemote
    func leave(_ address: CloudAddress) async throws
}

/// Cached data + common ancestor form a durable outbox, saved in the same atomic local file.
public struct CloudLink: Codable, Sendable, Identifiable {
    public var id: CloudAddress { address }
    public var accountID: String
    public var address: CloudAddress
    public var cached: CloudLedgerSnapshot
    public var base: CloudLedgerSnapshot?
    public var version: Data?
    public var writable: Bool
    public var paused: Bool = false
    public var lastSync: Date?
    public var issue: String?
    public var incoming: CloudLedgerSnapshot?
    public var localDraft: Draft?
    public var unresolvedDraft: Draft?
    public init(accountID: String, address: CloudAddress, cached: CloudLedgerSnapshot, base: CloudLedgerSnapshot? = nil,
                version: Data? = nil, writable: Bool = true) {
        self.accountID = accountID; self.address = address; self.cached = cached; self.base = base; self.version = version; self.writable = writable
    }
    public var pending: Bool { base.map { cached != $0 } ?? true }
}

public enum CloudLedgerMerge {
    public struct Result {
        public let snapshot: CloudLedgerSnapshot
        public let conflicts: [String]
        public init(snapshot: CloudLedgerSnapshot, conflicts: [String]) { self.snapshot = snapshot; self.conflicts = conflicts }
    }
    /// Entity IDs first, then independent fields. Same-field conflicts never use last-writer-wins.
    public static func merge(base: CloudLedgerSnapshot, local: CloudLedgerSnapshot, remote: CloudLedgerSnapshot) throws -> Result {
        try base.validate(); try local.validate(); try remote.validate()
        guard base.ledger.id == local.ledger.id, base.ledger.id == remote.ledger.id else { throw DomainError.ledgerMismatch("云端账本身份不一致") }
        if local.matches(base) { return Result(snapshot: remote, conflicts: []) }
        if remote.matches(base) || local.matches(remote) { return Result(snapshot: local, conflicts: []) }
        var conflicts: [String] = []
        let b = try object(base), l = try object(local), r = try object(remote)
        var merged = l
        for key in ["accounts", "categories", "tags", "transactions"] {
            merged[key] = mergeEntities(b[key] as? [[String: Any]] ?? [], l[key] as? [[String: Any]] ?? [], r[key] as? [[String: Any]] ?? [], label: key, conflicts: &conflicts)
        }
        merged["ledger"] = mergeFields(b["ledger"] as? [String: Any] ?? [:], l["ledger"] as? [String: Any] ?? [:], r["ledger"] as? [String: Any] ?? [:], label: "账本", conflicts: &conflicts)
        let bytes = try JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys])
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(CloudLedgerSnapshot.self, from: bytes)
        do { try result.validate() } catch { conflicts.append("合并后数据关系不满足要求：\(describe(error))") }
        return Result(snapshot: result, conflicts: conflicts)
    }
    private static func object(_ value: CloudLedgerSnapshot) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: value.encoded()) as? [String: Any] ?? [:]
    }
    private static func same(_ a: Any?, _ b: Any?) -> Bool {
        guard let a else { return b == nil }; guard let b else { return false }
        return (a as? NSObject)?.isEqual(b) ?? false
    }
    private static func identity(_ value: [String: Any]) -> String { (value["id"] as? [String: Any])?["raw"] as? String ?? "" }
    private static func mergeEntities(_ b: [[String: Any]], _ l: [[String: Any]], _ r: [[String: Any]], label: String, conflicts: inout [String]) -> [[String: Any]] {
        let base = Dictionary(uniqueKeysWithValues: b.map { (identity($0), $0) })
        let local = Dictionary(uniqueKeysWithValues: l.map { (identity($0), $0) })
        let remote = Dictionary(uniqueKeysWithValues: r.map { (identity($0), $0) })
        return Set(base.keys).union(local.keys).union(remote.keys).sorted().compactMap { key in
            let a = base[key], x = local[key], y = remote[key]
            if same(x, a) { return y }; if same(y, a) || same(x, y) { return x }
            guard let a, let x, let y else { conflicts.append("\(labelName(label))：删除与修改或重复新增冲突"); return x }
            // A soft delete and another user's edit also require an explicit decision.
            if (x["deletedAt"] != nil) != (y["deletedAt"] != nil) {
                conflicts.append("流水：删除与修改冲突"); return x
            }
            return mergeFields(a, x, y, label: labelName(label), conflicts: &conflicts)
        }
    }
    private static func mergeFields(_ b: [String: Any], _ l: [String: Any], _ r: [String: Any], label: String, conflicts: inout [String]) -> [String: Any] {
        var result = l
        for key in Set(b.keys).union(l.keys).union(r.keys) {
            if key == "updatedAt" || key == "lastEditorID" { result[key] = l[key] ?? r[key]; continue }
            if key == "revision" { result[key] = max(l[key] as? Int ?? 1, r[key] as? Int ?? 1) + 1; continue }
            if key == "budgetRules" {
                result[key] = mergeBudgets(b[key] as? [[String: Any]] ?? [], l[key] as? [[String: Any]] ?? [], r[key] as? [[String: Any]] ?? [], conflicts: &conflicts)
            } else if same(l[key], b[key]) { result[key] = r[key] }
            else if !same(r[key], b[key]) && !same(l[key], r[key]) { conflicts.append("\(label)：\(fieldName(key))被同时修改") }
        }
        return result
    }
    private static func mergeBudgets(_ b: [[String: Any]], _ l: [[String: Any]], _ r: [[String: Any]], conflicts: inout [String]) -> [[String: Any]] {
        func keyed(_ list: [[String: Any]]) -> [String: [String: Any]] {
            Dictionary(list.map { value in
                let bytes = try? JSONSerialization.data(withJSONObject: ["period": value["period"] ?? "", "effectiveFrom": value["effectiveFrom"] ?? [:], "categoryID": value["categoryID"] ?? NSNull()], options: [.sortedKeys])
                return (bytes.map { String(decoding: $0, as: UTF8.self) } ?? "", value)
            }, uniquingKeysWith: { a, _ in a })
        }
        let base = keyed(b), local = keyed(l), remote = keyed(r)
        return Set(base.keys).union(local.keys).union(remote.keys).sorted().compactMap { key in
            if same(local[key], base[key]) { return remote[key] }
            if !same(remote[key], base[key]) && !same(local[key], remote[key]) { conflicts.append("预算：同一范围的额度被同时修改") }
            return local[key]
        }
    }
    private static func labelName(_ key: String) -> String { ["accounts": "账户", "categories": "分类", "tags": "历史标签", "transactions": "流水"][key] ?? key }
    private static func fieldName(_ key: String) -> String { ["amountCents": "金额", "note": "备注", "date": "日期", "name": "名称", "categoryID": "分类", "accountID": "账户", "openingBalanceCents": "期初余额"][key] ?? "信息" }
    public static func describe(_ error: Error) -> String { (error as? CloudSyncError)?.message ?? (error as? DomainError)?.message ?? "暂时无法完成同步，请重试。" }
}

public enum CloudWorkspace {
    public static func capture(_ data: inout LedgerData) throws {
        guard var links = data.cloudLinks else { return }
        for i in links.indices where (data.activeCloudAccountID == nil || links[i].accountID == data.activeCloudAccountID) && data.ledgers.contains(where: { $0.id == links[i].cached.ledger.id }) {
            links[i].cached = try CloudLedgerSnapshot(data: data, ledgerID: links[i].cached.ledger.id)
            links[i].localDraft = data.drafts.first { $0.ledgerID == links[i].cached.ledger.id }
        }
        data.cloudLinks = links
    }
    public static func parkAll(_ data: inout LedgerData) throws {
        try capture(&data)
        for link in data.cloudLinks ?? [] { remove(link.cached.ledger.id, from: &data) }
        data.activeCloudAccountID = nil
        if data.activeLedgerID.flatMap({ id in data.ledgers.first { $0.id == id } }) == nil { data.activeLedgerID = data.ledgers.first?.id }
    }
    public static func activate(_ accountID: String, in data: inout LedgerData) throws {
        try parkAll(&data)
        data.activeCloudAccountID = accountID
        for link in data.cloudLinks ?? [] where link.accountID == accountID {
            try install(link.cached, in: &data)
            if let draft = link.localDraft {
                var withDraft = data; withDraft.drafts.append(draft)
                if (try? LedgerValidation.validate(withDraft)) != nil { data = withDraft }
            }
        }
        if data.activeLedgerID == nil { data.activeLedgerID = data.ledgers.first?.id }
    }
    public static func install(_ book: CloudLedgerSnapshot, in data: inout LedgerData) throws {
        try book.validate()
        // A cloud address must be bound before replacing its visible local entities.
        if data.ledgers.contains(where: { $0.id == book.ledger.id }), !(data.cloudLinks ?? []).contains(where: { $0.cached.ledger.id == book.ledger.id }) {
            throw DomainError.ledgerMismatch("发现同标识的本地账本，未覆盖。请先保留备份并检查账本来源。")
        }
        let draft = data.drafts.first { $0.ledgerID == book.ledger.id }
        let wasActive = data.activeLedgerID == book.ledger.id
        remove(book.ledger.id, from: &data)
        data.ledgers.append(book.ledger); data.accounts += book.accounts; data.categories += book.categories; data.tags += book.tags; data.transactions += book.transactions
        data.appliedOperations = Array(Set(data.appliedOperations + book.transactions.map(\.operationID))).sorted()
        if wasActive || data.activeLedgerID == nil { data.activeLedgerID = book.ledger.id }
        if let draft {
            var candidate = data; candidate.drafts.append(draft)
            if (try? LedgerValidation.validate(candidate)) != nil { data = candidate }
            else if let i = data.cloudLinks?.firstIndex(where: { $0.cached.ledger.id == book.ledger.id && (data.activeCloudAccountID == nil || $0.accountID == data.activeCloudAccountID) }) { data.cloudLinks?[i].unresolvedDraft = draft }
        }
    }
    public static func remove(_ id: EntityID, from data: inout LedgerData) {
        data.ledgers.removeAll { $0.id == id }; data.accounts.removeAll { $0.ledgerID == id }
        data.categories.removeAll { $0.ledgerID == id }; data.tags.removeAll { $0.ledgerID == id }
        data.transactions.removeAll { $0.ledgerID == id }; data.drafts.removeAll { $0.ledgerID == id }
        if data.activeLedgerID == id { data.activeLedgerID = data.ledgers.first?.id }
    }
    public static func checkMutation(before: LedgerData, after: LedgerData, accountID: String?) throws {
        for link in before.cloudLinks ?? [] {
            guard link.accountID == (before.activeCloudAccountID ?? accountID) else { continue }
            let id = link.cached.ledger.id
            guard before.ledgers.contains(where: { $0.id == id }) else { continue }
            guard after.ledgers.contains(where: { $0.id == id }) else { throw CloudSyncError.invalid("云端账本请从同步与成员中管理，不能直接删除。") }
            let changed = !(try CloudLedgerSnapshot(data: before, ledgerID: id)).matches(try CloudLedgerSnapshot(data: after, ledgerID: id))
            if changed && (link.accountID != accountID || !link.writable || link.incoming != nil) {
                throw CloudSyncError.invalid(link.incoming == nil ? "此账本当前仅可查看。请确认 iCloud 账号和成员权限。" : "此账本有待处理冲突，请先保留副本并处理。")
            }
        }
    }
    /// A deliberately independent local copy remaps every ID and reference.
    public static func localCopy(_ source: CloudLedgerSnapshot, name: String) throws -> CloudLedgerSnapshot {
        try source.validate()
        var value = source
        let ids = [source.ledger.id] + source.accounts.map(\.id) + source.categories.map(\.id) + source.tags.map(\.id) + source.transactions.map(\.id)
        let mapping = Dictionary(uniqueKeysWithValues: Set(ids).map { ($0, EntityID.new()) })
        func id(_ old: EntityID) -> EntityID { mapping[old]! }
        value.ledger.id = id(source.ledger.id); value.ledger.name = name
        value.ledger.budgetRules = source.ledger.budgetRules?.map { rule in var x = rule; x.categoryID = rule.categoryID.map(id); return x }
        value.accounts = source.accounts.map { var x = $0; x.id = id(x.id); x.ledgerID = value.ledger.id; return x }
        value.categories = source.categories.map { var x = $0; x.id = id(x.id); x.ledgerID = value.ledger.id; x.parentID = x.parentID.map(id); return x }
        value.tags = source.tags.map { var x = $0; x.id = id(x.id); x.ledgerID = value.ledger.id; x.parentID = x.parentID.map(id); return x }
        value.transactions = source.transactions.map { var x = $0; x.id = id(x.id); x.ledgerID = value.ledger.id; x.operationID = UUID().uuidString; x.accountID = id(x.accountID); x.transferToAccountID = x.transferToAccountID.map(id); x.categoryID = x.categoryID.map(id); x.tagIDs = x.tagIDs.map(id); x.originalExpenseID = x.originalExpenseID.map(id); return x }
        try value.validate(); return value
    }

    public static func localDraftCopy(_ source: Draft, from old: CloudLedgerSnapshot, to copy: CloudLedgerSnapshot) -> Draft {
        var value = source
        let pairs = Array(zip(old.accounts.map(\.id), copy.accounts.map(\.id))) + Array(zip(old.categories.map(\.id), copy.categories.map(\.id)))
        var mapping = Dictionary(pairs, uniquingKeysWith: { a, _ in a })
        for (a, b) in zip(old.tags.map(\.id), copy.tags.map(\.id)) { mapping[a] = b }
        for (a, b) in zip(old.transactions.map(\.id), copy.transactions.map(\.id)) { mapping[a] = b }
        value.ledgerID = copy.ledger.id
        value.accountID = value.accountID.flatMap { mapping[$0] }; value.transferToAccountID = value.transferToAccountID.flatMap { mapping[$0] }
        value.categoryID = value.categoryID.flatMap { mapping[$0] }; value.tagIDs = value.tagIDs.compactMap { mapping[$0] }
        value.originalExpenseID = value.originalExpenseID.flatMap { mapping[$0] }
        return value
    }
}
