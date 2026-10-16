import XCTest
import YujiCore
#if canImport(YujiAppState)
@testable import YujiAppState
#else
@testable import Yuji
#endif

@MainActor
final class AppStateTests: XCTestCase {
    func testCrossYearBackdateRequiresExplicitStartAdjustmentAndKeepsDraftOnFailure() throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        for opening: Int64 in [0, 10_000] {
            let repository = Repository()
            let today = Day(year: 2026, month: 10, day: 15)
            let past = Day(year: 2025, month: 12, day: 31)
            let state = AppState(repository: repository, clockDay: today)
            let ledger = try XCTUnwrap(state.activeLedger)
            let account = try XCTUnwrap(state.store.accounts(in: ledger.id).first)
            let category = try XCTUnwrap(state.store.categories(in: ledger.id, kind: .expense).first(where: \.isLeaf))
            XCTAssertTrue(state.perform { try state.store.updateAccountOpening(account.id, openingCents: opening, startDay: today) })
            let draft = Draft(ledgerID: ledger.id, expression: "42", date: past, accountID: account.id, categoryID: category.id, note: "跨年补记")
            XCTAssertTrue(state.saveDraft(draft))
            XCTAssertFalse(state.addExpense(expression: "42", date: past, accountID: account.id, categoryID: category.id, tagIDs: [], note: draft.note, ledgerID: ledger.id, kind: .expense, amountCents: 4_200))
            XCTAssertTrue(state.alertError?.contains("2026年10月15日") == true)
            XCTAssertEqual(state.store.draft(for: ledger.id), draft)
            let before = try encoder.encode(state.store.data)
            repository.fails = true
            XCTAssertFalse(state.perform { try state.store.updateAccountOpening(account.id, openingCents: opening, startDay: past) })
            XCTAssertEqual(try encoder.encode(state.store.data), before)
            repository.fails = false
            XCTAssertTrue(state.perform { try state.store.updateAccountOpening(account.id, openingCents: opening, startDay: past) })
            XCTAssertEqual(state.store.draft(for: ledger.id), draft)
            XCTAssertEqual(state.currentBalance(accountID: account.id), opening)
            XCTAssertTrue(state.addExpense(expression: "42", date: past, accountID: account.id, categoryID: category.id, tagIDs: [], note: draft.note, ledgerID: ledger.id, kind: .expense, amountCents: 4_200))
            let reloaded = AppState(repository: repository, clockDay: today)
            XCTAssertEqual(reloaded.store.account(account.id)?.startDay, past)
            XCTAssertEqual(reloaded.store.account(account.id)?.openingBalanceCents, opening)
            XCTAssertEqual(reloaded.currentBalance(accountID: account.id), opening - 4_200)
            XCTAssertNil(reloaded.store.draft(for: ledger.id))
            XCTAssertEqual(reloaded.store.data.transactions.count, 1)
        }
    }

    func testAccountStartCannotMovePastSavedHistory() throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let today = Day(year: 2026, month: 10, day: 15)
        let state = AppState(repository: Repository(), clockDay: today)
        let ledger = try XCTUnwrap(state.activeLedger)
        let account = try XCTUnwrap(state.store.accounts(in: ledger.id).first)
        let category = try XCTUnwrap(state.store.categories(in: ledger.id, kind: .expense).first(where: \.isLeaf))
        XCTAssertTrue(state.addExpense(expression: "10", date: today, accountID: account.id, categoryID: category.id, tagIDs: [], note: "已有记录", ledgerID: ledger.id, kind: .expense, amountCents: 1_000))
        let before = try encoder.encode(state.store.data)
        XCTAssertFalse(state.perform { try state.store.updateAccountOpening(account.id, openingCents: 0, startDay: today.nextDay) })
        XCTAssertEqual(try encoder.encode(state.store.data), before)
    }

    func testCurrentBalanceUsesRefreshedBusinessDayAndFutureOpening() throws {
        let today = Day(year: 2026, month: 10, day: 8)
        let tomorrow = Day(year: 2026, month: 10, day: 9)
        let state = AppState(repository: Repository(), clockDay: today, dayProvider: { tomorrow })
        let ledger = try XCTUnwrap(state.activeLedger)
        let account = try state.store.createAccount(ledgerID: ledger.id, name: "未来", openingBalanceCents: 10_000, startDay: tomorrow)
        XCTAssertEqual(state.currentBalance(accountID: account.id), 0)
        state.refreshToday()
        XCTAssertEqual(state.currentBalance(accountID: account.id), 10_000)
    }
    func testSharedPeriodSurvivesWritesAndOnlyResetsAfterSuccessfulLedgerSwitch() throws {
        let repository = Repository()
        let state = AppState(repository: repository)
        let first = try XCTUnwrap(state.activeLedger)
        XCTAssertTrue(state.createAndSwitchLedger(name: "第二本"))
        state.browsingPeriod = .year(2024)
        XCTAssertTrue(state.perform { })
        XCTAssertEqual(state.browsingPeriod, .year(2024))
        repository.fails = true
        XCTAssertFalse(state.switchLedger(first.id))
        XCTAssertEqual(state.browsingPeriod, .year(2024))
        repository.fails = false
        XCTAssertTrue(state.switchLedger(first.id))
        XCTAssertEqual(state.browsingPeriod, .currentMonth)
    }
    final class Repository: LedgerRepository {
        var saved: LedgerData?
        var fails = false
        func load() throws -> LedgerData? { saved }
        func save(_ data: LedgerData) throws {
            if fails { throw CocoaError(.fileWriteOutOfSpace) }
            saved = data
        }
    }

    func testDraftSaveAndClearReturnFailureWithoutLosingPreviousDraft() throws {
        let repository = Repository(); let state = AppState(repository: repository)
        let ledger = try XCTUnwrap(state.activeLedger)
        let original = Draft(ledgerID: ledger.id, expression: "123", date: state.today, note: "未完成")
        XCTAssertTrue(state.saveDraft(original))
        var edited = original; edited.expression = "456"
        repository.fails = true
        XCTAssertFalse(state.saveDraft(edited, message: "草稿已保留"))
        XCTAssertEqual(state.store.draft(for: ledger.id), original)
        XCTAssertNil(state.toast)
        XCTAssertFalse(state.clearDraft(ledgerID: ledger.id))
        XCTAssertEqual(state.store.draft(for: ledger.id), original)
        repository.fails = false
        XCTAssertTrue(state.saveDraft(edited, message: "草稿已保留"))
        XCTAssertEqual(AppState(repository: repository).store.draft(for: ledger.id), edited)
        XCTAssertTrue(state.clearDraft(ledgerID: ledger.id))
        XCTAssertNil(AppState(repository: repository).store.draft(for: ledger.id))
    }

    func testWholeAndCategoryBudgetsRollBackTogetherOnDiskFailure() throws {
        let repository = Repository(); let state = AppState(repository: repository)
        let ledger = try XCTUnwrap(state.activeLedger)
        let category = try XCTUnwrap(state.store.categories(in: ledger.id, kind: .expense).first)
        repository.fails = true
        XCTAssertFalse(state.perform {
            try state.store.setBudgets(ledgerID: ledger.id, monthly: 100_000, yearly: nil, effective: state.today)
            try state.store.setCategoryBudgets(ledgerID: ledger.id, limits: [.init(period: .month, categoryID: category.id, limit: 10_000)], effective: state.today)
        })
        XCTAssertNil(state.store.budgetLimit(in: ledger.id, period: .month, containing: state.today))
        XCTAssertTrue(state.store.categoryBudgetLimits(in: ledger.id, containing: state.today).isEmpty)
        repository.fails = false
        XCTAssertTrue(state.perform {
            try state.store.setCategoryBudgets(ledgerID: ledger.id, limits: [.init(period: .month, categoryID: category.id, limit: 10_000)], effective: state.today)
        })
        XCTAssertEqual(AppState(repository: repository).store.categoryBudgetLimits(in: ledger.id, containing: state.today).count, 1)
    }

    func testCategoryReorderRollsBackOnDiskFailureAndReloadsOnSuccess() throws {
        let repository = Repository(); let state = AppState(repository: repository)
        let ledger = try XCTUnwrap(state.activeLedger)
        let parents = state.store.categories(in: ledger.id, kind: .expense).filter { !$0.isLeaf }.map(\.id)
        let order = Array(parents.reversed())
        repository.fails = true
        XCTAssertFalse(state.perform { try state.store.reorderCategories(ledgerID: ledger.id, kind: .expense, parentID: nil, orderedIDs: order) })
        XCTAssertEqual(state.store.categories(in: ledger.id, kind: .expense).filter { !$0.isLeaf }.map(\.id), parents)
        repository.fails = false
        XCTAssertTrue(state.perform { try state.store.reorderCategories(ledgerID: ledger.id, kind: .expense, parentID: nil, orderedIDs: order) })
        let reloaded = AppState(repository: repository)
        XCTAssertEqual(reloaded.store.categories(in: ledger.id, kind: .expense).filter { !$0.isLeaf }.map(\.id), order)
    }

    func testWriteFailureDoesNotReportSuccessOrChangeLedger() throws {
        let repository = Repository()
        let state = AppState(repository: repository)
        let ledger = try XCTUnwrap(state.activeLedger)
        repository.fails = true
        let result = state.perform("已改名") {
            try state.store.renameLedger(ledger.id, name: "未写入的修改")
        }
        XCTAssertFalse(result)
        XCTAssertEqual(state.activeLedger?.name, ledger.name)
        XCTAssertEqual(repository.saved?.ledgers.first?.name, ledger.name)
        XCTAssertNotNil(state.alertError)
        XCTAssertNil(state.toast)
    }

    func testBudgetsRollBackWithCreateAndPersistWithRestore() throws {
        let repository = Repository(); let state = AppState(repository: repository)
        let original = try XCTUnwrap(state.activeLedger?.id)
        repository.fails = true
        XCTAssertFalse(state.createAndSwitchLedger(name: "预算账本", monthlyBudget: 10_000, yearlyBudget: 100_000))
        XCTAssertEqual(state.activeLedger?.id, original)
        XCTAssertEqual(state.store.data.ledgers.count, 1)
        repository.fails = false
        XCTAssertTrue(state.createAndSwitchLedger(name: "预算账本", monthlyBudget: 10_000, yearlyBudget: 100_000))
        let id = try XCTUnwrap(state.activeLedger?.id)
        repository.fails = true
        XCTAssertFalse(state.perform { try state.store.setBudgets(ledgerID: id, monthly: 20_000, yearly: nil, effective: state.today) })
        XCTAssertEqual(state.store.budgetLimit(in: id, period: .month, containing: state.today), 10_000)
        let loaded = AppState(repository: repository)
        XCTAssertEqual(loaded.store.budgetLimit(in: id, period: .year, containing: loaded.today), 100_000)
    }

    func testPartialActionRollsBackWhenLaterOperationFails() throws {
        let state = AppState(repository: Repository())
        let before = state.store.data.ledgers.count
        XCTAssertFalse(state.perform {
            _ = try state.store.createLedger(name: "应撤回")
            throw CocoaError(.fileWriteUnknown)
        })
        XCTAssertEqual(state.store.data.ledgers.count, before)
    }

    func testRetryAfterFailurePersistsAndReloads() throws {
        let repository = Repository()
        let state = AppState(repository: repository)
        let id = try XCTUnwrap(state.activeLedger?.id)
        repository.fails = true
        XCTAssertFalse(state.perform { try state.store.renameLedger(id, name: "旅行") })
        repository.fails = false
        XCTAssertTrue(state.perform { try state.store.renameLedger(id, name: "旅行") })
        XCTAssertEqual(AppState(repository: repository).activeLedger?.name, "旅行")
    }

    func testCreateAndSwitchLedgerIsAtomicAndReloadsSelection() throws {
        let repository = Repository(); let state = AppState(repository: repository)
        let original = try XCTUnwrap(state.activeLedger?.id)
        let before = state.store.data
        repository.fails = true
        XCTAssertFalse(state.createAndSwitchLedger(name: "旅行"))
        XCTAssertEqual(state.activeLedger?.id, original)
        XCTAssertEqual(state.store.data.ledgers.count, before.ledgers.count)
        XCTAssertEqual(state.store.data.accounts.count, before.accounts.count)
        repository.fails = false
        XCTAssertTrue(state.createAndSwitchLedger(name: "旅行"))
        let reloaded = AppState(repository: repository)
        XCTAssertEqual(reloaded.activeLedger?.name, "旅行")
        XCTAssertNotEqual(reloaded.activeLedger?.id, original)
    }

    func testDayRefreshIncludesNewDayTransactionsWithoutRelaunch() throws {
        let state = AppState(repository: Repository(), clockDay: Day(year: 2026, month: 9, day: 9))
        let ledger = try XCTUnwrap(state.activeLedger)
        let account = try XCTUnwrap(state.store.accounts(in: ledger.id).first)
        let category = try XCTUnwrap(state.store.categories(in: ledger.id, kind: .expense).first(where: \.isLeaf))
        let nextDay = Day(year: 2026, month: 9, day: 10)
        XCTAssertTrue(state.addExpense(expression: "90", date: nextDay, accountID: account.id,
                                       categoryID: category.id, tagIDs: [], note: "跨日回归",
                                       ledgerID: ledger.id, kind: .expense, amountCents: 9000))
        XCTAssertEqual(state.stats(for: ledger.id).summary(range: state.currentMonth.prefix(through: state.today.day)).netExpense, 0)
        state.refreshToday(now: nextDay.date())
        XCTAssertEqual(state.stats(for: ledger.id).summary(range: state.currentMonth.prefix(through: state.today.day)).netExpense, 9000)
        state.refreshToday(now: Day(year: 2026, month: 10, day: 1).date())
        XCTAssertEqual(state.currentMonth, MonthKey(year: 2026, month: 10))
        XCTAssertEqual(state.store.activeTransactions(in: ledger.id).count, 1)
    }
}

