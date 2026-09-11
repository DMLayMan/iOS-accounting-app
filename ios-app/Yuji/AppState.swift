import SwiftUI
import YujiCore

/// 应用根状态：持有 LedgerStore，所有变更经领域方法后原子落盘，并发布 UI 状态。
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var store: LedgerStore
    @Published private(set) var activeLedgerID: EntityID? {
        didSet { if activeLedgerID != oldValue { browsingPeriod = .currentMonth } }
    }
    @Published var browsingPeriod: BrowsingPeriod = .currentMonth
    @Published var today: Day
    @Published var toast: Toast?
    @Published var alertError: String?
    @Published var isSaving = false
    @Published private(set) var storageFailure: String?
    @Published var pendingUndo: (() -> Void)?   // 短时撤销回调

    private let repository: LedgerRepository
    private let dayProvider: () -> Day
    private var toastTask: Task<Void, Never>?

    struct Toast: Equatable {
        var message: String
        var kind: Kind = .info
        enum Kind { case info, success, error }
    }

    init(repository: LedgerRepository = JSONFileRepository(url: JSONFileRepository.defaultURL()),
         clockDay: Day = Day(from: Date()), dayProvider: @escaping () -> Day = { Day(from: Date()) }) {
        self.repository = repository
        self.dayProvider = dayProvider
        self.today = clockDay
        self.store = LedgerStore()
        self.activeLedgerID = nil
        reloadFromDisk()
    }

    /// 读取失败时保留原路径与字节，暂停写入，允许修复文件后重新读取。
    @discardableResult
    func reloadFromDisk() -> Bool {
        do {
            if let data = try repository.load() {
                try LedgerValidation.validate(data)
                self.store = LedgerStore(data: data)
                self.activeLedgerID = data.activeLedgerID
            } else {
                let s = LedgerStore()
                let ledger = try s.createLedger(name: "个人账本", startDay: today)
                try repository.save(s.data)
                self.store = s
                self.activeLedgerID = ledger.id
            }
            storageFailure = nil
            alertError = nil
            pendingUndo = nil
            return true
        } catch {
            storageFailure = "暂时无法读取本地账本，已暂停写入。原文件保持不变，可重新读取或选择备份恢复。"
            return false
        }
    }

    // MARK: - 落盘

    /// 在领域变更后调用：保存并发布。
    private func showToast(_ t: Toast) {
        toast = t
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled { self?.toast = nil; self?.pendingUndo = nil }
        }
    }

    /// 统一执行领域操作，捕获领域错误为可解释提示；失败不改数据。防重入（防重复保存）。
    @discardableResult
    func perform(_ messageOnSuccess: String? = nil, _ action: () throws -> Void) -> Bool {
        guard storageFailure == nil else { alertError = storageFailure; return false }
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        let snapshot = store.data
        do {
            try action()
            try LedgerValidation.validate(store.data)
            try repository.save(store.data)
            activeLedgerID = store.data.activeLedgerID
            alertError = nil
            if let message = messageOnSuccess { showToast(Toast(message: message, kind: .success)) }
            return true
        } catch let e as DomainError {
            store = LedgerStore(data: snapshot)
            activeLedgerID = snapshot.activeLedgerID
            toast = nil
            alertError = e.message
            return false
        } catch {
            store = LedgerStore(data: snapshot)
            activeLedgerID = snapshot.activeLedgerID
            toast = nil
            alertError = "保存未完成：\(error.localizedDescription)。请重试，原数据未改动。"
            return false
        }
    }

    // MARK: - 便捷访问

    var activeLedger: Ledger? {
        if let id = activeLedgerID, let l = store.ledger(id) { return l }
        return store.activeLedger
    }

    func stats(for ledgerID: EntityID) -> StatsEngine {
        StatsEngine(store: store, ledgerID: ledgerID)
    }

    var currentMonth: MonthKey { today.monthKey }

    var browsingBounds: ClosedRange<Day> {
        let id = activeLedgerID ?? ""
        let dates = store.activeTransactions(in: id).map(\.date)
            + store.accounts(in: id).map(\.startDay) + [today]
        return (dates.min() ?? today)...(dates.max() ?? today)
    }

    func refreshToday(now: Date? = nil) {
        let day = now.map { Day(from: $0) } ?? dayProvider()
        if today != day { today = day }
    }

    // MARK: - 账本切换

    @discardableResult
    func switchLedger(_ id: EntityID) -> Bool {
        perform { try store.switchLedger(id) }
    }

    @discardableResult
    func createAndSwitchLedger(name: String, monthlyBudget: Int64? = nil, yearlyBudget: Int64? = nil) -> Bool {
        perform("账本已创建") {
            let ledger = try store.createLedger(name: name, startDay: today)
            try store.setBudgets(ledgerID: ledger.id, monthly: monthlyBudget, yearly: yearlyBudget, effective: today)
            try store.switchLedger(ledger.id)
        }
    }

    // MARK: - 交易增改

    func addExpense(expression: String, date: Day, accountID: EntityID, categoryID: EntityID,
                    tagIDs: [EntityID], note: String, ledgerID: EntityID, kind: TransactionKind,
                    amountCents: Int64) -> Bool {
        let op = UUID().uuidString
        let t = YujiCore.Transaction(ledgerID: ledgerID, operationID: op, kind: kind, amountCents: amountCents,
                            date: date, accountID: accountID, categoryID: categoryID,
                            tagIDs: tagIDs, note: note, expression: expression)
        return perform("已保存") { try store.addTransaction(t); store.clearDraft(for: ledgerID) }
    }

    func addTransfer(amountCents: Int64, date: Day, from: EntityID, to: EntityID, note: String,
                     ledgerID: EntityID) -> Bool {
        let t = YujiCore.Transaction(ledgerID: ledgerID, kind: .transfer, amountCents: amountCents, date: date,
                            accountID: from, transferToAccountID: to, note: note)
        return perform("转账已记录") { try store.addTransaction(t) }
    }

    func addRefund(amountCents: Int64, date: Day, accountID: EntityID, original: EntityID, note: String,
                   ledgerID: EntityID) -> Bool {
        let t = YujiCore.Transaction(ledgerID: ledgerID, kind: .refund, amountCents: amountCents, date: date,
                            accountID: accountID, note: note, originalExpenseID: original)
        return perform("退款已记录") { try store.addTransaction(t) }
    }

    func update(_ id: EntityID, success: String = "已保存", _ apply: (inout YujiCore.Transaction) -> Void) -> Bool {
        perform(success) { try store.updateTransaction(id, apply: apply) }
    }

    // MARK: - 删除（带短时撤销）

    func delete(_ t: YujiCore.Transaction) {
        let result = perform(nil) { try store.deleteTransaction(t.id) }
        guard result else { return }
        showToast(Toast(message: "已删除", kind: .info))
        pendingUndo = { [weak self] in
            self?.perform("已撤销删除") { try self?.store.restoreTransaction(t.id) }
        }
    }

    func undoLastDelete() {
        pendingUndo?()
        pendingUndo = nil
    }

    func restore(_ id: EntityID) {
        perform("已恢复") { try store.restoreTransaction(id) }
    }

    func purge(_ id: EntityID) {
        perform("已永久删除") { try store.purgeTransaction(id) }
    }

    // MARK: - 草稿

    @discardableResult
    func saveDraft(_ draft: Draft, message: String? = nil) -> Bool {
        perform(message) { store.saveDraft(draft) }
    }
    @discardableResult
    func clearDraft(ledgerID: EntityID) -> Bool {
        perform { store.clearDraft(for: ledgerID) }
    }

    // MARK: - 备份恢复

    func exportBackup() -> Data? {
        guard storageFailure == nil else { alertError = storageFailure; return nil }
        do {
            let backup = try BackupService.makeBackup(from: store)
            return try BackupService.encode(backup)
        } catch {
            alertError = "生成备份失败：\(error.localizedDescription)"
            return nil
        }
    }

    var recoveryDirectory: URL? {
        guard let url = (repository as? JSONFileRepository)?.url else { return nil }
        return url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".restore-points", isDirectory: true)
    }

    var recoveryBackupURL: URL? {
        guard let id = store.data.recoveryBackupID, UUID(uuidString: id) != nil else { return nil }
        return recoveryDirectory?.appendingPathComponent(id + ".json")
    }

    func markBackupGenerated() {
        perform {
            var data = store.data; data.lastBackupAt = Date(); store = LedgerStore(data: data)
        }
    }

    /// 恢复：先隔离校验，落盘成功后再切换内存；失败原库不动。
    func restoreBackup(_ data: Data) -> Bool {
        do {
            let backup = try BackupService.decode(data)
            var validated = try BackupService.validate(backup: backup)
            validated.lastRestoreVerifiedAt = Date()
            // 先写到磁盘确认成功，再切换内存状态，避免“报成功但重启回退”。
            validated.recoveryBackupID = nil
            if let directory = recoveryDirectory {
                let recoveryID = UUID().uuidString
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if storageFailure != nil, let repository = repository as? JSONFileRepository,
                   FileManager.default.fileExists(atPath: repository.url.path) {
                    try FileManager.default.copyItem(at: repository.url, to: directory.appendingPathComponent("unreadable-" + recoveryID + ".json"))
                } else if storageFailure == nil {
                    let previous = try BackupService.encode(BackupService.makeBackup(from: store))
                    try previous.write(to: directory.appendingPathComponent(recoveryID + ".json"), options: .atomic)
                    validated.recoveryBackupID = recoveryID
                }
            }
            let newStore = LedgerStore(data: validated)
            try repository.save(newStore.data)
            store = newStore
            storageFailure = nil
            alertError = nil
            pendingUndo = nil
            activeLedgerID = validated.activeLedgerID ?? validated.ledgers.first?.id
            showToast(Toast(message: "恢复完成，数据已核对", kind: .success))
            return true
        } catch let e as BackupService.RestoreError {
            alertError = e.message
            return false
        } catch {
            alertError = "恢复失败：\(error.localizedDescription)。原数据未改动。"
            return false
        }
    }

    func exportCSV(ledgerID: EntityID) -> String {
        // 导出含有效与回收站记录（状态列区分），便于完整核对。
        let txns = store.data.transactions.filter { $0.ledgerID == ledgerID }
        let name = store.ledger(ledgerID)?.name ?? ""
        return CSVExporter.export(transactions: txns, store: store, options: .init(ledgerName: name))
    }
}
