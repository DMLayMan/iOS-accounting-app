import Foundation

@main struct DomainProbes {
    static func main() throws {
        let today = Day(year: 2026, month: 10, day: 3)
        let store = LedgerStore()
        let ledger = try store.createLedger(name: "发布审查隔离账本", startDay: today)
        let account = store.accounts(in: ledger.id)[0]
        try store.updateAccountOpening(account.id, openingCents: 10_000, startDay: today)
        let category = store.categories(in: ledger.id, kind: .expense).first(where: { $0.isLeaf })!
        try store.addTransaction(Transaction(ledgerID: ledger.id, kind: .expense, amountCents: 1_000,
            date: Day(year: 2026, month: 10, day: 4), accountID: account.id, categoryID: category.id))
        try LedgerValidation.validate(store.data)
        let home = store.overview(in: ledger.id, through: today).balances.first { $0.id == account.id }!.cents
        let accountList = store.balance(accountID: account.id)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("yuji-release-probe-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = JSONFileRepository(url: folder.appendingPathComponent("ledger.json"))
        try repository.save(store.data)
        let loaded = try repository.load()!
        let backup = try BackupService.decode(BackupService.encode(BackupService.makeBackup(from: store)))
        let restored = try BackupService.validate(backup: backup)
        let result: [String: Any] = [
            "scope": "isolated core reproduction using the exact UI call sites, cents",
            "businessDay": "2026-10-03",
            "tomorrowExpenseCents": 1_000,
            "openingCents": 10_000,
            "ledgerHomeBalance": home,
            "accountListBalance": accountList,
            "discrepancyConfirmed": home != accountList,
            "reloadedTransactions": loaded.transactions.count,
            "restoredTransactions": restored.transactions.count
        ]
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
    }
}
