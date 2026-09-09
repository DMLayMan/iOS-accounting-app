import Foundation

/// 金额表达式计算器（PRD §8）。
/// - 支持数字、小数点、+ − × ÷、括号与优先级；半角 * / 等价。
/// - 十进制求值（Foundation Decimal），不使用二进制 Double。
/// - 乘除优先于加减，同级从左到右，括号优先；支持一元负号（如 100 + (−20)）。
/// - 除法使用十进制精度上下文（Decimal 默认约 38 位有效数字），不在每步先舍入到分。
/// - 最终提交金额必须为正；舍入到分用「半入」四舍五入，超两位小数需用户明确确认。
public enum Calculator {

    public enum Error: Swift.Error, Equatable {
        case empty
        case unexpectedCharacter(String)       // 含位置
        case incompleteExpression             // 10 + 、括号不匹配
        case unmatchedOpenParen
        case unmatchedCloseParen
        case duplicateDecimalPoint
        case divisionByZero
        case overflow
        case tooLong                          // 超过 128 字符
        case tooDeep                          // 超过 8 层括号
    }

    /// 求值结果。
    public struct Result: Equatable {
        /// 精确十进制结果（未舍入）。
        public let exact: Decimal
        public init(exact: Decimal) { self.exact = exact }

        /// 舍入到分（半入）后的金额。
        public var roundedCents: Int64 {
            var r = Decimal()
            var src = exact * 100
            NSDecimalRound(&r, &src, 0, .plain)
            return NSDecimalNumber(decimal: r).int64Value
        }

        /// 舍入后的 Money（分）。
        public var roundedMoney: Money { Money(roundedCents) }

        /// 是否存在超过两位小数、需要用户明确确认舍入。
        public var needsRoundingConfirmation: Bool {
            // 精确值与舍入值不一致 → 需要确认。
            exact != Decimal(roundedCents) / 100
        }

        /// 精确结果的展示字符串（保留足够位数，如 1÷3 → 0.333…）。
        public var exactDisplay: String { Self.format(exact) }

        /// 舍入后两位小数字符串（始终保留两位小数）。
        public var roundedDisplay: String {
            var r = Decimal()
            var src = exact
            NSDecimalRound(&r, &src, 2, .plain)
            return Self.formatMoney(r)
        }

        static func format(_ d: Decimal) -> String {
            var x = d
            return NSDecimalString(&x, Locale(identifier: "en_US"))
        }

        /// 两位小数金额格式（如 0.30、5.00）。
        static func formatMoney(_ d: Decimal) -> String {
            let nf = NumberFormatter()
            nf.locale = Locale(identifier: "en_US")
            nf.numberStyle = .decimal
            nf.minimumFractionDigits = 2
            nf.maximumFractionDigits = 2
            nf.negativePrefix = "-"
            return nf.string(from: NSDecimalNumber(decimal: d)) ?? format(d)
        }
    }

    public static let maxExpressionLength = 128
    public static let maxParenDepth = 8

    /// 规范化输入：全角×÷−→半角、* / 等价、去除空格。不猜测千位分隔符（PRD §8：含糊的 1,234.56 不静默猜测）。
    public static func normalize(_ raw: String) -> String {
        var s = raw
        s = s.replacingOccurrences(of: "×", with: "*")
        s = s.replacingOccurrences(of: "÷", with: "/")
        s = s.replacingOccurrences(of: "−", with: "-")
        s = s.replacingOccurrences(of: "　", with: "")
        s = s.replacingOccurrences(of: " ", with: "")
        s = s.replacingOccurrences(of: "\t", with: "")
        return s
    }

    /// 求值。抛出 Calculator.Error。
    public static func evaluate(_ raw: String) throws -> Result {
        let expr = normalize(raw)
        if expr.isEmpty { throw Error.empty }
        if expr.count > maxExpressionLength { throw Error.tooLong }

        let tokens = try tokenize(expr)
        var parser = Parser(tokens: tokens)
        let value = try parser.parseExpression()
        try parser.expectEnd()
        if value.isNaN { throw Error.incompleteExpression }
        // 溢出检测：结果量级超过 10^15 元（远超产品上限 10^9 元）视为求值溢出，拒绝。
        let bound = Decimal(sign: .plus, exponent: 15, significand: 1) // 1×10^15
        var av = value
        if av < 0 { av = -av }
        if av > bound { throw Error.overflow }
        return Result(exact: value)
    }

    // MARK: - 词法

    enum Token: Equatable {
        case number(Decimal)
        case plus, minus, star, slash
        case lParen, rParen
    }

