import XCTest
@testable import YujiCore

/// 测试世界：快速构造账本/账户/分类并提供便捷记账方法。
final class World {
    let store: LedgerStore
    let ledger: Ledger
    var cash: Account!      // 现金
    var wallet: Account!    // 钱包/银行卡
    var expBreakfast: CategoryNode!  // 餐饮→早餐
    var expTransport: CategoryNode!  // 出行→公共交通
    var incSalary: CategoryNode!     // 工作收入→工资
    var tagTravel: TagNode!          // 项目→青岛旅行（叶子）
    var tagSelf: TagNode!            // 对象→自己（叶子）

    init(ledgerName: String = "个人账本", openingCash: Int64 = 0, openingWallet: Int64 = 0,
         startDay: Day = Day(year: 2020, month: 1, day: 1)) {
        store = LedgerStore()
        ledger = try! store.createLedger(name: ledgerName)
        // 默认种子已含 现金/银行卡 与分类；这里按测试需要重设期初。
        cash = store.accounts(in: ledger.id).first { $0.name == "现金" }!
        wallet = store.accounts(in: ledger.id).first { $0.name == "银行卡" }!
        try! store.updateAccountOpening(cash.id, openingCents: openingCash, startDay: startDay)
        try! store.updateAccountOpening(wallet.id, openingCents: openingWallet, startDay: startDay)

        let expCats = store.categories(in: ledger.id, kind: .expense)
        let mealParent = expCats.first { $0.name == "餐饮" }!
        let travelParent = expCats.first { $0.name == "出行" }!
        expBreakfast = store.categories(in: ledger.id, kind: .expense).first { $0.parentID == mealParent.id && $0.name == "早餐" }!
        expTransport = store.categories(in: ledger.id, kind: .expense).first { $0.parentID == travelParent.id && $0.name == "公共交通" }!
        let incCats = store.categories(in: ledger.id, kind: .income)
        let salaryParent = incCats.first { $0.name == "工作收入" }!
        incSalary = store.categories(in: ledger.id, kind: .income).first { $0.parentID == salaryParent.id && $0.name == "工资" }!

        // 标签：项目→青岛旅行；对象→自己
        let projParent = store.tags(in: ledger.id).first { $0.name == "项目" }!
        tagTravel = try! store.createTag(ledgerID: ledger.id, parentID: projParent.id, name: "青岛旅行")
        let objParent = store.tags(in: ledger.id).first { $0.name == "对象" }!
        tagSelf = store.tags(in: ledger.id).first { $0.parentID == objParent.id && $0.name == "自己" }!
    }

    @discardableResult
    func expense(_ cents: Int64, account: Account, category: CategoryNode, date: Day,
                 tags: [EntityID] = [], note: String = "", op: String = UUID().uuidString) -> Transaction {
        let t = Transaction(ledgerID: ledger.id, operationID: op, kind: .expense, amountCents: cents,
                            date: date, accountID: account.id, categoryID: category.id, tagIDs: tags, note: note)
        return try! store.addTransaction(t)
    }

    @discardableResult
    func income(_ cents: Int64, account: Account, category: CategoryNode, date: Day,
                op: String = UUID().uuidString) -> Transaction {
        let t = Transaction(ledgerID: ledger.id, operationID: op, kind: .income, amountCents: cents,
                            date: date, accountID: account.id, categoryID: category.id)
        return try! store.addTransaction(t)
    }

    @discardableResult
    func transfer(_ cents: Int64, from: Account, to: Account, date: Day,
                  op: String = UUID().uuidString) -> Transaction {
        let t = Transaction(ledgerID: ledger.id, operationID: op, kind: .transfer, amountCents: cents,
                            date: date, accountID: from.id, transferToAccountID: to.id)
        return try! store.addTransaction(t)
    }

    @discardableResult
    func refund(_ cents: Int64, of expense: Transaction, to account: Account, date: Day,
                op: String = UUID().uuidString) -> Transaction {
        let t = Transaction(ledgerID: ledger.id, operationID: op, kind: .refund, amountCents: cents,
                            date: date, accountID: account.id, originalExpenseID: expense.id)
        return try! store.addTransaction(t)
    }

