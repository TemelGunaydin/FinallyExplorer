import Testing
@testable import FinallyExplorer

struct SmartSearchRequestValidatorTests {
    @Test("Explicit file-operation commands are rejected before inference", arguments: [
        "Delete all PDF files", "Please copy my documents", "Can you move the report", "Open Terminal",
        "Rename the files", "trash the PDFs", "Could you uninstall the app", "Run this script",
    ])
    func rejectsActions(_ text: String) {
        #expect(throws: SmartSearchError.unsupportedRequest) {
            try SmartSearchRequestValidator.validatedQuery(text)
        }
    }

    @Test("Action words remain valid in a file lookup", arguments: [
        "Find delete handler.swift", "Find the copy of my report", "PDFs in Downloads from last week",
        "Find the accounting report from 2 days ago",
        "Find images with beach in the filename",
    ])
    func acceptsSearches(_ text: String) throws {
        #expect(try SmartSearchRequestValidator.validatedQuery(text) == text)
    }

    @Test("Empty, oversized and control-character input is bounded", arguments: [
        "   ", String(repeating: "a", count: 501), "report\0pdf", "report\nPDF",
    ])
    func rejectsMalformedInput(_ text: String) {
        #expect(throws: SmartSearchError.invalidRequest) {
            try SmartSearchRequestValidator.validatedQuery(text)
        }
    }

    @Test("Unsupported conditions cannot silently turn into a broader search", arguments: [
        "Find videos larger than 2 GB", "Files under 50MB", "Photos downloaded yesterday",
        "Files imported last week", "Find photos depicting the sea", "Pictures of a beach",
    ])
    func unsupportedCriteria(_ text: String) {
        #expect(throws: SmartSearchError.unsupportedRequest) {
            try SmartSearchRequestValidator.validatedQuery(text)
        }
    }

    @Test("Image keywords require an explicit filename request, not pretend visual recognition")
    func imageSubjectBoundary() throws {
        let plan = try SmartSearchTestFixtures.plan(SmartSearchTestFixtures.interpretation(keywords: ["beach"], kind: .image, dateRule: .none))
        #expect(throws: SmartSearchError.unsupportedRequest) {
            try SmartSearchRequestValidator.validateCapabilities(plan, query: "Find beach photos")
        }
        try SmartSearchRequestValidator.validateCapabilities(plan, query: "Find photos named beach")
        try SmartSearchRequestValidator.validateCapabilities(plan, query: "Keep these results, but only JPEG files", previousPlan: plan)
    }

    @Test("Generic type words do not become unwanted keywords, but explicit names are preserved")
    func redundantTypeWords() {
        let value = SmartSearchTestFixtures.interpretation(keywords: ["photos"], kind: .image, dateField: .captured)
        #expect(SmartSearchRequestValidator.removingRedundantTypeWords(value, query: "Photos taken three days ago").keywords.isEmpty)
        #expect(SmartSearchRequestValidator.removingRedundantTypeWords(value, query: "Images named photos").keywords == ["photos"])
        let report = SmartSearchTestFixtures.interpretation(keywords: ["pdfs", "accounting", "report"], kind: .pdf)
        #expect(SmartSearchRequestValidator.removingRedundantTypeWords(report, query: "Accounting report PDFs").keywords == ["accounting", "report"])
    }
}
