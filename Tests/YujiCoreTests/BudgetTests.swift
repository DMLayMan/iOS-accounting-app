import XCTest
@testable import YujiCore

final class BudgetTests: XCTestCase {
    private let september = Day(year: 2026, month: 9, day: 10)
    private func fixture() throws -> LedgerStore {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return LedgerStore(data: try XCTUnwrap(JSONFileRepository(url: root.appendingPathComponent("Fixtures/stats-500.json")).load()))
    }
    func testRecurringBudgetsAreIndependentAndPreserveEarlierPeriods() throws {
        let s = try fixture()
        try s.setBudgets(ledgerID: "stress", monthly: 100_000, yearly: 500_000, effective: september)
        XCTAssertEqual(s.budgetLimit(in: "stress", period: .month, containing: september), 100_000)
        XCTAssertEqual(s.budgetLimit(in: "stress", period: .year, containing: september), 500_000)
        XCTAssertNil(s.budgetLimit(in: "stress", period: .month, containing: Day(year: 2026, month: 8, day: 1)))
        let october = Day(year: 2026, month: 10, day: 1)
        try s.setBudgets(ledgerID: "stress", monthly: 200_000, yearly: 500_000, effective: october)
        XCTAssertEqual(s.budgetLimit(in: "stress", period: .month, containing: september), 100_000)
        XCTAssertEqual(s.budgetLimit(in: "stress", period: .month, containing: october), 200_000)
        XCTAssertEqual(s.budgetLimit(in: "stress", period: .year, containing: Day(year: 2027, month: 1, day: 1)), 500_000)
        try s.setBudgets(ledgerID: "stress", monthly: nil, yearly: 500_000, effective: october)
        XCTAssertNil(s.budgetLimit(in: "stress", period: .month, containing: october))
        XCTAssertEqual(s.budgetLimit(in: "stress", period: .month, containing: september), 100_000)
    }
    func testMonthlyNetExpenseAndZeroBudgetNeverDivideByZero() throws {
        let s = try fixture()
        try s.setBudgets(ledgerID: "stress", monthly: 100_000, yearly: nil, effective: september)
        let snap = s.budget(in: "stress", period: .month, containing: september, through: september)
        XCTAssertEqual(snap.spent, 50_105); XCTAssertEqual(snap.remaining, 49_895)
        XCTAssertEqual(snap.progress, 0.50105, accuracy: 0.00001)
        try s.setBudgets(ledgerID: "stress", monthly: 0, yearly: nil, effective: september)
        let zero = s.budget(in: "stress", period: .month, containing: september, through: september)
        XCTAssertEqual(zero.remaining, -50_105); XCTAssertEqual(zero.progress, 1)
    }
    func testRefundOnlyMonthRestoresAllowanceWithoutNegativeProgress() throws {
        let s = try fixture(); let jan = Day(year: 2023, month: 1, day: 31)
        try s.setBudgets(ledgerID: "stress", monthly: 100_000, yearly: nil, effective: jan)
        let snap = s.budget(in: "stress", period: .month, containing: jan, through: jan)
        XCTAssertEqual(snap.spent, -1_200_000); XCTAssertEqual(snap.remaining, 1_300_000); XCTAssertEqual(snap.progress, 0)
    }
    func testEntryPreviewReplacesOriginalWithoutSavingOrDoubleCounting() throws {
        let s = try fixture()
        try s.setBudgets(ledgerID: "stress", monthly: 100_000, yearly: nil, effective: september)
        let preview = BudgetEntryPreview(kind: .expense, cents: 20_000, date: september, replacingID: "tx-003")
        let snap = s.budget(in: "stress", period: .month, containing: september, through: september, preview: preview)
        XCTAssertEqual(snap.spent, 60_106)
        XCTAssertEqual(s.transaction("tx-003")?.amountCents, 9_999)
        let income = BudgetEntryPreview(kind: .income, cents: 20_000, date: september, replacingID: "tx-003")
        XCTAssertEqual(s.budget(in: "stress", period: .month, containing: september, through: september, preview: income).spent, 40_106)
        let moved = BudgetEntryPreview(kind: .expense, cents: 20_000, date: Day(year: 2026, month: 10, day: 1), replacingID: "tx-003")
        XCTAssertEqual(s.budget(in: "stress", period: .month, containing: september, through: september, preview: moved).spent, 40_106)
    }
    func testLedgerIsolationYearTotalsAndInvalidBudgetIsAtomic() throws {
        let s = try fixture()
        try s.setBudgets(ledgerID: "stress", monthly: 100_000, yearly: 10_000_000, effective: september)
        let year = s.budget(in: "stress", period: .year, containing: september, through: september)
        let summary = StatsEngine(store: s, ledgerID: "stress").summary(range: Day(year: 2026, month: 1, day: 1)...september)
        XCTAssertEqual(year.spent, summary.netExpense)
        let before = s.ledger("stress")?.budgetRules
        XCTAssertThrowsError(try s.setBudgets(ledgerID: "stress", monthly: 200_000, yearly: -1, effective: september))
        XCTAssertEqual(s.ledger("stress")?.budgetRules, before)
        let other = try s.createLedger(name: "独立")
        XCTAssertNil(s.budgetLimit(in: other.id, period: .month, containing: september))
    }
    func testLegacyDecodeAndBudgetBackupRoundTrip() throws {
        let s = try fixture(); XCTAssertNil(s.ledger("stress")?.budgetRules)
        try s.setBudgets(ledgerID: "stress", monthly: 123_456, yearly: 654_321, effective: september)
        let backup = try BackupService.makeBackup(from: s)
        let restored = try BackupService.validate(backup: BackupService.decode(BackupService.encode(backup)))
        XCTAssertEqual(LedgerStore(data: restored).budgetLimit(in: "stress", period: .month, containing: september), 123_456)
        XCTAssertEqual(backup.formatVersion, LedgerData.currentSchemaVersion)
        var invalid = backup
        invalid.data.ledgers[0].budgetRules = [BudgetRule(period: .month, effectiveFrom: september, limit: -1)]
        XCTAssertThrowsError(try BackupService.validate(backup: invalid))
    }
    func testBudgetInputRejectsMalformedPrecisionAndHugeValues() throws {
        XCTAssertNil(try BudgetInput.parse("  "))
        XCTAssertEqual(try BudgetInput.parse("0"), 0)
        XCTAssertEqual(try BudgetInput.parse("123.45"), 12_345)
        for invalid in ["-1", "abc", "1.234", "1,23", "999999999999999999999"] {
            XCTAssertThrowsError(try BudgetInput.parse(invalid))
        }
    }
}
