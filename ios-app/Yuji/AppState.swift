import SwiftUI
import YujiCore

/// 应用根状态：持有 LedgerStore，所有变更经领域方法后原子落盘，并发布 UI 状态。
@MainActor
final class AppState: ObservableObject {
    @Published var store: LedgerStore
    @Published var activeLedgerID: EntityID?
    @Published var today: Day
    @Published var toast: Toast?
    @Published var alertError: String?
    @Published var isSaving = false
    @Published var pendingUndo: (() -> Void)?   // 短时撤销回调

    private let repository: LedgerRepository
    private var saveTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    struct Toast: Equatable {
        var message: String
        var kind: Kind = .info
        enum Kind { case info, success, error }
    }

    init(repository: LedgerRepository = JSONFileRepository(url: JSONFileRepository.defaultURL()),
         clockDay: Day = Day(from: Date())) {
        self.repository = repository
        self.today = clockDay
        do {
            if let data = try repository.load() {
                self.store = LedgerStore(data: data)
                self.activeLedgerID = data.activeLedgerID
            } else {
                let s = LedgerStore()
                let ledger = try s.createLedger(name: "个人账本")
                self.store = s
                self.activeLedgerID = ledger.id
                try? Self.persist(repository: repository, data: s.data)
            }
        } catch {
            // 本地数据无法读取：先隔离原文件（避免被空库首次保存覆盖，导致不可挽回），再新建空库。
            (repository as? JSONFileRepository).map { Self.quarantine($0) }
            self.store = LedgerStore()
            let ledger = try? self.store.createLedger(name: "个人账本")
            self.activeLedgerID = ledger?.id
            self.alertError = "本地数据读取失败，原文件已隔离保留；已新建空账本，可在「我的 → 数据」从备份恢复。"
        }
    }

    /// 把损坏的数据文件改名隔离，防止被后续保存覆盖（PRD：坏数据可恢复、不静默丢弃）。
    private static func quarantine(_ repo: JSONFileRepository) {
        let url = repo.url
        let dst = url.deletingLastPathComponent()
            .appendingPathComponent("ledger.corrupt-\(UUID().uuidString).json")
        try? FileManager.default.moveItem(at: url, to: dst)
    }

    // MARK: - 落盘

    private static func persist(repository: LedgerRepository, data: LedgerData) throws {
        try repository.save(data)
    }

    /// 在领域变更后调用：保存并发布。
    private func commit(_ message: String? = nil) {
        activeLedgerID = store.data.activeLedgerID
        do {
            try repository.save(store.data)
            if let message = message { showToast(Toast(message: message, kind: .success)) }
        } catch {
            alertError = "保存失败：\(error.localizedDescription)。请重试，数据未丢失。"
        }
    }

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
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try action()
            commit(messageOnSuccess)
            return true
        } catch let e as DomainError {
            alertError = e.message
            return false
        } catch {
            alertError = "操作失败：\(error.localizedDescription)"
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

    // MARK: - 账本切换

    func switchLedger(_ id: EntityID) {
        perform { try store.switchLedger(id) }
    }

    // MARK: - 交易增改

    func addExpense(expression: String, date: Day, accountID: EntityID, categoryID: EntityID,
                    tagIDs: [EntityID], note: String, ledgerID: EntityID, kind: TransactionKind,
                    amountCents: Int64) -> Bool {
        let op = UUID().uuidString
        let t = Transaction(ledgerID: ledgerID, operationID: op, kind: kind, amountCents: amountCents,
                            date: date, accountID: accountID, categoryID: categoryID,
                            tagIDs: tagIDs, note: note, expression: expression)
        return perform("已保存") { try store.addTransaction(t); store.clearDraft(for: ledgerID) }
    }

    func addTransfer(amountCents: Int64, date: Day, from: EntityID, to: EntityID, note: String,
                     ledgerID: EntityID) -> Bool {
        let t = Transaction(ledgerID: ledgerID, kind: .transfer, amountCents: amountCents, date: date,
                            accountID: from, transferToAccountID: to, note: note)
        return perform("转账已记录") { try store.addTransaction(t); store.clearDraft(for: ledgerID) }
    }

    func addRefund(amountCents: Int64, date: Day, accountID: EntityID, original: EntityID, note: String,
                   ledgerID: EntityID) -> Bool {
        let t = Transaction(ledgerID: ledgerID, kind: .refund, amountCents: amountCents, date: date,
                            accountID: accountID, note: note, originalExpenseID: original)
        return perform("退款已记录") { try store.addTransaction(t) }
    }

    func update(_ id: EntityID, _ apply: (inout Transaction) -> Void, success: String = "已保存") -> Bool {
        perform(success) { try store.updateTransaction(id, apply: apply) }
    }

    // MARK: - 删除（带短时撤销）

    func delete(_ t: Transaction) {
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

    func saveDraft(_ draft: Draft) {
        store.saveDraft(draft)
        commit()
    }
    func clearDraft(ledgerID: EntityID) {
        store.clearDraft(for: ledgerID)
        commit()
    }

    // MARK: - 备份恢复

    func exportBackup() -> Data? {
        do {
            let backup = try BackupService.makeBackup(from: store)
            // 备份文件已生成即视为本地备份成功；落盘记录最近备份时间
            store.data.lastBackupAt = backup.createdAt
            commit()
            return try BackupService.encode(backup)
        } catch {
            alertError = "生成备份失败：\(error.localizedDescription)"
            return nil
        }
    }

    /// 恢复：先隔离校验，落盘成功后再切换内存；失败原库不动。
    func restoreBackup(_ data: Data) -> Bool {
        do {
            let backup = try BackupService.decode(data)
            var validated = try BackupService.validate(backup: backup)
            validated.lastRestoreVerifiedAt = Date()
            // 先写到磁盘确认成功，再切换内存状态，避免“报成功但重启回退”。
            let newStore = LedgerStore(data: validated)
            try repository.save(newStore.data)
            store = newStore
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
