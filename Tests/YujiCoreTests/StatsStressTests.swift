import XCTest
@testable import YujiCore

/// Expected amounts and record IDs are computed independently by Node.js, never by StatsEngine.
final class StatsStressTests: XCTestCase {
    private let fixtureRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
    private func fixture() throws -> (LedgerData, [String: Any]) {
        let data = try XCTUnwrap(JSONFileRepository(url: fixtureRoot.appendingPathComponent("stats-500.json")).load())
        let oracle = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureRoot.appendingPathComponent("stats-500-oracle.json"))) as! [String: Any]
        return (data, oracle)
    }
    private func day(_ s: String) -> Day { let n = s.split(separator: "-").map { Int($0)! }; return Day(year: n[0], month: n[1], day: n[2]) }
    private func range(_ o: [String: Any]) -> ClosedRange<Day> { day(o["from"] as! String)...day(o["to"] as! String) }
    private func cents(_ o: [String: Any], _ k: String) -> Int64 { (o[k] as! NSNumber).int64Value }
    private func check(_ s: PeriodSummary, _ o: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(s.expense, cents(o,"expense"), file:file,line:line)
        XCTAssertEqual(s.refund, cents(o,"refund"), file:file,line:line)
        XCTAssertEqual(s.netExpense, cents(o,"netExpense"), file:file,line:line)
        XCTAssertEqual(s.income, cents(o,"income"), file:file,line:line)
        XCTAssertEqual(s.surplus, cents(o,"surplus"), file:file,line:line)
    }
    private func check(_ c: StatsEngine.Comparison, _ o: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(c.current,cents(o,"current"), file:file,line:line)
        XCTAssertEqual(c.base,cents(o,"base"), file:file,line:line)
        XCTAssertEqual(c.delta,cents(o,"delta"), file:file,line:line)
        XCTAssertEqual(String(describing:c.status),o["status"] as! String,file:file,line:line)
        if let p=o["percent"] as? Double { XCTAssertEqual(c.percent ?? .nan,p,accuracy:0.0000001,file:file,line:line) }
        else { XCTAssertNil(c.percent,file:file,line:line) }
    }
    func test500Records57Months5YearsAgainstIndependentOracle() throws {
        let (data,o) = try fixture(); let store=LedgerStore(data:data); let stats=StatsEngine(store:store,ledgerID:"stress")
        XCTAssertEqual(data.transactions.count,500); XCTAssertEqual(store.activeTransactions(in:"stress").count,470)
        let today=day("2026-09-10")
        check(stats.summary(range:day("2022-01-01")...today),o["total"] as! [String:Any])
        for m in o["months"] as! [[String:Any]] {
            let s=m["summary"] as! [String:Any]; check(stats.summary(range:range(s)),s)
            let mk=MonthKey(year:m["year"] as! Int,month:m["month"] as! Int)
            check(stats.momComparison(for:mk,today:today),m["mom"] as! [String:Any])
            check(stats.yoyComparison(for:mk,today:today),m["yoy"] as! [String:Any])
        }
        for y in o["years"] as! [[String:Any]] {
            let s=stats.yearSummary(y["year"] as! Int,today:today)
            check(s.total,y["summary"] as! [String:Any]);check(s.yoy,y["yoy"] as! [String:Any])
            XCTAssertEqual(s.months.values.reduce(0){$0+$1.netExpense},s.total.netExpense)
        }
        for b in o["balances"] as! [[String:Any]] { XCTAssertEqual(store.balance(accountID:EntityID(b["id"] as! String)),cents(b,"cents")) }
    }
    func testMonthlyCategoryConservationIncludingIncomeAndRefundOnlyMonth() throws {
        let (data,o)=try fixture();let stats=StatsEngine(store:LedgerStore(data:data),ledgerID:"stress")
        for m in o["months"] as! [[String:Any]] {
            let s=m["summary"] as! [String:Any]
            for kind in [TransactionKind.expense,.income] {
                let rows=stats.categoryBreakdown(range:range(s),kind:kind)
                let expected=m[kind.rawValue] as! [[String:Any]]
                XCTAssertEqual(Set(rows.map(\.id.raw)),Set(expected.map{$0["id"] as! String}),"\(s["from"]!) \(kind)")
                for e in expected {let row=try XCTUnwrap(rows.first{$0.id.raw==e["id"] as! String});XCTAssertEqual(row.expense,cents(e,"expense"));XCTAssertEqual(row.refund,cents(e,"refund"));XCTAssertEqual(row.count,e["count"] as! Int)}
                XCTAssertEqual(rows.reduce(0){$0+$1.expense},cents(s,kind == .expense ? "expense":"income"))
                XCTAssertEqual(rows.reduce(0){$0+$1.refund},kind == .expense ? cents(s,"refund"):0)
            }
        }
    }
    func testDiskRoundTripKeepsAll500RecordsAndTotals() throws {
        let (data,o)=try fixture();let url=FileManager.default.temporaryDirectory.appendingPathComponent("stats-500-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at:url) }
        let repo=JSONFileRepository(url:url); try repo.save(data);let loaded=try XCTUnwrap(repo.load())
        XCTAssertEqual(loaded.transactions.count,500)
        check(StatsEngine(store:LedgerStore(data:loaded),ledgerID:"stress").summary(range:day("2022-01-01")...day("2026-09-10")),o["total"] as! [String:Any])
    }
    func testParentLeafAndDrilldownRecordIDsAgreeWithOracleFor57Months() throws {
        let (data,o)=try fixture();let stats=StatsEngine(store:LedgerStore(data:data),ledgerID:"stress")
        for m in o["months"] as! [[String:Any]] {
            let r=range(m["summary"] as! [String:Any])
            let expected=m["parents"] as! [[String:Any]]
            let parents=stats.categoryGroups(range:r)
            XCTAssertEqual(Set(parents.map(\.id.raw)),Set(expected.map{$0["id"] as! String}))
            for e in expected {
                let id=EntityID(e["id"] as! String)
                let item=try XCTUnwrap(parents.first{$0.id==id})
                XCTAssertEqual(item.expense,cents(e,"expense"));XCTAssertEqual(item.refund,cents(e,"refund"))
                let leaves=stats.categoryGroups(range:r,parentID:id)
                XCTAssertEqual(leaves.reduce(0){$0+$1.net},item.net)
                XCTAssertEqual(leaves.reduce(0){$0+$1.count},item.count)
                let details=stats.categoryTransactions(range:r,kind:.expense,categoryID:id)
                XCTAssertEqual(details.map(\.id.raw).sorted(),e["transactionIDs"] as! [String])
                for leaf in leaves {
                    let expectedLeaf=(m["expense"] as! [[String:Any]]).first{$0["id"] as! String==leaf.id.raw}!
                    XCTAssertEqual(stats.categoryTransactions(range:r,kind:.expense,categoryID:leaf.id).map(\.id.raw).sorted(),expectedLeaf["transactionIDs"] as! [String])
                }
            }
            for e in m["income"] as! [[String:Any]] {
                XCTAssertEqual(stats.categoryTransactions(range:r,kind:.income,categoryID:EntityID(e["id"] as! String)).map(\.id.raw).sorted(),e["transactionIDs"] as! [String])
            }
            let countRows=stats.categoryGroups(range:r,sort:.count)
            XCTAssertEqual(countRows.map(\.count),countRows.map(\.count).sorted(by:>))
            let refundRows=stats.categoryGroups(range:r,sort:.refund)
            XCTAssertEqual(refundRows.map(\.refund),refundRows.map(\.refund).sorted(by:>))
            let cmp=stats.momComparison(for:MonthKey(year:m["year"] as! Int,month:m["month"] as! Int),today:day("2026-09-10"))
            let changes=stats.categoryChanges(currentRange:try XCTUnwrap(cmp.currentRange),baseRange:try XCTUnwrap(cmp.baseRange))
            XCTAssertEqual(changes.reduce(0){$0+$1.delta},cmp.delta)
            XCTAssertEqual(changes.map{abs($0.delta)},changes.map{abs($0.delta)}.sorted(by:>))
        }
    }

    func testBackupRestoreAndEditsRefreshFiveYearTotals() throws {
        let (data,o)=try fixture();let store=LedgerStore(data:data)
        let backup=try BackupService.makeBackup(from:store)
        let restored=try BackupService.validate(backup:BackupService.decode(BackupService.encode(backup)))
        XCTAssertEqual(restored.transactions.count,500)
        let stats=StatsEngine(store:store,ledgerID:"stress")
        let r=day("2022-01-01")...day("2026-09-10")
        let original=try XCTUnwrap(store.transaction("tx-200"))
        _ = try store.updateTransaction(original.id){$0.amountCents += 12345}
        XCTAssertEqual(stats.summary(range:r).expense,cents(o["total"] as! [String:Any],"expense")+12345)
        try store.deleteTransaction(original.id)
        XCTAssertFalse(stats.categoryTransactions(range:r,kind:.expense).contains{$0.id==original.id})
        XCTAssertEqual(stats.summary(range:r).expense,cents(o["total"] as! [String:Any],"expense")-original.amountCents)
        try store.restoreTransaction(original.id)
        _ = try store.updateTransaction(original.id){$0.amountCents = original.amountCents}
        check(stats.summary(range:r),o["total"] as! [String:Any])
    }

    func testExactComparisonWindowsAndKnownCoverageBoundary() throws {
        let (data,_)=try fixture();let stats=StatsEngine(store:LedgerStore(data:data),ledgerID:"stress")
        let leap=stats.yoyComparison(for:MonthKey(year:2024,month:2),today:day("2024-02-29"))
        XCTAssertEqual(leap.currentRange,day("2024-02-01")...day("2024-02-28"))
        XCTAssertEqual(leap.baseRange,day("2023-02-01")...day("2023-02-28"))
        XCTAssertEqual(leap.status,.unequalLength);XCTAssertNil(leap.percent)
        let march=stats.momComparison(for:MonthKey(year:2024,month:3),today:day("2024-03-31"))
        XCTAssertEqual(march.currentRange?.upperBound,day("2024-03-29"));XCTAssertEqual(march.status,.unequalLength)
        let current=stats.momComparison(for:MonthKey(year:2026,month:9),today:day("2026-09-10"))
        XCTAssertEqual(current.baseRange,day("2026-08-01")...day("2026-08-10"))
        XCTAssertEqual(stats.momComparison(for:MonthKey(year:2022,month:1),today:day("2026-09-10")).status,.baseNotCovered)
        XCTAssertEqual(stats.momComparison(for:MonthKey(year:2023,month:4),today:day("2026-09-10")).status,.baseZero)
        XCTAssertEqual(stats.momComparison(for:MonthKey(year:2023,month:2),today:day("2026-09-10")).status,.baseNegative)
    }

    func testRepeatedFiveYearExplorationTiming() throws {
        let (data,_)=try fixture();let stats=StatsEngine(store:LedgerStore(data:data),ledgerID:"stress")
        let start=Date()
        for _ in 0..<100 {
            for year in 2022...2026 {
                let result=stats.yearSummary(year,today:day("2026-09-10"))
                _ = stats.categoryGroups(range:result.ytdRange)
                _ = stats.categoryTransactions(range:result.ytdRange,kind:.expense)
            }
        }
        print("STATS_STRESS_TIMING: 500 year-summary + category + drilldown queries, \(Date().timeIntervalSince(start)) seconds")
    }

}
