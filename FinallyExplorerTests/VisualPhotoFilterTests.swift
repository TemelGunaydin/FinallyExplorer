import Foundation
import Testing
@testable import FinallyExplorer

struct VisualPhotoFilterTests {
    private let calendar = SmartSearchTestFixtures.calendar()
    private var now: Date { get throws { try SmartSearchTestFixtures.date("2026-09-09T12:00:00+03:00") } }

    @Test("Scene, date and type are combined without model latency", arguments: [
        "Find HEIC beach photos from last week", "Find HEIC photos taken by the sea from last week",
        "Find beach photos in HEIC from last week",
    ])
    func combined(_ query: String) async throws {
        let instant = try now
        let interpreter = FoundationModelsVisualInterpreter(now: { instant }, calendar: calendar)
        let plan = try await interpreter.interpret(query)
        #expect(plan.concepts == [["beach", "seashore", "coast", "coastal", "ocean", "sea"]])
        #expect(plan.filters.fileExtensions == ["heic"])
        #expect(plan.filters.captureInterval?.start == (try SmartSearchTestFixtures.date("2026-08-31T00:00:00+03:00")))
        #expect(plan.filters.captureInterval?.end == (try SmartSearchTestFixtures.date("2026-09-07T00:00:00+03:00")))
    }

    @Test("Date formats use existing calendar semantics", arguments: ["today", "yesterday", "3 days ago", "last 3 days", "last week", "this week", "last month", "this month", "on 2026-09-01", "between 2026-09-01 and 2026-09-04"])
    func dateFormats(_ date: String) throws {
        let result = try VisualPhotoRequest.initial("Find beach photos from \(date)", now: now, calendar: calendar)
        #expect(result.scene == "find beach photos")
        #expect(result.filters.captureInterval != nil)
    }

    @Test("Invalid dates never produce a broadened result", arguments: [
        "Find beach photos from last 0 days", "Find beach photos from 9999 days ago", "Find beach photos on 2026-02-30",
        "Find beach photos between 2026-09-05 and 2026-09-01",
    ])
    func rejectInvalidDates(_ query: String) async {
        await #expect(throws: SmartSearchError.invalidInterpretation) { try await FoundationModelsVisualInterpreter().interpret(query) }
    }

    @Test("Unsupported criteria are refused before calling the model", arguments: [
        "Find RAW photos by the sea", "Find beach photos modified yesterday", "Find beach photos before yesterday",
    ])
    func rejectUnsupportedCriteria(_ query: String) async {
        await #expect(throws: VisualDescriptionError.unsupportedRequest) { try await FoundationModelsVisualInterpreter().interpret(query) }
    }

    @Test("Type follow-ups preserve the exact resolved scene and date, including across midnight")
    func refinements() async throws {
        let instant = try now
        let previous = try await FoundationModelsVisualInterpreter(now: { instant }, calendar: calendar).interpret("Find beach photos from yesterday")
        let nextDay = instant.addingTimeInterval(86_400)
        let heic = try #require(try VisualPhotoRequest.refine("Only HEIC", previous: previous, now: nextDay, calendar: calendar))
        #expect(heic.concepts == previous.concepts)
        #expect(heic.filters.captureInterval == previous.filters.captureInterval)
        #expect(heic.filters.fileExtensions == ["heic"])
        let date = try #require(try VisualPhotoRequest.refine("Last week instead", previous: heic, now: instant, calendar: calendar))
        #expect(date.filters.fileExtensions == ["heic"])
        #expect(date.filters.captureInterval != heic.filters.captureInterval)
        let allDates = try #require(try VisualPhotoRequest.refine("All dates", previous: date, now: instant, calendar: calendar))
        #expect(allDates.filters.captureInterval == nil)
        #expect(allDates.filters.fileExtensions == ["heic"])
        let allTypes = try #require(try VisualPhotoRequest.refine("All image types", previous: allDates, now: instant, calendar: calendar))
        #expect(allTypes.filters.fileExtensions.isEmpty)
        #expect(allTypes.concepts == previous.concepts)
        #expect(throws: VisualDescriptionError.unsupportedRequest) {
            try VisualPhotoRequest.refine("Only RAW", previous: previous, now: instant, calendar: calendar)
        }
    }

    @Test("Capture date intervals stay correct on daylight-saving transitions")
    func daylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let spring = try VisualPhotoRequest.dateInterval("on 2026-03-08", now: now, calendar: calendar)
        let fall = try VisualPhotoRequest.dateInterval("on 2026-11-01", now: now, calendar: calendar)
        #expect(spring.duration == 23 * 3600)
        #expect(fall.duration == 25 * 3600)
    }

    @Test("Dates use a half-open interval, missing EXIF never falls back to filesystem dates")
    func evidenceFiltering() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("original.JPG", "fixture")
        let entry = try #require(try await VisualSearchService(analyzer: FixedVisualAnalyzer()).scan(rootURL: fixture.source, includesHidden: false).entries.first)
        let interval = try VisualPhotoRequest.dateInterval("yesterday", now: now, calendar: calendar)
        let filters = try VisualPhotoFilters(captureInterval: interval, fileExtensions: ["jpg"])
        #expect(filters.includes(entry) == false)
        for (instant, included) in [(interval.start, true), (interval.end.addingTimeInterval(-1), true), (interval.end, false), (interval.start.addingTimeInterval(-1), false)] {
            var evidence = entry.evidence
            evidence.captureDate = PhotoCaptureDate(date: instant, assumedLocalTimeZone: false)
            let candidate = VisualSearchSnapshot.Entry(relativePath: entry.relativePath, state: entry.state, evidence: evidence)
            #expect(filters.includes(candidate) == included)
            let onlyHEIC = try VisualPhotoFilters(captureInterval: interval, fileExtensions: ["heic"])
            #expect(onlyHEIC.includes(candidate) == false)
        }
    }

    @MainActor @Test("Refinement failures keep the last plan; new search and analysis clear it")
    func lifecycle() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Photo.jpg", "fixture")
        let model = VisualSearchModel(service: VisualSearchService(analyzer: FixedVisualAnalyzer()))
        model.setSource(fixture.source)
        await model.analyze()?.value
        model.naturalDraft = "Only HEIC"
        await model.findPhotos()?.value
        #expect(model.errorMessage != nil)
        #expect(model.naturalPlan == nil)
        model.naturalDraft = "Find beach photos from last week"
        await model.findPhotos()?.value
        let previous = try #require(model.naturalPlan)
        #expect(model.missingCaptureDateCount == 1)
        model.naturalDraft = "Only HEIC"
        await model.findPhotos()?.value
        #expect(model.naturalPlan?.filters.captureInterval == previous.filters.captureInterval)
        #expect(model.naturalPlan?.filters.fileExtensions == ["heic"])
        model.naturalDraft = "Only RAW"
        await model.findPhotos()?.value
        #expect(model.errorMessage != nil)
        #expect(model.naturalPlan?.filters.fileExtensions == ["heic"])
        model.startNewPhotoSearch()
        await model.waitForSearch()
        #expect(model.snapshot != nil)
        #expect(model.naturalPlan == nil)
        #expect(model.naturalDraft.isEmpty)
        model.naturalDraft = "Find beach photos"
        await model.findPhotos()?.value
        #expect(model.matches.count == 1)
        await model.analyze()?.value
        await model.waitForSearch()
        #expect(model.naturalPlan == nil)
    }
}
