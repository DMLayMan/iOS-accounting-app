import SwiftUI
import YujiCore

func statsMoney(_ cents: Int64) -> String { "¥\(Money(cents).yuanDescription)" }
func statsDayText(_ day: Day) -> String { String(format: "%04d.%02d.%02d", day.year, day.month, day.day) }
func spokenDayText(_ day: Day) -> String { "\(day.year)年\(day.month)月\(day.day)日" }
func statsRangeText(_ range: ClosedRange<Day>) -> String { "\(statsDayText(range.lowerBound))–\(statsDayText(range.upperBound))" }
func statsComparisonReason(_ status: StatsEngine.Comparison.Status) -> String {
    switch status {
    case .ok: return "按已记录的净支出比较"
    case .baseZero: return "基期为零，无增长率"
    case .baseNegative: return "基期为负，无增长率"
    case .baseNotCovered: return "基期早于记账起点"
    case .unequalLength: return "按共同天数比较，不算增长率"
    }
}

struct StatsRangeLabel: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let range: ClosedRange<Day>
    var body: some View {
        Text(typeSize.isAccessibilitySize
             ? "\(statsDayText(range.lowerBound))\n至 \(statsDayText(range.upperBound))"
             : statsRangeText(range))
            .font(.caption).foregroundStyle(Design.secondary)
            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1).minimumScaleFactor(0.6)
            .accessibilityLabel("时间范围，\(spokenDayText(range.lowerBound))至\(spokenDayText(range.upperBound))")
    }
}

extension Calculator.Result {
    var saveActionTitle: String { needsRoundingConfirmation ? "按 ¥\(roundedDisplay) 保存" : "保存" }
}