    var stats: StatsEngine { StatsEngine(store: store, ledgerID: ledger.id) }
}

/// PRD §12 独立验收样本。
final class DomainAcceptanceTests: XCTestCase {

    // 样本：基础余额
    func testBasicBalances() {
        let w = World(openingCash: 100_000, openingWallet: 50_000)  // 现金1000、钱包500
        let d = Day(year: 2026, month: 9, day: 1)
        let e = w.expense(2_800, account: w.wallet, category: w.expBreakfast, date: d)      // 钱包支出28
        w.transfer(10_000, from: w.cash, to: w.wallet, date: d)                            // 现金转钱包100
        w.income(200_000, account: w.wallet, category: w.incSalary, date: d)               // 钱包收入2000
        w.refund(800, of: e, to: w.wallet, date: d)                                        // 退款8到钱包

        XCTAssertEqual(w.store.balance(accountID: w.cash.id), 90_000)      // 现金900
        XCTAssertEqual(w.store.balance(accountID: w.wallet.id), 258_000)   // 钱包2580
        let s = w.stats.monthSummary(MonthKey(year: 2026, month: 9))
        XCTAssertEqual(s.expense, 2_800)     // 消费28
        XCTAssertEqual(s.refund, 800)        // 退款8
        XCTAssertEqual(s.netExpense, 2_000)  // 净支出20
        XCTAssertEqual(s.income, 200_000)    // 收入2000
    }

    // 样本：编辑与退款上限
    func testEditAndRefundCap() {
        let w = World(openingCash: 100_000, openingWallet: 50_000)
        let d = Day(year: 2026, month: 9, day: 1)
        let e = w.expense(2_800, account: w.wallet, category: w.expBreakfast, date: d)
        w.transfer(10_000, from: w.cash, to: w.wallet, date: d)
        w.income(200_000, account: w.wallet, category: w.incSalary, date: d)
        w.refund(800, of: e, to: w.wallet, date: d)

        // 原支出 28 改 30
        try! w.store.updateTransaction(e.id) { $0.amountCents = 3_000 }
        XCTAssertEqual(w.store.balance(accountID: w.wallet.id), 257_800)  // 钱包2578
        XCTAssertEqual(w.stats.monthSummary(MonthKey(year: 2026, month: 9)).netExpense, 2_200) // 净22

        // 再尝试改 5（低于已退 8）→ 失败，全部值不变
        XCTAssertThrowsError(try w.store.updateTransaction(e.id) { $0.amountCents = 500 }) { err in
            XCTAssertEqual(err as? DomainError, .expenseHasRefundsCannotChangeAmount)
        }
        XCTAssertEqual(w.store.balance(accountID: w.wallet.id), 257_800)
        XCTAssertEqual(w.store.transaction(e.id)!.amountCents, 3_000)
    }

    // 样本：转账删除恢复（整体）
    func testTransferDeleteRestore() {
        let w = World(openingCash: 100_000, openingWallet: 50_000)
        let d = Day(year: 2026, month: 9, day: 1)
        let t = w.transfer(10_000, from: w.cash, to: w.wallet, date: d)
        XCTAssertEqual(w.store.balance(accountID: w.cash.id), 90_000)
        XCTAssertEqual(w.store.balance(accountID: w.wallet.id), 60_000)

        // 删除：两账户同时回退
        try! w.store.deleteTransaction(t.id)
        XCTAssertEqual(w.store.balance(accountID: w.cash.id), 100_000)
        XCTAssertEqual(w.store.balance(accountID: w.wallet.id), 50_000)
        // 收支统计始终不含转账
        let s = w.stats.monthSummary(MonthKey(year: 2026, month: 9))
        XCTAssertEqual(s.expense, 0); XCTAssertEqual(s.income, 0); XCTAssertEqual(s.netExpense, 0)

        // 恢复：两账户同时恢复；重复恢复幂等
        try! w.store.restoreTransaction(t.id)
        try! w.store.restoreTransaction(t.id)
        XCTAssertEqual(w.store.balance(accountID: w.cash.id), 90_000)
        XCTAssertEqual(w.store.balance(accountID: w.wallet.id), 60_000)
    }