@MainActor
final class DiskPersistenceTests: XCTestCase {
    func testRecoveryPointRemovalOnlyDeletesTheSelectedManagedCopy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = JSONFileRepository(url: directory.appendingPathComponent("ledger.json"))
        let state = AppState(repository: repository)
        let backup = try XCTUnwrap(state.exportBackup())
        XCTAssertTrue(state.restoreBackup(backup)); XCTAssertTrue(state.restoreBackup(backup))
        XCTAssertEqual(state.recoveryPoints.count, 2)
        let old = try XCTUnwrap(state.recoveryPoints.first { $0.url != state.recoveryBackupURL })
        let mainBytes = try Data(contentsOf: repository.url)
        let latest = try XCTUnwrap(state.recoveryBackupURL)
        XCTAssertTrue(state.removeRecoveryPoint(old))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: latest.path))
        XCTAssertEqual(try Data(contentsOf: repository.url), mainBytes)
        let fake = AppState.RecoveryPoint(url: repository.url, createdAt: Date(), bytes: 0, unreadable: false)
        XCTAssertFalse(state.removeRecoveryPoint(fake))
        let link = try XCTUnwrap(state.recoveryDirectory).appendingPathComponent(UUID().uuidString + ".json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: repository.url)
        XCTAssertEqual(state.recoveryPoints.count, 1, "A symlink cannot turn the current ledger into a managed recovery point")
        let linked = AppState.RecoveryPoint(url: link, createdAt: Date(), bytes: 0, unreadable: false)
        XCTAssertFalse(state.removeRecoveryPoint(linked))
        XCTAssertEqual(try Data(contentsOf: repository.url), mainBytes)
        let final = try XCTUnwrap(state.recoveryPoints.first)
        XCTAssertTrue(state.removeRecoveryPoint(final))
        XCTAssertTrue(state.recoveryPoints.isEmpty)
        XCTAssertNil(AppState(repository: repository).recoveryBackupURL)
    }
    func testBackupPreviewIsReadOnlyAndRestoreKeepsARecoverableSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = JSONFileRepository(url: directory.appendingPathComponent("ledger.json"))
        let state = AppState(repository: repository)
        let ledger = try XCTUnwrap(state.activeLedger)
        let backup = try XCTUnwrap(state.exportBackup())
        XCTAssertNil(state.store.data.lastBackupAt, "Encoding alone does not prove a file was generated")
        XCTAssertTrue(state.perform { try state.store.renameLedger(ledger.id, name: "恢复前的工作") })
        let before = try Data(contentsOf: repository.url)
        _ = try BackupService.validate(backup: BackupService.decode(backup))
        XCTAssertEqual(try Data(contentsOf: repository.url), before, "Preview/cancel cannot mutate the store")
        XCTAssertTrue(state.restoreBackup(backup))
        XCTAssertEqual(state.activeLedger?.name, ledger.name)
        let recovery = try Data(contentsOf: XCTUnwrap(state.recoveryBackupURL))
        XCTAssertEqual(try BackupService.decode(recovery).data.ledgers.first?.name, "恢复前的工作")
        XCTAssertTrue(state.restoreBackup(recovery))
        XCTAssertEqual(AppState(repository: repository).activeLedger?.name, "恢复前的工作")
    }

    func testRestoreStopsIfRecoveryFileCannotBeWritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = JSONFileRepository(url: directory.appendingPathComponent("ledger.json"))
        let state = AppState(repository: repository)
        let backup = try XCTUnwrap(state.exportBackup())
        let before = try Data(contentsOf: repository.url)
        try Data("blocked".utf8).write(to: XCTUnwrap(state.recoveryDirectory))
        XCTAssertFalse(state.restoreBackup(backup))
        XCTAssertEqual(try Data(contentsOf: repository.url), before)
        XCTAssertNotNil(state.alertError)
    }

    func testFailedMainWritePreservesThePreviousRecoveryPoint() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = JSONFileRepository(url: directory.appendingPathComponent("ledger.json"))
        let state = AppState(repository: repository)
        let ledger = try XCTUnwrap(state.activeLedger)
        let backup = try XCTUnwrap(state.exportBackup())
        XCTAssertTrue(state.perform { try state.store.renameLedger(ledger.id, name: "首次替换前") })
        XCTAssertTrue(state.restoreBackup(backup))
        let previousURL = try XCTUnwrap(state.recoveryBackupURL)
        let previousBytes = try Data(contentsOf: previousURL)
        XCTAssertTrue(state.perform { try state.store.renameLedger(ledger.id, name: "当前工作") })

        // The existing recovery subdirectory stays writable, while the main
        // directory cannot create the temporary file used for atomic replacement.
        let currentBytes = try Data(contentsOf: repository.url)
        let countBefore = try FileManager.default.contentsOfDirectory(atPath: XCTUnwrap(state.recoveryDirectory).path).count
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        XCTAssertFalse(state.restoreBackup(backup))
        XCTAssertEqual(state.activeLedger?.name, "当前工作")
        XCTAssertEqual(state.recoveryBackupURL, previousURL)
        XCTAssertEqual(try Data(contentsOf: previousURL), previousBytes)
        XCTAssertEqual(try Data(contentsOf: repository.url), currentBytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: XCTUnwrap(state.recoveryDirectory).path).count, countBefore + 1)
        XCTAssertNotNil(state.alertError)
    }

    func testActualDiskSaveReplacementAndReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = JSONFileRepository(url: directory.appendingPathComponent("ledger.json"))
        let state = AppState(repository: repository)
        let ledger = try XCTUnwrap(state.activeLedger)
        let account = try XCTUnwrap(state.store.accounts(in: ledger.id).first)
        let category = try XCTUnwrap(state.store.categories(in: ledger.id, kind: .expense).first(where: \.isLeaf))
        let saved = state.addExpense(expression: "(28+16)*2", date: state.today, accountID: account.id,
                                     categoryID: category.id, tagIDs: [], note: "本地落盘验收", ledgerID: ledger.id,
                                     kind: .expense, amountCents: 8800)
        XCTAssertTrue(saved)
        let reloaded = AppState(repository: repository)
        XCTAssertEqual(reloaded.store.activeTransactions(in: ledger.id).count, 1)
        XCTAssertEqual(reloaded.store.balance(accountID: account.id), -8800)
        let bytes = try XCTUnwrap(reloaded.exportBackup())
        XCTAssertTrue(state.restoreBackup(bytes))
        XCTAssertEqual(AppState(repository: repository).store.balance(accountID: account.id), -8800)
    }
}
