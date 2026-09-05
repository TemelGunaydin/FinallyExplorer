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
}
