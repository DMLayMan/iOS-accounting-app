import XCTest
@testable import YujiCore

final class CategoryBudgetTests: XCTestCase {
    private let day = Day(year: 2026, month: 9, day: 10)
    private func setup() throws -> (LedgerStore, Ledger, Account, CategoryNode, CategoryNode, CategoryNode) {
        let store = LedgerStore(); let ledger = try store.createLedger(name: "分类预算", startDay: day)
        let account = try XCTUnwrap(store.accounts(in: ledger.id).first)
        let group = try store.createCategory(ledgerID: ledger.id, kind: .expense, parentID: nil, name: "测试餐饮")
        let a = try store.createCategory(ledgerID: ledger.id, kind: .expense, parentID: group.id, name: "咖啡")
        let b = try store.createCategory(ledgerID: ledger.id, kind: .expense, parentID: group.id, name: "午餐")
        return (store, ledger, account, group, a, b)
    }

    func testParentAndChildBudgetsOverlapWithoutChangingLedgerTotal() throws {
        let (s,l,a,p,c,b) = try setup()
        try s.addTransaction(Transaction(ledgerID: l.id, kind: .expense, amountCents: 8_000, date: day, accountID: a.id, categoryID: c.id))
        try s.addTransaction(Transaction(ledgerID: l.id, kind: .expense, amountCents: 2_000, date: day, accountID: a.id, categoryID: b.id))
        try s.setBudgets(ledgerID: l.id, monthly: 20_000, yearly: 100_000, effective: day)
        try s.setCategoryBudgets(ledgerID: l.id, limits: [.init(period: .month, categoryID: p.id, limit: 9_000), .init(period: .month, categoryID: c.id, limit: 5_000), .init(period: .year, categoryID: c.id, limit: 50_000)], effective: day)
        let rows = s.categoryBudgets(in: l.id, period: .month, containing: day, through: day)
        XCTAssertEqual(rows.map(\.categoryID), [c.id,p.id]); XCTAssertEqual(rows.map(\.overrun), [3_000,1_000])
        XCTAssertEqual(s.budget(in: l.id, period: .month, containing: day, through: day).remaining, 10_000)
        XCTAssertEqual(s.categoryBudgets(in: l.id, period: .year, containing: day, through: day).first?.snapshot.remaining, 42_000)
        try s.setBudgets(ledgerID: l.id, monthly: 30_000, yearly: nil, effective: day)
        XCTAssertEqual(s.categoryBudgetLimits(in: l.id, containing: day).count, 3)
    }

    func testRuleRemovalAndAmountChangePreserveEarlierPeriods() throws {
        let (s,l,_,_,c,_) = try setup()
        try s.setCategoryBudgets(ledgerID: l.id, limits: [.init(period: .month, categoryID: c.id, limit: 100), .init(period: .year, categoryID: c.id, limit: 500)], effective: day)
        let october = Day(year: 2026, month: 10, day: 2)
        try s.setCategoryBudgets(ledgerID: l.id, limits: [.init(period: .year, categoryID: c.id, limit: 800)], effective: october)
        XCTAssertEqual(s.budgetLimit(in: l.id, period: .month, containing: day, categoryID: c.id), 100)
        XCTAssertNil(s.budgetLimit(in: l.id, period: .month, containing: october, categoryID: c.id))
        XCTAssertEqual(s.budgetLimit(in: l.id, period: .year, containing: day, categoryID: c.id), 800)
        try s.setCategoryBudgets(ledgerID: l.id, limits: [], effective: Day(year: 2027, month: 1, day: 1))
        XCTAssertEqual(s.budgetLimit(in: l.id, period: .year, containing: day, categoryID: c.id), 800)
        XCTAssertThrowsError(try s.deleteCategory(c.id))
        try s.archiveCategory(c.id, archived: true)
        XCTAssertNotNil(s.category(c.id))
    }

    func testPreviewMovesExpenseBetweenCategoriesWithoutDoubleCounting() throws {
        let (s,l,a,p,c,b) = try setup()
        let t = Transaction(ledgerID: l.id, kind: .expense, amountCents: 8_000, date: day, accountID: a.id, categoryID: c.id)
        try s.addTransaction(t)
        try s.setCategoryBudgets(ledgerID: l.id, limits: [.init(period: .month, categoryID: p.id, limit: 10_000), .init(period: .month, categoryID: c.id, limit: 5_000), .init(period: .month, categoryID: b.id, limit: 4_000)], effective: day)
        let preview = BudgetEntryPreview(kind: .expense, cents: 6_000, date: day, replacingID: t.id, categoryID: b.id)
        let rows = s.categoryBudgets(in: l.id, containing: day, through: day, preview: preview, matching: b.id)
        XCTAssertEqual(Set(rows.map(\.categoryID)), Set([p.id,b.id]))
        XCTAssertEqual(rows.first?.overrun, 2_000)
        XCTAssertEqual(s.budget(in: l.id, period: .month, containing: day, through: day, preview: preview, categoryID: c.id).spent, 0)
        XCTAssertEqual(s.transaction(t.id)?.amountCents, 8_000)
    }