    // 样本：跨月退款
    func testCrossMonthRefund() {
        let w = World()
        let aug = Day(year: 2026, month: 8, day: 15)
        let sep = Day(year: 2026, month: 9, day: 5)
        let augExpense = w.expense(10_000, account: w.wallet, category: w.expBreakfast, date: aug) // 8月支出100
        w.expense(2_000, account: w.wallet, category: w.expTransport, date: sep)                    // 9月消费20
        w.refund(10_000, of: augExpense, to: w.wallet, date: sep)                                   // 9月退原支出100

        let augS = w.stats.monthSummary(MonthKey(year: 2026, month: 8))
        XCTAssertEqual(augS.netExpense, 10_000)   // 8月净100
        let sepS = w.stats.monthSummary(MonthKey(year: 2026, month: 9))
        XCTAssertEqual(sepS.expense, 2_000)       // 9月消费20
        XCTAssertEqual(sepS.refund, 10_000)       // 退款100
        XCTAssertEqual(sepS.netExpense, -8_000)   // 净支出 −80
    }

    // 样本：分类守恒
    func testCategoryConservation() {
        let w = World()
        let d = Day(year: 2026, month: 9, day: 1)
        w.expense(6_000, account: w.wallet, category: w.expBreakfast, date: d)
        w.expense(4_000, account: w.wallet, category: w.expTransport, date: d)
        let items = w.stats.categoryBreakdown(range: MonthKey(year: 2026, month: 9).fullRange)
        let total = items.reduce(0) { $0 + $1.net }
        XCTAssertEqual(total, 10_000)  // 叶子合计=总额
    }

    // 样本：标签重叠（去重，不相加）
    func testTagOverlapDedup() {
        let w = World()
        let d = Day(year: 2026, month: 9, day: 1)
        let e = w.expense(10_000, account: w.wallet, category: w.expBreakfast, date: d,
                          tags: [w.tagTravel.id, w.tagSelf.id])   // 同时两标签
        w.refund(2_000, of: e, to: w.wallet, date: d)             // 退款归属原支出标签

        let range = MonthKey(year: 2026, month: 9).fullRange
        let items = w.stats.tagBreakdown(range: range)
        let travel = items.first { $0.id == w.tagTravel.id }!
        let self_ = items.first { $0.id == w.tagSelf.id }!
        XCTAssertEqual(travel.net, 8_000)   // 各净80
        XCTAssertEqual(self_.net, 8_000)
        // 父级（对象 / 项目）并集去重后仍为 80，不是 160
        let objParent = w.store.tag(w.tagSelf.parentID)!
        XCTAssertEqual(w.stats.parentTagNet(parentID: objParent.id, range: range), 8_000)
        let projParent = w.store.tag(w.tagTravel.parentID)!
        XCTAssertEqual(w.stats.parentTagNet(parentID: projParent.id, range: range), 8_000)
    }

    // 样本：部分月比较（环比同进度，不拿整月比）
    func testPartialMonthMoM() {
        let w = World()
        // 8月1-9日净60，8月10日另有240（使整月=300）
        for day in 1...9 {
            w.expense(667, account: w.wallet, category: w.expBreakfast, date: Day(year: 2026, month: 8, day: day)) // ~60
        }
        w.expense(24_000, account: w.wallet, category: w.expBreakfast, date: Day(year: 2026, month: 8, day: 20)) // 8月整月更大
        // 9月1-9日净90
        for day in 1...9 {
            w.expense(1_000, account: w.wallet, category: w.expBreakfast, date: Day(year: 2026, month: 9, day: day))
        }
        let today = Day(year: 2026, month: 9, day: 9)
        let mom = w.stats.momComparison(for: MonthKey(year: 2026, month: 9), today: today)
        // 环比基期是 8月1-9（约60），不是 8月整月（300）
        XCTAssertEqual(mom.base, 9 * 667)
        XCTAssertEqual(mom.current, 9_000)
        XCTAssertEqual(mom.delta, 9_000 - 9 * 667)
        XCTAssertNotNil(mom.percent)  // 基期>0，有百分比
    }

