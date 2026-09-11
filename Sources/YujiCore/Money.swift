import Foundation

/// 金额：以整数「分」存储，是全应用唯一金额真值。
/// 表达式只是录入工具；任何统计只使用已确认的分值（PRD §8）。
/// 使用 Int64，范围远超产品上限 ¥999,999,999.99（= 99,999,999,999 分）。
public struct Money: Hashable, Codable, Comparable, Sendable {
    /// 整数分。正数表示资产/收支方向由交易类型决定；模型层不强制符号。
    public var cents: Int64

    public static let zero = Money(0)

    /// 产品金额上限（分）：¥999,999,999.99。这是产品上限而非数据库极限（PRD §5）。
    public static let maxProductCents: Int64 = 99_999_999_999
    /// 最小可记账金额：¥0.01。
    public static let minProductCents: Int64 = 1

    public init(_ cents: Int64) { self.cents = cents }

    /// 由元（Decimal）构造，四舍五入到分。
    public init(yuan: Decimal) {
        var rounded = Decimal()
        var src = yuan * 100
        NSDecimalRound(&rounded, &src, 0, .plain)
        self.cents = NSDecimalNumber(decimal: rounded).int64Value
    }

    /// 元金额（Decimal），用于展示与计算。
    public var yuan: Decimal { Decimal(cents) / 100 }

    /// 是否在产品允许的正额范围内（普通录入金额为正）。
    public var isWithinPositiveProductRange: Bool {
        cents >= Self.minProductCents && cents <= Self.maxProductCents
    }

    public static func < (l: Money, r: Money) -> Bool { l.cents < r.cents }

    public static func + (l: Money, r: Money) -> Money { Money(l.cents + r.cents) }
    public static func - (l: Money, r: Money) -> Money { Money(l.cents - r.cents) }
    public static prefix func - (m: Money) -> Money { Money(-m.cents) }
    public static func * (m: Money, n: Int64) -> Money { Money(m.cents * n) }
}

extension Money {
    /// 按 CNY 格式化金额。`signed` 在流水/统计中控制是否显示 +/− 方向符号。
    /// 金额使用等宽数字（视图层通过 monospacedDigit 实现）。
    public func formatted(style: FormatStyle = .signed, currency: Currency = .cny) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = currency.code
        nf.currencySymbol = currency.symbol
        nf.minimumFractionDigits = 2
        nf.maximumFractionDigits = 2
        nf.negativePrefix = "-" + currency.symbol
        nf.positivePrefix = currency.symbol
        let value = NSDecimalNumber(decimal: yuan)
        let base = nf.string(from: value) ?? "\(currency.symbol)\(yuanDescription)"
        switch style {
        case .plain:
            return base
        case .signed:
            // 正数加 + 用于收入/退款方向；负数已含 −。
            if cents > 0 { return "+" + base }
            return base
        case .unsigned:
            // 始终按绝对值展示，不带方向符号（方向由类型图标/颜色表达）。
            nf.negativePrefix = currency.symbol
            return nf.string(from: NSDecimalNumber(decimal: abs(yuan))) ?? base
        }
    }

    /// 不带货币符号的纯数字字符串，如 "1,234.56" 或 "-80.00"。
    public var yuanDescription: String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 2
        nf.maximumFractionDigits = 2
        nf.negativePrefix = "-"
        return nf.string(from: NSDecimalNumber(decimal: yuan)) ?? String(describing: yuan)
    }

    public enum FormatStyle {
        case plain      // ¥1,234.56，负值 −¥…
        case signed     // 收入 +¥…，支出 −¥…
        case unsigned   // 始终绝对值
    }
}

/// 币种。首版仅 CNY（PRD §1 建议默认）。
public struct Currency: Hashable, Codable, Sendable {
    public let code: String
    public let symbol: String
    public static let cny = Currency(code: "CNY", symbol: "¥")
}

extension Money {
    /// Locale-independent text for calculator / numeric fields, never a formatted label.
    public var inputString: String {
        let value = cents.magnitude
        let fraction = value % 100
        return "\(cents < 0 ? "-" : "")\(value / 100).\(fraction < 10 ? "0" : "")\(fraction)"
    }
}

extension Transaction {
    /// Stored cents remain authoritative when an imported or old expression is absent/stale.
    public var editingExpression: String {
        if let expression = expression, let result = try? Calculator.evaluate(expression), result.roundedCents == amountCents {
            return expression
        }
        return Money(amountCents).inputString
    }
}
