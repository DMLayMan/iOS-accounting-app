import XCTest
@testable import YujiCore

final class MoneyEditingTests: XCTestCase {
    func testInputAmountRoundTripsWithoutLocaleGrouping() throws {
        for cents: Int64 in [1, 99, 100, 99_999, 100_000, 290_029, 1_200_000, Money.maxProductCents] {
            XCTAssertEqual(try Calculator.evaluate(Money(cents).inputString).roundedCents,cents)
            XCTAssertFalse(Money(cents).inputString.contains(","))
        }
        XCTAssertEqual(Money(-500_000).inputString,"-5000.00")
    }
    func testEditingPreservesValidExpressionButUsesStoredAmountForMissingOrStaleExpression() {
        var t=Transaction(ledgerID:"ledger",operationID:"op",kind:.expense,amountCents:290_029,date:Day(year:2024,month:2,day:29),accountID:"cash",categoryID:"leaf")
        XCTAssertEqual(t.editingExpression,"2900.29")
        t.expression="2,900.29";XCTAssertEqual(t.editingExpression,"2900.29")
        t.expression="2900+0.29";XCTAssertEqual(t.editingExpression,"2900+0.29")
        t.amountCents=300_000;XCTAssertEqual(t.editingExpression,"3000.00")
    }
}