    // 样本：基期零/负 → 不显示百分比
    func testBaseZeroAndNegative() {
        // 基期 0
        let w1 = World()
        let today = Day(year: 2026, month: 9, day: 9)
        for day in 1...9 {
            w1.expense(333, account: w1.wallet, category: w1.expBreakfast, date: Day(year: 2026, month: 9, day: day))
        }
        let mom1 = w1.stats.momComparison(for: MonthKey(year: 2026, month: 9), today: today)
        XCTAssertEqual(mom1.base, 0)
        XCTAssertNil(mom1.percent)
        XCTAssertEqual(mom1.status, .baseZero)

        // 基期为负：8月（环比基期）净支出为负——7月的一笔支出在8月被全额退回，且8月无其他消费
        let w2 = World()
        let julExp = w2.expense(20_000, account: w2.wallet, category: w2.expBreakfast,
                                date: Day(year: 2026, month: 7, day: 1))   // 7月支出200
        w2.refund(20_000, of: julExp, to: w2.wallet, date: Day(year: 2026, month: 8, day: 5)) // 8月退款200
        // 9月 1-9 日有消费
        for day in 1...9 {
            w2.expense(333, account: w2.wallet, category: w2.expBreakfast, date: Day(year: 2026, month: 9, day: day))
        }
        let mom2 = w2.stats.momComparison(for: MonthKey(year: 2026, month: 9), today: today)
        XCTAssertTrue(mom2.base < 0)      // 8月净支出 −200
        XCTAssertNil(mom2.percent)
        XCTAssertEqual(mom2.status, .baseNegative)
    }

    // 样本：月份不足（3月30日 vs 2月28天）→ 不等长，不输出增长率
    func testUnequalMonthLength() {
        let w = World()
        // 当前 2027-03-30；2月只有28天
        for day in 1...30 {
            w.expense(1_000, account: w.wallet, category: w.expBreakfast, date: Day(year: 2027, month: 3, day: day))
        }
        let today = Day(year: 2027, month: 3, day: 30)
        let mom = w.stats.momComparison(for: MonthKey(year: 2027, month: 3), today: today)
        XCTAssertEqual(mom.status, .unequalLength)
        XCTAssertNil(mom.percent)
    }

    // 样本：YTD 年度同比（对去年同期，不对去年全年）
    func testYTDYearOverYear() {
        let w = World()
        // 去年 2025 YTD(1/1-9/9) 净 1000：1-8 月各 100（800）+ 9/8 一笔 200 = 1000
        for m in 1...8 {
            w.expense(10_000, account: w.wallet, category: w.expBreakfast, date: Day(year: 2025, month: m, day: 5))
        }
        w.expense(20_000, account: w.wallet, category: w.expBreakfast, date: Day(year: 2025, month: 9, day: 8))
        // 去年 11 月再记 800，使去年全年 = 1800（不应作为同比基期）
        w.expense(80_000, account: w.wallet, category: w.expBreakfast, date: Day(year: 2025, month: 11, day: 5))
        // 今年 2026 YTD(至9/9) 净 1200
        w.expense(120_000, account: w.wallet, category: w.expBreakfast, date: Day(year: 2026, month: 9, day: 9))

        let today = Day(year: 2026, month: 9, day: 9)
        let ys = w.stats.yearSummary(2026, today: today)
        XCTAssertEqual(ys.total.netExpense, 120_000)   // 今年 YTD 1200
        XCTAssertEqual(ys.yoy.base, 100_000)           // 对比去年同期 1000，非全年 1800
        XCTAssertEqual(ys.yoy.delta, 20_000)           // +200
        XCTAssertEqual(ys.yoy.percent ?? 0, 20.0, accuracy: 0.01) // +20%
    }