    static func tokenize(_ s: String) throws -> [Token] {
        let chars = Array(s)
        var tokens: [Token] = []
        var i = 0
        var depth = 0
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "+": tokens.append(.plus); i += 1
            case "-": tokens.append(.minus); i += 1
            case "*": tokens.append(.star); i += 1
            case "/": tokens.append(.slash); i += 1
            case "(":
                depth += 1
                if depth > maxParenDepth { throw Error.tooDeep }
                tokens.append(.lParen); i += 1
            case ")":
                depth -= 1
                if depth < 0 { throw Error.unmatchedCloseParen }
                tokens.append(.rParen); i += 1
            case "0"..."9", ".":
                // 读取数字，含小数点
                var num = ""
                var seenDot = false
                while i < chars.count {
                    let ch = chars[i]
                    if ch.isNumber {
                        num.append(ch); i += 1
                    } else if ch == "." {
                        if seenDot { throw Error.duplicateDecimalPoint }
                        seenDot = true
                        num.append(ch); i += 1
                    } else {
                        break
                    }
                }
                if num == "." || num.isEmpty { throw Error.unexpectedCharacter(num) }
                guard let dec = Decimal(string: num, locale: Locale(identifier: "en_US")) else {
                    throw Error.unexpectedCharacter(num)
                }
                tokens.append(.number(dec))
            default:
                throw Error.unexpectedCharacter(String(c))
            }
        }
        if depth != 0 { throw Error.unmatchedOpenParen }
        return tokens
    }

    // MARK: - 语法（递归下降）
    // expression = term (('+' | '-') term)*
    // term       = factor(('*' | '/') factor)*
    // factor     = ['-' | '+'] factor | '(' expression ')' | number

    struct Parser {
        let tokens: [Token]
        var pos = 0

        mutating func peek() -> Token? { pos < tokens.count ? tokens[pos] : nil }
        mutating func consume() -> Token? { pos < tokens.count ? tokens[pos] : nil }
        @discardableResult mutating func advance() -> Token? {
            let t = pos < tokens.count ? tokens[pos] : nil
            pos += 1
            return t
        }

        mutating func expectEnd() throws {
            if pos != tokens.count { throw Error.incompleteExpression }
        }

        mutating func parseExpression() throws -> Decimal {
            var value = try parseTerm()
            while let t = peek() {
                if t == .plus {
                    advance()
                    let rhs = try parseTerm()
                    value = value + rhs
                } else if t == .minus {
                    advance()
                    let rhs = try parseTerm()
                    value = value - rhs
                } else {
                    break
                }
            }
            return value
        }

        mutating func parseTerm() throws -> Decimal {
            var value = try parseFactor()
            while let t = peek() {
                if t == .star {
                    advance()
                    let rhs = try parseFactor()
                    value = value * rhs
                } else if t == .slash {
                    advance()
                    let rhs = try parseFactor()
                    if rhs == 0 { throw Error.divisionByZero }
                    value = value / rhs
                } else {
                    break
                }
            }
            return value
        }

        mutating func parseFactor() throws -> Decimal {
            guard let t = peek() else { throw Error.incompleteExpression }
            switch t {
            case .minus:
                advance()
                let v = try parseFactor()
                return -v
            case .plus:
                advance()
                return try parseFactor()
            case .lParen:
                advance()
                let v = try parseExpression()
                guard let close = peek(), close == .rParen else {
                    throw Error.unmatchedOpenParen
                }
                advance()
                return v
            case .number(let d):
                advance()
                return d
            case .rParen:
                throw Error.unmatchedCloseParen
            case .star, .slash:
                throw Error.incompleteExpression
            }
        }
    }
}

extension Calculator.Error {
    /// 用户可理解的中文错误文案。
    public var message: String {
        switch self {
        case .empty: return "请输入金额"
        case .incompleteExpression: return "算式不完整，请检查运算符和数字"
        case .unmatchedOpenParen: return "括号不匹配：有未闭合的左括号"
        case .unmatchedCloseParen: return "括号不匹配：多出右括号"
        case .duplicateDecimalPoint: return "一个数字里不能有多个小数点"
        case .divisionByZero: return "除数不能为 0"
        case .overflow: return "结果超出可记录范围"
        case .tooLong: return "算式过长（最多 \(Calculator.maxExpressionLength) 个字符）"
        case .tooDeep: return "括号层数过多（最多 \(Calculator.maxParenDepth) 层）"
        case .unexpectedCharacter(let c): return "无法识别的字符：\(c)"
        }
    }
}
