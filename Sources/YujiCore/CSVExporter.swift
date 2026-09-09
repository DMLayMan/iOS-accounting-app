import Foundation

/// CSV 导出（PRD §10 / US29）。
/// 包含导出范围、账本/交易稳定 ID、发生日期、类型、金额、账户、分类路径、标签、备注与退款/转账关系标识。
/// 不把两条转账分录各自写成收入和支出。中文、逗号、换行、公式起始字符安全转义。
public enum CSVExporter {

    public struct Options {
        public var ledgerName: String
        public var range: ClosedRange<Day>?
        public init(ledgerName: String, range: ClosedRange<Day>? = nil) {
            self.ledgerName = ledgerName; self.range = range
        }
    }

    public static func export(transactions: [Transaction], store: LedgerStore, options: Options) -> String {
        let header = ["账本", "交易ID", "发生日期", "类型", "金额(元)", "账户", "对方账户",
                      "分类", "标签", "备注", "关联原支出ID", "录入表达式", "状态"]
        var rows: [[String]] = [header]

        let sorted = transactions
            .filter { options.range == nil || options.range!.contains($0.date) }
            .sorted { $0.date < $1.date }

        for t in sorted {
            let acc = store.account(t.accountID)?.name ?? ""
            let toAcc = t.transferToAccountID.flatMap { store.account($0)?.name } ?? ""
            let categoryPath: String
            if let cid = t.categoryID, let cat = store.category(cid) {
                let parent = cat.parentID.flatMap { store.category($0)?.name } ?? ""
                categoryPath = parent.isEmpty ? cat.name : "\(parent)/\(cat.name)"
            } else {
                categoryPath = ""
            }
            let tagNames = t.tagIDs.compactMap { tid -> String? in
                guard let tag = store.tag(tid) else { return nil }
                let parent = tag.parentID.flatMap { store.tag($0)?.name } ?? ""
                return parent.isEmpty ? tag.name : "\(parent)/\(tag.name)"
            }.joined(separator: "|")

            rows.append([
                options.ledgerName,
                t.id.raw,
                String(format: "%04d-%02d-%02d", t.date.year, t.date.month, t.date.day),
                t.kind.displayName,
                Money(t.amountCents).yuanDescription,
                acc,
                toAcc,
                categoryPath,
                tagNames,
                t.note,
                t.originalExpenseID?.raw ?? "",
                t.expression ?? "",
                t.isActive ? "有效" : "已删除"
            ])
        }

        return rows.map { row in
            row.map { escape($0) }.joined(separator: ",")
        }.joined(separator: "\r\n")
    }

    /// RFC4180 转义 + 防表格公式注入：剥离前导空白后以 = + - @ 开头的字段前置单引号。
    static func escape(_ field: String) -> String {
        var f = field
        if let first = f.trimmingCharacters(in: .whitespacesAndNewlines).first,
           ["=", "+", "-", "@"].contains(first) {
            f = "'" + f
        }
        if f.contains(",") || f.contains("\"") || f.contains("\n") || f.contains("\r") {
            f = f.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(f)\""
        }
        return f
    }
}