    // 样本：日期归属（发生日存储不受时区影响——Day 为纯日历值）
    func testDateOwnershipStable() {
        let w = World()
        let t = w.expense(5_000, account: w.wallet, category: w.expBreakfast,
                          date: Day(year: 2026, month: 8, day: 31))
        // 无论系统时区如何，发生年月日固定为 8/31，归属 8 月
        XCTAssertEqual(t.date.monthKey, MonthKey(year: 2026, month: 8))
        let aug = w.stats.monthSummary(MonthKey(year: 2026, month: 8))
        let sep = w.stats.monthSummary(MonthKey(year: 2026, month: 9))
        XCTAssertEqual(aug.expense, 5_000)
        XCTAssertEqual(sep.expense, 0)
    }

    // 样本：多账本隔离
    func testLedgerIsolation() {
        let store = LedgerStore()
        let personal = try! store.createLedger(name: "个人账本")
        let travel = try! store.createLedger(name: "旅行")
        let pAcc = store.accounts(in: personal.id).first!
        let tAcc = store.accounts(in: travel.id).first!
        // 账户记账起点设为年初，允许补记 9/1
        try! store.updateAccountOpening(pAcc.id, openingCents: 0, startDay: Day(year: 2026, month: 1, day: 1))
        try! store.updateAccountOpening(tAcc.id, openingCents: 0, startDay: Day(year: 2026, month: 1, day: 1))
        let pCat = store.categories(in: personal.id, kind: .expense).first { $0.isLeaf }!
        let tCat = store.categories(in: travel.id, kind: .expense).first { $0.isLeaf }!
        let d = Day(year: 2026, month: 9, day: 1)
        _ = try! store.addTransaction(Transaction(ledgerID: personal.id, kind: .expense, amountCents: 10_000,
                                                  date: d, accountID: pAcc.id, categoryID: pCat.id))
        _ = try! store.addTransaction(Transaction(ledgerID: travel.id, kind: .expense, amountCents: 5_000,
                                                  date: d, accountID: tAcc.id, categoryID: tCat.id))

        let ps = StatsEngine(store: store, ledgerID: personal.id).monthSummary(MonthKey(year: 2026, month: 9))
        let ts = StatsEngine(store: store, ledgerID: travel.id).monthSummary(MonthKey(year: 2026, month: 9))
        XCTAssertEqual(ps.expense, 10_000)
        XCTAssertEqual(ts.expense, 5_000)
        // 不能引用另一账本的分类
        XCTAssertThrowsError(try store.addTransaction(
            Transaction(ledgerID: personal.id, kind: .expense, amountCents: 100, date: d,
                        accountID: pAcc.id, categoryID: tCat.id)))
    }

    // 样本：批量原子（一条阻塞 → 整批不变）
    func testBatchAtomic() {
        let w = World()
        let d = Day(year: 2026, month: 9, day: 1)
        let t1 = w.expense(1_000, account: w.wallet, category: w.expBreakfast, date: d)
        let t2 = w.expense(2_000, account: w.wallet, category: w.expBreakfast, date: d)
        let t3 = w.expense(3_000, account: w.wallet, category: w.expBreakfast, date: d)
        // 目标分类为收入类型 → 与支出不匹配，构成阻塞
        let blockers = w.store.precheckBatch(ledgerID: w.ledger.id, ids: [t1.id, t2.id, t3.id],
                                             change: LedgerStore.BatchChange(categoryID: w.incSalary.id))
        XCTAssertFalse(blockers.isEmpty)
        XCTAssertThrowsError(try w.store.applyBatch(ledgerID: w.ledger.id, ids: [t1.id, t2.id, t3.id],
                                                    change: LedgerStore.BatchChange(categoryID: w.incSalary.id)))
        // 整批不变
        XCTAssertEqual(w.store.transaction(t1.id)!.categoryID, w.expBreakfast.id)
        XCTAssertEqual(w.store.transaction(t2.id)!.categoryID, w.expBreakfast.id)
        XCTAssertEqual(w.store.transaction(t3.id)!.categoryID, w.expBreakfast.id)

        // 合法批量：全部改为交通分类
        try! w.store.applyBatch(ledgerID: w.ledger.id, ids: [t1.id, t2.id, t3.id], change: LedgerStore.BatchChange(categoryID: w.expTransport.id))
        XCTAssertEqual(w.store.transaction(t1.id)!.categoryID, w.expTransport.id)
    }

