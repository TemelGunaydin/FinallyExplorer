import Foundation
import Testing
@testable import FinallyExplorer

struct VisualSearchQueryTests {
    @Test("Text matching folds case and accents and supplies a bounded excerpt around the match")
    func textEvidence() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Unrelated.jpg", "image")
        let text = String(repeating: "Earlier text. ", count: 60) + "CAFÉ invoice 4827" + String(repeating: " Later text.", count: 50)
        let snapshot = try await VisualSearchService(analyzer: FixedVisualAnalyzer(text: text)).scan(rootURL: fixture.source, includesHidden: false)
        let matches = try await VisualSearchQuery.search(snapshot.entries, query: "cafe 4827", mode: .text)
        let match = try #require(matches.first)
        #expect(match.labels.isEmpty)
        #expect(match.excerpt?.contains("CAFÉ invoice 4827") == true)
        #expect((match.excerpt?.count ?? .max) <= 242)
        #expect(try await VisualSearchQuery.search(snapshot.entries, query: "cafe nonexistent", mode: .both).isEmpty)
    }

    @Test("Text-only mode does not show images without recognized text")
    func textModeNeedsEvidence() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Invoice.jpg", "image")
        let snapshot = try await VisualSearchService(analyzer: FixedVisualAnalyzer(text: "")).scan(rootURL: fixture.source, includesHidden: false)
        #expect(try await VisualSearchQuery.search(snapshot.entries, query: "", mode: .text).isEmpty)
        #expect(try await VisualSearchQuery.search(snapshot.entries, query: "", mode: .labels).count == 1)
        #expect(try await VisualSearchQuery.search(snapshot.entries, query: "invoice", mode: .both).isEmpty)
    }

    @Test("Long queries are rejected, never silently truncated")
    func queryLimit() async {
        await #expect(throws: VisualSearchError.queryTooLong) {
            try await VisualSearchQuery.search([], query: String(repeating: "x", count: 201), mode: .both)
        }
    }
}