    func testRefundUsesOriginalCategoryAndRefundDate() throws {
        let (s,l,a,p,c,_) = try setup()
        let t = Transaction(ledgerID: l.id, kind: .expense, amountCents: 8_000, date: day, accountID: a.id, categoryID: c.id)
        try s.addTransaction(t)
        let october = Day(year: 2026, month: 10, day: 2)
        try s.setCategoryBudgets(ledgerID: l.id, limits: [.init(period: .month, categoryID: p.id, limit: 0)], effective: day)
        try s.addTransaction(Transaction(ledgerID: l.id, kind: .refund, amountCents: 3_000, date: october, accountID: a.id, originalExpenseID: t.id))
        let row = try XCTUnwrap(s.categoryBudgets(in: l.id, containing: october, through: october).first)
        XCTAssertEqual(row.snapshot.spent, -3_000); XCTAssertEqual(row.snapshot.remaining, 3_000); XCTAssertEqual(row.snapshot.progress, 0)
    }

    func testInvalidAndDuplicateRulesAreAtomicAndLedgerIsolated() throws {
        let (s,l,_,_,c,_) = try setup()
        let rule = CategoryBudgetLimit(period: .month, categoryID: c.id, limit: 0)
        try s.setCategoryBudgets(ledgerID: l.id, limits: [rule], effective: day)
        let before = s.ledger(l.id)?.budgetRules
        XCTAssertThrowsError(try s.setCategoryBudgets(ledgerID: l.id, limits: [rule,rule], effective: day))
        XCTAssertThrowsError(try s.setCategoryBudgets(ledgerID: l.id, limits: [.init(period: .year, categoryID: c.id, limit: -1)], effective: day))
        let other = try s.createLedger(name: "其他")
        XCTAssertThrowsError(try s.setCategoryBudgets(ledgerID: other.id, limits: [rule], effective: day))
        XCTAssertEqual(s.ledger(l.id)?.budgetRules, before)
        XCTAssertTrue(s.categoryBudgets(in: other.id, containing: day, through: day).isEmpty)
        try s.archiveCategory(c.id, archived: true)
        XCTAssertNoThrow(try s.setCategoryBudgets(ledgerID: l.id, limits: [rule], effective: day))
        XCTAssertThrowsError(try s.setCategoryBudgets(ledgerID: l.id, limits: [rule, .init(period: .year, categoryID: c.id, limit: 100)], effective: day))
    }

    func testManyRulesAndBackupRoundTripWithReferenceValidation() throws {
        let (s,l,_,p,_,_) = try setup()
        var rules: [CategoryBudgetLimit] = []
        for i in 0..<32 {
            let c = try s.createCategory(ledgerID: l.id, kind: .expense, parentID: p.id, name: "项目\(i)")
            rules.append(.init(period: .month, categoryID: c.id, limit: Int64(i)))
        }
        try s.setCategoryBudgets(ledgerID: l.id, limits: rules, effective: day)
        let backup = try BackupService.makeBackup(from: s)
        XCTAssertEqual(backup.formatVersion, 3)
        let restored = LedgerStore(data: try BackupService.validate(backup: BackupService.decode(BackupService.encode(backup))))
        XCTAssertEqual(restored.categoryBudgetLimits(in: l.id, containing: day).count, 32)
        var bad = backup
        bad.data.ledgers[0].budgetRules?[0].categoryID = "missing"
        XCTAssertThrowsError(try BackupService.validate(backup: bad))
        try s.setCategoryBudgets(ledgerID: l.id, limits: [], effective: day)
        XCTAssertTrue(s.categoryBudgetLimits(in: l.id, containing: day).isEmpty)
    }

    func testV2WholeLedgerBudgetStillDecodesWithoutCategoryScope() throws {
        let (s,l,_,_,_,_) = try setup()
        try s.setBudgets(ledgerID: l.id, monthly: 123_456, yearly: 987_654, effective: day)
        var backup = try BackupService.makeBackup(from: s)
        backup.formatVersion = 2; backup.data.schemaVersion = 2
        let decoded = try BackupService.decode(BackupService.encode(backup))
        let restored = LedgerStore(data: try BackupService.validate(backup: decoded))
        XCTAssertEqual(restored.budgetLimit(in: l.id, period: .month, containing: day), 123_456)
        XCTAssertEqual(restored.budgetLimit(in: l.id, period: .year, containing: day), 987_654)
        XCTAssertTrue(restored.categoryBudgetLimits(in: l.id, containing: day).isEmpty)
    }
}
