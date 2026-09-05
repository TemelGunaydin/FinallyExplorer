import Foundation
@testable import FinallyExplorer

nonisolated enum SmartSearchTestFixtures {
    static func interpretation(
        keywords: [String] = ["accounting", "report"],
        area: SmartSearchInterpretation.Area = .namesAndContents,
        kind: SmartSearchInterpretation.Kind = .any,
        location: SmartSearchInterpretation.Location = .anywhere,
        dateField: SmartSearchInterpretation.DateField = .modified,
        dateRule: SmartSearchInterpretation.DateRule = .daysAgo,
        dayCount: Int = 2,
        startDate: String = "",
        endDate: String = ""
    ) -> SmartSearchInterpretation {
        SmartSearchInterpretation(
            area: area, kind: kind,
            location: location, dateField: dateField, dateRule: dateRule,
            dayCount: dayCount, startDate: startDate, endDate: endDate,
            keywords: keywords, unsupportedCriteria: []
        )
    }

    static func date(_ text: String) throws -> Date {
        try Date(text, strategy: .iso8601)
    }

    static func calendar() -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 3 * 60 * 60) ?? .gmt
        value.firstWeekday = 2
        value.minimumDaysInFirstWeek = 4
        return value
    }

    static func plan(_ interpretation: SmartSearchInterpretation? = nil) throws -> SmartSearchPlan {
        try SmartSearchPlan(
            interpretation: interpretation ?? Self.interpretation(),
            now: date("2026-09-05T12:00:00+03:00"),
            calendar: calendar()
        )
    }

    static func result(named name: String) -> ExplorerSearchResult {
        let url = URL(filePath: "/fixture/\(name)")
        return ExplorerSearchResult(
            id: "smart-fixture:\(name)",
            item: FileItem(url: url, isDirectory: false, isImage: false, fileSize: 20, modificationDate: nil),
            relativePath: name,
            contentMatch: nil
        )
    }
}

nonisolated struct SmartSearchInterpreterStub: SmartSearchInterpreting {
    var respond: @Sendable (String) async throws -> SmartSearchPlan = { _ in
        try SmartSearchTestFixtures.plan()
    }

    func interpret(_ query: String) async throws -> SmartSearchPlan { try await respond(query) }
}

nonisolated struct SmartSearchExecutorStub: SmartSearchExecuting {
    var respond: @Sendable (URL, SmartSearchPlan) async throws -> GlobalSearchPage = { _, _ in
        GlobalSearchPage(results: [SmartSearchTestFixtures.result(named: "accounting report.pdf")], message: nil)
    }

    func search(rootURL: URL, plan: SmartSearchPlan) async throws -> GlobalSearchPage {
        try await respond(rootURL, plan)
    }
}

actor SmartSearchInterpretationGate: SmartSearchInterpreting {
    private var continuation: CheckedContinuation<SmartSearchPlan, any Error>?
    private var requested = false
    private var requestWaiter: CheckedContinuation<Void, Never>?

    func interpret(_ query: String) async throws -> SmartSearchPlan {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            requested = true
            requestWaiter?.resume()
            requestWaiter = nil
        }
    }

    func waitUntilRequested() async {
        guard requested == false else { return }
        await withCheckedContinuation { requestWaiter = $0 }
    }

    func finish(with plan: SmartSearchPlan) {
        continuation?.resume(returning: plan)
        continuation = nil
    }
}
