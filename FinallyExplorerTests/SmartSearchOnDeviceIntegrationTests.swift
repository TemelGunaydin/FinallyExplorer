import Foundation
import FoundationModels
import Testing
@testable import FinallyExplorer

/// Deliberately kept separate from deterministic regression suites. These tests
/// exercise Apple's real installed model when it is available, using only
/// synthetic descriptions and never reading the user's documents.
@Suite(.serialized, .enabled(
    if: SystemLanguageModel.default.availability == .available,
    "Requires the downloaded, enabled on-device Apple Intelligence model."
))
struct SmartSearchOnDeviceIntegrationTests {
    @Test("The actual model extracts the accounting-report example", .timeLimit(.minutes(1)))
    func accountingReport() async throws {
        let now = try SmartSearchTestFixtures.date("2026-09-05T12:00:00+03:00")
        let service = FoundationModelsSmartSearchService(now: { now }, calendar: SmartSearchTestFixtures.calendar())
        let plan = try await service.interpret("Find the accounting report from 2 days ago")
        #expect(plan.keywords.contains("accounting"))
        #expect(plan.keywords.contains("report"))
        #expect(plan.dateInterval == (try SmartSearchTestFixtures.plan().dateInterval))
        #expect(plan.dateField == .modified)
        #expect(plan.kind == .any)
        #expect(plan.location == .anywhere)
    }

    @Test("The actual model extracts a type, standard folder, and calendar week", .timeLimit(.minutes(1)))
    func pdfsInDownloads() async throws {
        let now = try SmartSearchTestFixtures.date("2026-09-05T12:00:00+03:00")
        let service = FoundationModelsSmartSearchService(now: { now }, calendar: SmartSearchTestFixtures.calendar())
        let plan = try await service.interpret("PDFs in Downloads from last week")
        #expect(plan.keywords.isEmpty)
        #expect(plan.kind == .pdf)
        #expect(plan.location == .downloads)
        let expected = try SmartSearchTestFixtures.plan(SmartSearchTestFixtures.interpretation(dateRule: .lastWeek))
        #expect(plan.dateInterval == expected.dateInterval)
    }

    @Test("The actual model retains subjects in other date-filtered searches", .timeLimit(.minutes(1)))
    func invoiceSpreadsheets() async throws {
        let now = try SmartSearchTestFixtures.date("2026-09-05T12:00:00+03:00")
        let service = FoundationModelsSmartSearchService(now: { now }, calendar: SmartSearchTestFixtures.calendar())
        let plan = try await service.interpret("Show invoice spreadsheets modified yesterday")
        #expect(plan.keywords.contains("invoice"))
        #expect(plan.kind == .spreadsheet)
        let expected = try SmartSearchTestFixtures.plan(SmartSearchTestFixtures.interpretation(dayCount: 1))
        #expect(plan.dateInterval == expected.dateInterval)
    }

    @Test("The service rejects unsupported actions, sizes, visuals, and download dates", .timeLimit(.minutes(1)), arguments: [
        "Delete all PDF files", "Find videos larger than 2 GB", "Find photos depicting the sea", "Files downloaded yesterday",
    ])
    func unsupportedRequests(_ query: String) async {
        let service = FoundationModelsSmartSearchService()
        await #expect(throws: SmartSearchError.unsupportedRequest) {
            try await service.interpret(query)
        }
    }

    @Test("The on-device service refines a report search without losing the topic or dates", .timeLimit(.minutes(1)))
    func followUpSearch() async throws {
        let now = try SmartSearchTestFixtures.date("2026-09-05T12:00:00+03:00")
        let service = FoundationModelsSmartSearchService(now: { now }, calendar: SmartSearchTestFixtures.calendar())
        let previous = try SmartSearchTestFixtures.plan()
        let pdfs = try await service.interpret("Only PDFs", previousPlan: previous)
        #expect(pdfs.kind == .pdf)
        #expect(pdfs.keywords == previous.keywords)
        #expect(pdfs.dateInterval == previous.dateInterval)
        let documents = try await service.interpret("In Documents instead", previousPlan: pdfs)
        #expect(documents.location == .documents)
        #expect(documents.kind == .pdf)
        #expect(documents.keywords == previous.keywords)
        #expect(documents.dateInterval == previous.dateInterval)
    }

    @Test("The actual model distinguishes photo capture dates and extension refinements", .timeLimit(.minutes(1)))
    func photoCaptureFollowUp() async throws {
        let now = try SmartSearchTestFixtures.date("2026-09-05T12:00:00+03:00")
        let service = FoundationModelsSmartSearchService(now: { now }, calendar: SmartSearchTestFixtures.calendar())
        let photos = try await service.interpret("Photos taken three days ago")
        #expect(photos.kind == .image)
        #expect(photos.dateField == .captured)
        #expect(photos.keywords.isEmpty)
        #expect(photos.dateInterval == (try SmartSearchTestFixtures.plan(SmartSearchTestFixtures.interpretation(dayCount: 3))).dateInterval)
        let heic = try await service.interpret("Only HEIC", previousPlan: photos)
        #expect(heic.fileExtensions == ["heic"])
        #expect(heic.kind == .image)
        #expect(heic.dateField == .captured)
        #expect(heic.dateInterval == photos.dateInterval)
        #expect(heic.keywords.isEmpty)
    }

    @Test("The actual model handles a follow-up outside the quick-refinement grammar", .timeLimit(.minutes(1)))
    func modelInterpretedFollowUp() async throws {
        let now = try SmartSearchTestFixtures.date("2026-09-05T12:00:00+03:00")
        let previous = try SmartSearchTestFixtures.plan()
        let service = FoundationModelsSmartSearchService(now: { now }, calendar: SmartSearchTestFixtures.calendar())
        let query = "Keep the same search, but limit it to PDF files."
        #expect(try SmartSearchQuickRefinement.resolve(query, previous: previous, now: now, calendar: .current) == nil)
        let plan = try await service.interpret(query, previousPlan: previous)
        #expect(plan.kind == .pdf)
        #expect(plan.keywords == previous.keywords)
        #expect(plan.dateInterval == previous.dateInterval)
        #expect(plan.location == previous.location)
    }
}