    // 样本：回收站并发额度
    func testTrashRefundQuotaOnRestore() {
        let w = World()
        let d = Day(year: 2026, month: 9, day: 1)
        // 原支出 30
        let e = w.expense(3_000, account: w.wallet, category: w.expBreakfast, date: d)
        // 退款 8
        let r8 = w.refund(800, of: e, to: w.wallet, date: d)
        // 删除退款 8（释放额度）
        try! w.store.deleteTransaction(r8.id)
        // 新增退款 24（有效）
        w.refund(2_400, of: e, to: w.wallet, date: d)
        // 再恢复退款 8：累计将达 32 > 30 → 恢复失败，有效退款仍 24
        XCTAssertThrowsError(try w.store.restoreTransaction(r8.id)) { err in
            if case DomainError.restoreBlocked = err { /* 期望 */ } else { XCTFail("错误类型不符：\(err)") }
        }
        XCTAssertEqual(w.store.totalRefunds(forExpense: e.id), 2_400)
        XCTAssertNotNil(w.store.transaction(r8.id)?.deletedAt) // 仍在回收站
    }

    // 样本：完整备份恢复（空空间恢复后一致）
    func testBackupRestoreRoundTrip() {
        let w = World(openingCash: 100_000, openingWallet: 50_000)
        let d = Day(year: 2026, month: 9, day: 1)
        let e = w.expense(2_800, account: w.wallet, category: w.expBreakfast, date: d)
        w.transfer(10_000, from: w.cash, to: w.wallet, date: d)
        w.refund(800, of: e, to: w.wallet, date: d)
        // 含一个已删除（回收站）交易
        let trashed = w.expense(999, account: w.cash, category: w.expTransport, date: d)
        try! w.store.deleteTransaction(trashed.id)

        let backup = try! BackupService.makeBackup(from: w.store)
        let data = try! BackupService.encode(backup)
        let decoded = try! BackupService.decode(data)
        // 隔离校验
        let restored = try! BackupService.validate(backup: decoded)

        // 数量一致
        XCTAssertEqual(restored.ledgers.count, w.store.data.ledgers.count)
        XCTAssertEqual(restored.accounts.count, w.store.data.accounts.count)
        XCTAssertEqual(restored.transactions.count, w.store.data.transactions.count)
        // 在空空间用恢复数据重建 store，余额与统计一致
        let newStore = LedgerStore(data: restored)
        XCTAssertEqual(newStore.balance(accountID: w.cash.id), w.store.balance(accountID: w.cash.id))
        XCTAssertEqual(newStore.balance(accountID: w.wallet.id), w.store.balance(accountID: w.wallet.id))
        let s1 = StatsEngine(store: newStore, ledgerID: w.ledger.id).monthSummary(MonthKey(year: 2026, month: 9))
        let s2 = w.stats.monthSummary(MonthKey(year: 2026, month: 9))
        XCTAssertEqual(s1.netExpense, s2.netExpense)
        // 回收站条目仍在
        XCTAssertEqual(newStore.trashedTransactions(in: w.ledger.id).count, 1)
    }

    // 闰年 2/29 年度同比：比较双方用 1..2/28 共同窗口，主 YTD 仍含 29 日
    func testLeapDayYearComparison() {
        let w = World()
        // 去年 2023（非闰年）1-2 月净 280（1月100 + 2月180，其中 2/28 记 80）
        w.expense(10_000, account: w.wallet, category: w.expBreakfast, date: Day(year: 2023, month: 1, day: 10))
        w.expense(10_000, account: w.wallet, category: w.expBreakfast, date: Day(year: 2023, month: 2, day: 10))
        w.expense(8_000, account: w.wallet, category: w.expBreakfast, date: Day(year: 2023, month: 2, day: 28))
        // 今年 2024（闰年）至 2/29 净 300（含 2/29 的 20）
        w.expense(10_000, account: w.wallet, category: w.expBreakfast, date: Day(year: 2024, month: 1, day: 10))
        w.expense(10_000, account: w.wallet, category: w.expBreakfast, date: Day(year: 2024, month: 2, day: 10))
        w.expense(8_000, account: w.wallet, category: w.expBreakfast, date: Day(year: 2024, month: 2, day: 28))
        w.expense(2_000, account: w.wallet, category: w.expBreakfast, date: Day(year: 2024, month: 2, day: 29))

        let today = Day(year: 2024, month: 2, day: 29)
        let ys = w.stats.yearSummary(2024, today: today)
        XCTAssertEqual(ys.total.netExpense, 30_000)          // 主 YTD 含 2/29 = 300
        XCTAssertEqual(ys.yoy.base, 28_000)                  // 去年共同窗口（至2/28）= 280
        XCTAssertEqual(ys.yoy.current, 28_000)               // 今年比较窗口也只到 2/28 = 280
        XCTAssertEqual(ys.yoy.status, .ok)
    }

