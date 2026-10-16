import Foundation

/// Read-only comparison of every entity. It never participates in merge or resolution.
public struct CloudSnapshotComparison {
    public struct Field: Identifiable {
        public var id: String
        public var title: String
        public var local: String
        public var remote: String
    }
    public struct Change: Identifiable {
        public var id: String
        public var title: String
        public var fields: [Field]
    }
    public let changes: [Change]

    public init(local: CloudLedgerSnapshot, remote: CloudLedgerSnapshot,
                personName: (String) -> String = { _ in "共享成员" }) throws {
        let lhs = try Self.object(local), rhs = try Self.object(remote)
        var result: [Change] = []
        func compare(_ group: String, _ id: String, _ a: [String: Any]?, _ b: [String: Any]?) {
            let ignored: Set<String> = ["id", "ledgerID", "operationID", "revision", "updatedAt", "createdAt", "lastEditorID", "budgetRules"]
            let keys = Set(a?.keys.map { $0 } ?? []).union(b?.keys.map { $0 } ?? []).subtracting(ignored)
            var fields = keys.sorted().compactMap { key -> Field? in
                guard !Self.same(a?[key], b?[key]) else { return nil }
                var left = Self.value(a?[key], key: key, book: local, personName: personName)
                var right = Self.value(b?[key], key: key, book: remote, personName: personName)
                // Equal nicknames must not make distinct immutable identities look identical.
                if key == "authorID", left == right { left += "（本机成员）"; right += "（云端成员）" }
                return Field(id: key, title: Self.labels[key] ?? key, local: a == nil ? "不存在" : left, remote: b == nil ? "不存在" : right)
            }
            if a == nil || b == nil {
                fields.insert(Field(id: "presence", title: "记录状态", local: a == nil ? "不存在" : "存在", remote: b == nil ? "不存在" : "存在"), at: 0)
            }
            guard !fields.isEmpty else { return }
            let title: String
            if group == "transactions", let record = (local.transactions + remote.transactions).first(where: { $0.id.raw == id }) {
                title = "\(Self.dateLabel(record.date)) · \(record.kind.displayName) ¥\(record.money.yuanDescription)"
            } else {
                title = "\(Self.groups[group] ?? group) · \((a?["name"] ?? b?["name"]) as? String ?? "未命名")"
            }
            result.append(Change(id: group + ":" + id, title: title, fields: fields))
        }
        compare("ledger", local.ledger.id.raw, lhs["ledger"] as? [String: Any], rhs["ledger"] as? [String: Any])
        func rules(_ book: CloudLedgerSnapshot) -> [String: BudgetRule] {
            Dictionary((book.ledger.budgetRules ?? []).map {
                ("\($0.period.rawValue):\($0.categoryID?.raw ?? "all"):\(Self.dateLabel($0.effectiveFrom))", $0)
            }, uniquingKeysWith: { first, _ in first })
        }
        let localRules = rules(local), remoteRules = rules(remote)
        for key in Set(localRules.keys).union(remoteRules.keys).sorted() {
            let a = localRules[key], b = remoteRules[key]
            guard a != b, let rule = a ?? b else { continue }
            let book = a == nil ? remote : local
            let scope = rule.categoryID.map { Self.value(["raw": $0.raw], key: "categoryID", book: book, personName: personName) } ?? "全账本"
            func limit(_ rule: BudgetRule?) -> String {
                guard let rule else { return "无此规则" }
                return rule.limit.map { "¥" + Money($0).yuanDescription } ?? "不设预算"
            }
            result.append(Change(id: "budget:" + key, title: "\(scope) · \(rule.period == .month ? "月" : "年")预算 · \(Self.dateLabel(rule.effectiveFrom)) 起",
                                 fields: [Field(id: "budgetRules", title: "预算额度", local: limit(a), remote: limit(b))]))
        }
        for group in ["transactions", "accounts", "categories", "tags"] {
            func keyed(_ object: [String: Any]) -> [String: [String: Any]] {
                Dictionary(((object[group] as? [[String: Any]]) ?? []).map {
                    (($0["id"] as? [String: String])?["raw"] ?? "", $0)
                }, uniquingKeysWith: { first, _ in first })
            }
            let a = keyed(lhs), b = keyed(rhs)
            for id in Set(a.keys).union(b.keys).sorted() { compare(group, id, a[id], b[id]) }
        }
        changes = result
    }

