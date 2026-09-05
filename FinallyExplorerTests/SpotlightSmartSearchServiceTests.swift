import Foundation
import Testing
@testable import FinallyExplorer

struct SpotlightSmartSearchServiceTests {
    @Test("Validated filters reach Spotlight before the result limit; content-only hits survive")
    func forwardsPlanWithoutFilenameOnlyFiltering() async throws {
        let plan = try SmartSearchTestFixtures.plan()
        let root = URL(filePath: "/fixture", directoryHint: .isDirectory)
        let service = SpotlightSmartSearchService { receivedRoot, receivedPlan in
            #expect(receivedRoot == root)
            #expect(receivedPlan == plan)
            return SpotlightGlobalSearchService.Page(hits: [Self.hit("/fixture/scan.pdf")], isTruncated: false)
        }
        let page = try await service.search(rootURL: root, plan: plan)
        #expect(page.results.map(\.item.name) == ["scan.pdf"])
        #expect(page.isIndexWarming == false)
    }

    @Test("Duplicate, hidden, and out-of-scope catalog hits are never exposed")
    func validatesReturnedURLs() async throws {
        let service = SpotlightSmartSearchService { _, _ in
            SpotlightGlobalSearchService.Page(hits: [
                Self.hit("/fixture/report.pdf"), Self.hit("/fixture/report.pdf"),
                Self.hit("/fixture/.private/report.pdf"), Self.hit("/fixture-other/report.pdf"),
            ], isTruncated: false)
        }
        let page = try await service.search(rootURL: URL(filePath: "/fixture"), plan: SmartSearchTestFixtures.plan())
        #expect(page.results.map(\.item.name) == ["report.pdf"])
    }

    @Test("Result truncation is visible and does not trigger a new disk scan")
    func boundedResults() async throws {
        let service = SpotlightSmartSearchService { _, _ in
            SpotlightGlobalSearchService.Page(
                hits: (0..<150).map { Self.hit("/fixture/report-\($0).pdf") },
                isTruncated: false
            )
        }
        let page = try await service.search(rootURL: URL(filePath: "/fixture"), plan: SmartSearchTestFixtures.plan())
        #expect(page.results.count == 120)
        #expect(page.message?.isError == false)
        #expect(page.isIndexWarming == false)
    }

    @Test("A timed-out catalog query is cancelled")
    func timeout() async throws {
        let service = SpotlightSmartSearchService(timeout: .zero) { _, _ in
            try await Task.sleep(for: .seconds(60))
            Issue.record("The timeout must cancel the pending catalog request.")
            return SpotlightGlobalSearchService.Page(hits: [], isTruncated: false)
        }
        await #expect(throws: SmartSearchError.timedOut) {
            try await service.search(rootURL: URL(filePath: "/fixture"), plan: SmartSearchTestFixtures.plan())
        }
    }

    private static func hit(_ path: String) -> SpotlightGlobalSearchService.Hit {
        SpotlightGlobalSearchService.Hit(
            url: URL(filePath: path), isDirectory: false, isImage: false, byteSize: 100, modificationDate: nil
        )
    }
}
