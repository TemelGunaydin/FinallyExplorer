import Foundation
import Testing
@testable import FinallyExplorer

struct OfflineCatalogSearchTests {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Names and paths match all query tokens without disk access")
    func pathsAndTokens() async throws {
        let entries = [entry("Reports/Accounting Invoice.PDF"), entry("Reports/Notes.txt"), entry("Photos/Invoice.png")]
        #expect(try await OfflineCatalogSearch.search(entries, query: OfflineCatalogQuery(text: "  INVOICE   reports ")).entries.map(\.relativePath) == [entries[0].relativePath])
        #expect(try await OfflineCatalogSearch.search(entries, query: OfflineCatalogQuery(text: "nonexistent")).totalMatches == 0)
        #expect(try await OfflineCatalogSearch.search(entries, query: OfflineCatalogQuery(text: "   ")).totalMatches == 3)
    }

    @Test("Extension, minimum size and modification date combine as AND filters")
    func combinedFilters() async throws {
        let entries = [entry("Large.PDF", bytes: 4_000_000), entry("Small.pdf", bytes: 50), entry("Large.txt", bytes: 4_000_000), entry("Old.pdf", bytes: 4_000_000, date: date.addingTimeInterval(-100)), entry("Folder.pdf", directory: true)]
        let query = OfflineCatalogQuery(fileExtension: " .PDF ", minimumBytes: 1_000_000, modifiedSince: date)
        #expect(try await OfflineCatalogSearch.search(entries, query: query).entries.map(\.relativePath) == ["Large.PDF"])
        #expect(try await OfflineCatalogSearch.search(entries, query: OfflineCatalogQuery(fileExtension: ".*")).totalMatches == 0)
    }

    @Test("Rendering is capped while the complete matching count remains accurate")
    func resultLimit() async throws {
        let entries = (0..<OfflineCatalogValidation.entryLimit).map { entry("Report\($0).pdf") }
        let result = try await OfflineCatalogSearch.search(entries, query: OfflineCatalogQuery())
        #expect(result.entries.count == 200)
        #expect(result.totalMatches == OfflineCatalogValidation.entryLimit)
        #expect(try await OfflineCatalogSearch.search(entries, query: OfflineCatalogQuery(), limit: 0).entries.isEmpty)
        #expect(try await OfflineCatalogSearch.search(entries, query: OfflineCatalogQuery(text: "Report99999")).entries.map(\.relativePath) == ["Report99999.pdf"])
    }

    @Test("Cancelled searches do not produce stale results", .timeLimit(.minutes(1)))
    func cancelledSearch() async throws {
        let gate = FolderComparisonTestGate()
        let entries = [entry("Report.pdf")]
        let task = Task { await gate.pause(); return try await OfflineCatalogSearch.search(entries, query: OfflineCatalogQuery()) }
        await gate.waitUntilEntered()
        task.cancel(); await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    private func entry(_ path: String, bytes: Int64 = 50, date: Date? = nil, directory: Bool = false) -> OfflineCatalogEntry {
        OfflineCatalogEntry(relativePath: path, isDirectory: directory, byteCount: directory ? nil : bytes, modifiedAt: date ?? self.date, inode: 1)
    }
}
