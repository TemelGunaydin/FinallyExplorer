import Foundation
import Testing
@testable import FinallyExplorer

struct SmartSearchPlanTests {
    @Test("Two days ago means exactly one local calendar day, not the last 48 hours")
    func twoDaysAgo() throws {
        let plan = try SmartSearchTestFixtures.plan()
        let interval = try #require(plan.dateInterval)
        #expect(interval.start == (try SmartSearchTestFixtures.date("2026-09-03T00:00:00+03:00")))
        #expect(interval.end == (try SmartSearchTestFixtures.date("2026-09-04T00:00:00+03:00")))
        #expect(plan.keywords == ["accounting", "report"])
        #expect(plan.dateField == .modified)
    }

    @Test("Relative date ranges keep calendar boundaries", arguments: [
        (SmartSearchInterpretation.DateRule.lastDays, "2026-09-04", "2026-09-06"),
        (.thisWeek, "2026-08-31", "2026-09-07"),
        (.lastWeek, "2026-08-24", "2026-08-31"),
        (.thisMonth, "2026-09-01", "2026-10-01"),
        (.lastMonth, "2026-08-01", "2026-09-01"),
    ])
    func calendarRanges(_ rule: SmartSearchInterpretation.DateRule, _ start: String, _ end: String) throws {
        let plan = try SmartSearchTestFixtures.plan(SmartSearchTestFixtures.interpretation(dateRule: rule))
        let interval = try #require(plan.dateInterval)
        #expect(interval.start == (try SmartSearchTestFixtures.date(start + "T00:00:00+03:00")))
        #expect(interval.end == (try SmartSearchTestFixtures.date(end + "T00:00:00+03:00")))
    }

    @Test("Calendar days stay correct across daylight saving changes")
    func daylightSavingDayHas25Hours() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let plan = try SmartSearchPlan(
            interpretation: SmartSearchTestFixtures.interpretation(dayCount: 1),
            now: SmartSearchTestFixtures.date("2026-11-02T12:00:00-05:00"),
            calendar: calendar
        )
        let duration = try #require(plan.dateInterval?.duration)
        #expect(duration == TimeInterval(90_000))
    }

    @Test("Explicit date ranges include the entire last day")
    func explicitRange() throws {
        let plan = try SmartSearchTestFixtures.plan(SmartSearchTestFixtures.interpretation(
            dateField: .created, dateRule: .dateRange, startDate: "2026-08-01", endDate: "2026-08-31"
        ))
        #expect(plan.dateInterval?.end == (try SmartSearchTestFixtures.date("2026-09-01T00:00:00+03:00")))
        #expect(plan.dateField == .created)
    }

    @Test("Invalid dates are rejected instead of rolling into another month", arguments: [
        "2026-02-30", "2026-13-01", "2026-00-01", "26-09-03", "2026-9-3", "tomorrow", "2026-09-00",
    ])
    func rejectsInvalidDate(_ value: String) {
        #expect(throws: SmartSearchError.invalidInterpretation) {
            try SmartSearchTestFixtures.plan(SmartSearchTestFixtures.interpretation(dateRule: .onDate, startDate: value))
        }
    }

    @Test("Empty, unsupported, or malformed model output never becomes a broad search")
    func rejectsUnsafeInterpretations() {
        #expect(throws: SmartSearchError.invalidInterpretation) {
            try SmartSearchTestFixtures.plan(SmartSearchTestFixtures.interpretation(keywords: [], dateRule: .none))
        }
        #expect(throws: SmartSearchError.invalidInterpretation) {
            try SmartSearchTestFixtures.plan(SmartSearchTestFixtures.interpretation(keywords: ["/etc/passwd"]))
        }
        #expect(throws: SmartSearchError.invalidInterpretation) {
            try SmartSearchTestFixtures.plan(SmartSearchTestFixtures.interpretation(dateRule: .lastDays, dayCount: 0))
        }
        #expect(throws: SmartSearchError.invalidInterpretation) {
            try SmartSearchTestFixtures.plan(SmartSearchTestFixtures.interpretation(dayCount: -2))
        }
        var unsupported = SmartSearchTestFixtures.interpretation()
        unsupported.unsupportedCriteria = ["Delete matching files"]
        #expect(throws: SmartSearchError.unsupportedRequest) {
            try SmartSearchTestFixtures.plan(unsupported)
        }
    }

    @Test("Location filters are constrained to standard folders inside the search root")
    func locationScopeCannotEscape() throws {
        let plan = try SmartSearchTestFixtures.plan(SmartSearchTestFixtures.interpretation(location: .downloads))
        let home = URL(filePath: "/Users/test-search-user", directoryHint: .isDirectory)
        #expect(try plan.searchRoot(in: URL(filePath: "/"), homeURL: home)
            == home.appending(path: "Downloads", directoryHint: .isDirectory))
        #expect(throws: SmartSearchError.locationOutsideRoot) {
            try plan.searchRoot(in: URL(filePath: "/fixture"), homeURL: home)
        }
    }

    @Test("Visible filter labels explain the date field and actual day")
    func labelsExplainInterpretedQuery() throws {
        let plan = try SmartSearchTestFixtures.plan()
        let labels = plan.filterLabels(locale: Locale(identifier: "en_US"), timeZone: SmartSearchTestFixtures.calendar().timeZone)
        #expect(labels.contains("accounting + report"))
        #expect(labels.contains("Modified: Sep 3, 2026"))
    }
}
