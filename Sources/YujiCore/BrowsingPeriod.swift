import Foundation

/// Shared navigation state. Relative periods follow the clock; explicitly chosen dates stay fixed.
public enum BrowsingPeriod: Equatable, Hashable, Sendable {
    case currentMonth, currentYear, month(MonthKey), year(Int), custom(ClosedRange<Day>), all


    public func month(today: Day) -> MonthKey? {
        switch self {
        case .currentMonth: return today.monthKey
        case .month(let month): return month
        default: return nil
        }
    }

    public func year(today: Day) -> Int? {
        switch self {
        case .currentYear: return today.year
        case .year(let year): return year
        default: return nil
        }
    }

    /// The transaction list can retrieve future-dated records too.
    public func range(today: Day) -> ClosedRange<Day>? {
        if let month = month(today: today) { return month.fullRange }
        if let year = year(today: today) {
            return Day(year: year, month: 1, day: 1)...Day(year: year, month: 12, day: 31)
        }
        if case .custom(let range) = self { return range }
        return nil
    }

    /// Statistics retain their existing "through today" rule. A wholly future period has no actuals.
    public func statisticsRange(today: Day, earliest: Day) -> ClosedRange<Day>? {
        let selected = range(today: today) ?? min(earliest, today)...today
        guard selected.lowerBound <= today else { return nil }
        return selected.lowerBound...min(selected.upperBound, today)
    }

    public func title(today: Day) -> String {
        if let month = month(today: today) { return "\(month.year) 年 \(month.month) 月" }
        if let year = year(today: today) { return "\(year) 年" }
        if case .custom(let range) = self {
            let first = range.lowerBound, last = range.upperBound
            let end = first.year == last.year ? String(format: "%02d.%02d", last.month, last.day)
                : String(format: "%04d.%02d.%02d", last.year, last.month, last.day)
            return String(format: "%04d.%02d.%02d", first.year, first.month, first.day) + "–" + end
        }
        return "全部时间"
    }
}
