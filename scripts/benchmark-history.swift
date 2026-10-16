import Foundation

/// Compile with YujiCore sources using swiftc -O; uses isolated temporary files.
@main struct HistoryBenchmark {
    static func main() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try JSONFileRepository(url: root.appendingPathComponent("Fixtures/stats-500.json")).load()!
        var results: [[String: Any]] = []
        for count in [5_000, 50_000] {
            var data = fixture
            data.transactions = []
            data.appliedOperations = []
            for batch in 0..<(count / fixture.transactions.count) {
                for source in fixture.transactions {
                    var record = source
                    record.id = EntityID("\(source.id.raw)-\(batch)")
                    record.operationID = "\(source.operationID)-\(batch)"
                    record.originalExpenseID = source.originalExpenseID.map { EntityID("\($0.raw)-\(batch)") }
                    data.transactions.append(record)
                }
            }
            let store = LedgerStore(data: data)
            let day = Day(year: 2026, month: 9, day: 10)
            let categories = store.categories(in: "stress", kind: .expense, includeArchived: false)
                .filter { store.category($0.parentID)?.archived != true }.prefix(20)
            try store.setCategoryBudgets(ledgerID: "stress", limits: categories.map {
                CategoryBudgetLimit(period: .month, categoryID: $0.id, limit: 100_000)
            }, effective: day)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yuji-benchmark-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let repository = JSONFileRepository(url: directory.appendingPathComponent("ledger.json"))
            var row: [String: Any] = ["records": store.data.transactions.count, "categoryRules": categories.count, "build": "swiftc -O", "environment": "macOS host, not physical iPhone"]
            func measure(_ name: String, _ action: () throws -> Void) rethrows {
                var times: [Double] = []
                for _ in 0..<3 {
                    let start = DispatchTime.now().uptimeNanoseconds
                    try action()
                    times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                }
                row[name + "Ms"] = times.sorted()[1]
            }
            try measure("save") { try repository.save(store.data) }
            try measure("load") { _ = try repository.load() }
            measure("overview") { _ = store.overview(in: "stress", through: day) }
            measure("feedAll") { _ = store.transactions(in: "stress") }
            measure("categoryAnnual") { _ = StatsEngine(store: store, ledgerID: "stress").categoryGroups(range: BudgetPeriod.year.range(containing: day)) }
            measure("categoryAllTime") { _ = StatsEngine(store: store, ledgerID: "stress").categoryGroups(range: Day(year: 2022, month: 1, day: 1)...day) }
            measure("categoryBudgets") { _ = store.categoryBudgets(in: "stress", containing: day, through: day) }
            results.append(row)
        }
        let bytes = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: bytes, as: UTF8.self))
    }
}
