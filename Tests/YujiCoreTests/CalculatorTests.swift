import XCTest
@testable import YujiCore

/// PRD §8 金额输入与计算器合同。
final class CalculatorTests: XCTestCase {

    private func eval(_ s: String) throws -> Calculator.Result {
        try Calculator.evaluate(s)
    }

    func testPrecedenceMultiplicationBeforeAddition() throws {
        // 12 + 3 × 4 = 24.00
        XCTAssertEqual(try eval("12 + 3 × 4").roundedCents, 2400)
        XCTAssertEqual(try eval("12 + 3 * 4").roundedCents, 2400)
    }

    func testParentheses() throws {
        // (12 + 3) × 4 = 60.00
        XCTAssertEqual(try eval("(12 + 3) × 4").roundedCents, 6000)
    }

    func testDecimalAdditionNoBinaryError() throws {
        // 0.1 + 0.2 = 0.30，不出现 0.30000000000000004
        let r = try eval("0.1 + 0.2")
        XCTAssertEqual(r.roundedCents, 30)
        XCTAssertEqual(r.roundedDisplay, "0.30")
        XCTAssertFalse(r.exactDisplay.contains("0000000004"))
    }

    func testDivisionByThreeRequiresRoundingConfirmation() throws {
        // 1 ÷ 3 → 预览 0.333…，明确确认后保存 33 分
        let r = try eval("1 ÷ 3")
        XCTAssertTrue(r.needsRoundingConfirmation)
        XCTAssertEqual(r.roundedCents, 33)
        XCTAssertTrue(r.exactDisplay.hasPrefix("0.333"))
    }

    func testDivisionNoIntermediateRounding() throws {
        // 10 ÷ 6 × 3：中间不先按分舍入，最终为 5.00
        let r = try eval("10 ÷ 6 × 3")
        XCTAssertEqual(r.roundedCents, 500)
        XCTAssertEqual(r.roundedDisplay, "5.00")
    }

    func testHalfUpRounding() throws {
        // 1.005 半入到 1.01
        let r = try eval("1.005")
        XCTAssertTrue(r.needsRoundingConfirmation)
        XCTAssertEqual(r.roundedCents, 101)
    }

    func testDivisionByZeroRejected() {
        XCTAssertThrowsError(try eval("10 ÷ 0")) { err in
            XCTAssertEqual(err as? Calculator.Error, .divisionByZero)
        }
        XCTAssertThrowsError(try eval("5 ÷ (2 − 2)")) { err in
            XCTAssertEqual(err as? Calculator.Error, .divisionByZero)
        }
    }

    func testIncompleteExpression() {
        XCTAssertThrowsError(try eval("10 +")) { XCTAssertEqual($0 as? Calculator.Error, .incompleteExpression) }
        XCTAssertThrowsError(try eval("(10 + 2")) { XCTAssertEqual($0 as? Calculator.Error, .unmatchedOpenParen) }
        XCTAssertThrowsError(try eval("1.2.3")) { XCTAssertEqual($0 as? Calculator.Error, .duplicateDecimalPoint) }
    }

    func testNegativeFinalValueAllowedInCalcButRejectedAtSubmit() throws {
        // 20 − 30 可预览 −10.00；表达式层能算出负值，提交层（金额为正）拒绝。
        let r = try eval("20 − 30")
        XCTAssertEqual(r.roundedCents, -1000)
        // 负值不在正额产品范围内 → 表单应拒绝提交。
        XCTAssertFalse(Money(r.roundedCents).isWithinPositiveProductRange)
    }

    func testUnaryMinus() throws {
        // 100 + (−20) = 80
        XCTAssertEqual(try eval("100 + (-20)").roundedCents, 8000)
    }

    func testZeroRejected() {
        // 0 或舍入后为 0：拒绝提交（不创建零额流水）
        XCTAssertEqual(try eval("0").roundedCents, 0)
        XCTAssertFalse(Money(try eval("0").roundedCents).isWithinPositiveProductRange)
    }

    func testOverLimitRejected() throws {
        // 超金额上限
        let big = try eval("999999999.99 + 1")
        XCTAssertFalse(Money(big.roundedCents).isWithinPositiveProductRange)
    }

    func testTooLongExpression() {
        let long = String(repeating: "1+", count: 70) + "1"
        XCTAssertThrowsError(try eval(long)) { XCTAssertEqual($0 as? Calculator.Error, .tooLong) }
    }

    func testTooDeepParens() {
        let deep = String(repeating: "(", count: 9) + "1" + String(repeating: ")", count: 9)
        XCTAssertThrowsError(try eval(deep)) { XCTAssertEqual($0 as? Calculator.Error, .tooDeep) }
    }

    func testEmpty() {
        XCTAssertThrowsError(try eval("")) { XCTAssertEqual($0 as? Calculator.Error, .empty) }
    }

    func testUnsupportedFullWidthDigitsRejected() {
        // 全角数字不做静默转换，明确报错（不猜测含糊输入）。
        XCTAssertThrowsError(try eval("１０＋２"))
    }

    func testHalfWidthEquivalents() throws {
        XCTAssertEqual(try eval("10/6*3").roundedCents, 500)
        XCTAssertEqual(try eval("8-3").roundedCents, 500)
    }
}