    private static func dateLabel(_ day: Day) -> String {
        String(format: "%04d-%02d-%02d", day.year, day.month, day.day)
    }

    private static let groups = ["ledger": "账本", "accounts": "账户", "categories": "分类", "tags": "历史标签"]
    private static let labels = [
        "amountCents": "金额", "date": "日期", "note": "备注", "kind": "类型", "accountID": "账户",
        "transferToAccountID": "转入账户", "categoryID": "分类", "tagIDs": "历史标签", "deletedAt": "删除状态",
        "authorID": "记账人", "expression": "金额算式", "originalExpenseID": "关联支出", "name": "名称",
        "currencyCode": "币种", "archived": "归档状态", "sortOrder": "排列顺序", "parentID": "上级分类",
        "pinnedOrder": "常用顺序", "symbolName": "图标", "budgetRules": "预算规则",
        "openingBalanceCents": "期初余额", "startDay": "记账起点"
    ]
    private static func object(_ book: CloudLedgerSnapshot) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: book.encoded()) as? [String: Any] ?? [:]
    }
    private static func same(_ a: Any?, _ b: Any?) -> Bool {
        guard let a else { return b == nil }; guard let b else { return false }
        return (a as? NSObject)?.isEqual(b) ?? false
    }
    private static func value(_ value: Any?, key: String, book: CloudLedgerSnapshot, personName: (String) -> String) -> String {
        guard let value else { return key == "deletedAt" ? "有效记录" : "未设置" }
        if key == "amountCents" || key == "openingBalanceCents", let cents = value as? Int64 { return "¥" + Money(cents).yuanDescription }
        if key == "archived" { return (value as? Bool) == true ? "已归档" : "未归档" }
        if key == "deletedAt" { return "已移到最近删除" }
        if key == "kind", let raw = value as? String { return TransactionKind(rawValue: raw)?.displayName ?? raw }
        if key == "authorID", let identity = value as? String { return personName(identity) }
        if ["date", "startDay"].contains(key), let day = value as? [String: Int] {
            return dateLabel(Day(year: day["year"] ?? 0, month: day["month"] ?? 0, day: day["day"] ?? 0))
        }
        if let id = (value as? [String: String])?["raw"] {
            if key == "accountID" || key == "transferToAccountID" { return book.accounts.first { $0.id.raw == id }?.name ?? "未找到的账户" }
            if key == "categoryID" || key == "parentID" {
                if let node = book.categories.first(where: { $0.id.raw == id }) {
                    let parent = book.categories.first { $0.id == node.parentID }?.name
                    return [parent, node.name].compactMap { $0 }.joined(separator: " · ")
                }
                return "未找到的分类"
            }
            if key == "originalExpenseID", let record = book.transactions.first(where: { $0.id.raw == id }) {
                return "\(Self.dateLabel(record.date)) · ¥\(record.money.yuanDescription) · \(record.note)"
            }
        }
        if key == "tagIDs", let ids = value as? [[String: String]] {
            let names = ids.compactMap { id in book.tags.first { $0.id.raw == id["raw"] }?.name }
            return names.isEmpty ? "无" : names.joined(separator: "、")
        }
        if let text = value as? String { return text.isEmpty ? "空" : text }
        if let number = value as? NSNumber { return number.stringValue }
        if let bytes = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]) { return String(decoding: bytes, as: UTF8.self) }
        return "未设置"
    }
}
