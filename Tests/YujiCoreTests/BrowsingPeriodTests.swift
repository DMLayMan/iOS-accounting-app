import XCTest
@testable import YujiCore

final class BrowsingPeriodTests: XCTestCase {
    private let today = Day(year: 2026, month: 9, day: 10)
    private let earliest = Day(year: 2022, month: 1, day: 1)

    func testLeapMonthAndCrossYearRangeIncludeBothEndpoints() {
        let leap = BrowsingPeriod.month(MonthKey(year: 2024, month: 2))
        XCTAssertEqual(leap.range(today: today)?.upperBound, Day(year: 2024, month: 2, day: 29))
        let range = Day(year: 2023, month: 12, day: 31)...Day(year: 2024, month: 1, day: 1)
        XCTAssertEqual(BrowsingPeriod.custom(range).statisticsRange(today: today, earliest: earliest), range)
        XCTAssertEqual(BrowsingPeriod.custom(range).title(today: today), "2023.12.31–2024.01.01")
    }

    func testRelativeMonthFollowsClockButChosenMonthDoesNot() {
        let next = Day(year: 2026, month: 10, day: 1)
        XCTAssertEqual(BrowsingPeriod.currentMonth.range(today: next)?.lowerBound, next)
        XCTAssertEqual(BrowsingPeriod.month(today.monthKey).range(today: next)?.lowerBound,
                       Day(year: 2026, month: 9, day: 1))
        XCTAssertEqual(BrowsingPeriod.currentYear.range(today: Day(year: 2027, month: 1, day: 1))?.lowerBound,
                       Day(year: 2027, month: 1, day: 1))
    }

    func testFutureRecordsRemainRetrievableButExcludedFromActualStatistics() {
        let future = BrowsingPeriod.month(MonthKey(year: 2026, month: 12))
        XCTAssertNotNil(future.range(today: today))
        XCTAssertNil(future.statisticsRange(today: today, earliest: earliest))
        XCTAssertEqual(BrowsingPeriod.currentMonth.range(today: today)?.upperBound,
                       Day(year: 2026, month: 9, day: 30))
        for selection in [BrowsingPeriod.currentMonth, .currentYear, .all,
                          .custom(earliest...Day(year: 2027, month: 1, day: 1))] {
            XCTAssertEqual(selection.statisticsRange(today: today, earliest: earliest)?.upperBound, today)
        }
        XCTAssertNil(BrowsingPeriod.all.range(today: today))
        XCTAssertEqual(BrowsingPeriod.all.statisticsRange(today: today, earliest: earliest)?.lowerBound, earliest)
    }

    func testEmptyBookAndPastYearHaveValidRanges() {
        XCTAssertEqual(BrowsingPeriod.all.statisticsRange(today: today, earliest: today), today...today)
        let lastYear = BrowsingPeriod.year(2025).statisticsRange(today: today, earliest: earliest)
        XCTAssertEqual(lastYear?.lowerBound, Day(year: 2025, month: 1, day: 1))
        XCTAssertEqual(lastYear?.upperBound, Day(year: 2025, month: 12, day: 31))
    }
}
