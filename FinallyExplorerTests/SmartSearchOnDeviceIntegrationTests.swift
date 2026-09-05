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

    @Test("The actual model does not silently drop unsupported actions or size filters", .timeLimit(.minutes(1)), arguments: [
        "Delete all PDF files", "Find videos larger than 2 GB",
    ])
    func unsupportedRequests(_ query: String) async {
        let service = FoundationModelsSmartSearchService()
        await #expect(throws: SmartSearchError.unsupportedRequest) {
            try await service.interpret(query)
        }
    }
}