    // 样本：保存中断（同一 operationID 至多一笔）
    func testIdempotentOperation() {
        let w = World()
        let d = Day(year: 2026, month: 9, day: 1)
        let op = "fixed-op-id-123"
        let t = Transaction(ledgerID: w.ledger.id, operationID: op, kind: .expense, amountCents: 5_000,
                            date: d, accountID: w.wallet.id, categoryID: w.expBreakfast.id)
        _ = try! w.store.addTransaction(t)
        // 用同一 operationID 再次保存（双击/重试）→ 拒绝
        let dup = Transaction(ledgerID: w.ledger.id, operationID: op, kind: .expense, amountCents: 5_000,
                              date: d, accountID: w.wallet.id, categoryID: w.expBreakfast.id)
        XCTAssertThrowsError(try w.store.addTransaction(dup)) { err in
            XCTAssertEqual(err as? DomainError, .duplicateOperation)
        }
        XCTAssertEqual(w.store.activeTransactions(in: w.ledger.id).count, 1)
    }

    // 退款超额拦截
    func testRefundCannotExceedExpense() {
        let w = World()
        let d = Day(year: 2026, month: 9, day: 1)
        let e = w.expense(10_000, account: w.wallet, category: w.expBreakfast, date: d)
        w.refund(6_000, of: e, to: w.wallet, date: d)
        // 再退 50（累计 110 > 100）→ 拒绝
        XCTAssertThrowsError(try w.store.addTransaction(
            Transaction(ledgerID: w.ledger.id, kind: .refund, amountCents: 5_000, date: d,
                        accountID: w.wallet.id, originalExpenseID: e.id))) { err in
            if case DomainError.refundExceedsRemaining = err { } else { XCTFail("应为超额错误") }
        }
    }

    // 有退款的支出不能删除
    func testExpenseWithRefundCannotDelete() {
        let w = World()
        let d = Day(year: 2026, month: 9, day: 1)
        let e = w.expense(10_000, account: w.wallet, category: w.expBreakfast, date: d)
        w.refund(2_000, of: e, to: w.wallet, date: d)
        XCTAssertThrowsError(try w.store.deleteTransaction(e.id)) { err in
            XCTAssertEqual(err as? DomainError, .expenseHasRefundsCannotDelete)
        }
    }

    // 转账两账户不能相同
    func testTransferSameAccountRejected() {
        let w = World()
        let d = Day(year: 2026, month: 9, day: 1)
        XCTAssertThrowsError(try w.store.addTransaction(
            Transaction(ledgerID: w.ledger.id, kind: .transfer, amountCents: 1_000, date: d,
                        accountID: w.wallet.id, transferToAccountID: w.wallet.id))) { err in
            XCTAssertEqual(err as? DomainError, .sameTransferAccount)
        }
    }

    // 草稿不影响统计
    func testDraftExcludedFromStats() {
        let w = World()
        let d = Day(year: 2026, month: 9, day: 1)
        w.expense(5_000, account: w.wallet, category: w.expBreakfast, date: d)
        w.store.saveDraft(Draft(ledgerID: w.ledger.id, expression: "999", date: d, accountID: w.wallet.id))
        let s = w.stats.monthSummary(MonthKey(year: 2026, month: 9))
        XCTAssertEqual(s.expense, 5_000)  // 草稿 999 不计入
        XCTAssertNotNil(w.store.draft(for: w.ledger.id))
    }
}
