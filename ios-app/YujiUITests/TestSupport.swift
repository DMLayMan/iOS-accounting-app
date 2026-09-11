import XCTest

extension XCUIApplication {
    /// A fixed business day makes fixture totals reproducible without changing the simulator clock.
    /// Every invocation gets a new file; a relaunch within the same test retains its own file.
    func useIsolatedFixture(_ fixture: String = "YUJI_STRESS_SESSION") {
        launchEnvironment[fixture] = UUID().uuidString
        launchEnvironment["YUJI_TEST_TODAY"] = "2026-09-10"
    }
}

extension XCUIApplication {
    /// A fixed period header covers scrolled content even when XCTest marks it hittable.
    var scrollContentTop: CGFloat {
        var top = (navigationBars.allElementsBoundByIndex.last(where: { $0.isHittable })?.frame.maxY ?? 60) + 8
        for prefix in ["stats", "feed"] {
            let date = buttons[prefix + ".date"]
            if date.exists && date.isHittable { top = max(top, date.frame.maxY + 8) }
        }
        return top
    }
}
