import Foundation
import Testing
@testable import FinallyExplorer

struct SpotlightSmartSearchServiceTests {
    @Test("Validated filters reach Spotlight before the result limit; content-only hits survive")
    func forwardsPlanWithoutFilenameOnlyFiltering() async throws {
        let plan = try SmartSearchTestFixtures.plan()
        let root = URL(filePath: "/fixture", directoryHint: .isDirectory)
        let service = SpotlightSmartSearchService(query: { receivedRoot, receivedPlan in
            #expect(receivedRoot == root)
            #expect(receivedPlan == plan)
            return SpotlightGlobalSearchService.Page(hits: [Self.hit("/fixture/scan.pdf")], isTruncated: false)
        })
        let page = try await service.search(rootURL: root, plan: plan)
        #expect(page.results.map(\.item.name) == ["scan.pdf"])
        #expect(page.isIndexWarming == false)
    }

    @Test("Duplicate, hidden, and out-of-scope catalog hits are never exposed")
    func validatesReturnedURLs() async throws {
        let service = SpotlightSmartSearchService(query: { _, _ in
            SpotlightGlobalSearchService.Page(hits: [
                Self.hit("/fixture/report.pdf"), Self.hit("/fixture/report.pdf"),
                Self.hit("/fixture/.private/report.pdf"), Self.hit("/fixture-other/report.pdf"),
            ], isTruncated: false)
        })
        let page = try await service.search(rootURL: URL(filePath: "/fixture"), plan: SmartSearchTestFixtures.plan())
        #expect(page.results.map(\.item.name) == ["report.pdf"])
    }

    @Test("Result truncation is visible and does not trigger a new disk scan")
    func boundedResults() async throws {
        let service = SpotlightSmartSearchService(query: { _, _ in
            SpotlightGlobalSearchService.Page(
                hits: (0..<150).map { Self.hit("/fixture/report-\($0).pdf") },
                isTruncated: false
            )
        })
        let page = try await service.search(rootURL: URL(filePath: "/fixture"), plan: SmartSearchTestFixtures.plan())
        #expect(page.results.count == 120)
        #expect(page.message?.isError == false)
        #expect(page.isIndexWarming == false)
    }

    @Test("A timed-out catalog query is cancelled")
    func timeout() async throws {
        let service = SpotlightSmartSearchService(timeout: .zero, query: { _, _ in
            try await Task.sleep(for: .seconds(60))
            Issue.record("The timeout must cancel the pending catalog request.")
            return SpotlightGlobalSearchService.Page(hits: [], isTruncated: false)
        })
        await #expect(throws: SmartSearchError.timedOut) {
            try await service.search(rootURL: URL(filePath: "/fixture"), plan: SmartSearchTestFixtures.plan())
        }
    }

    @Test("Capture-date matches must pass EXIF verification with an exclusive end boundary")
    func verifiesCaptureDates() async throws {
        let plan = try SmartSearchTestFixtures.plan(SmartSearchTestFixtures.interpretation(keywords: [], kind: .image, dateField: .captured))
        let interval = try #require(plan.dateInterval)
        let service = SpotlightSmartSearchService(captureDateReader: { url in
            switch url.lastPathComponent {
            case "start.jpg": PhotoCaptureDate(date: interval.start, assumedLocalTimeZone: true)
            case "end.jpg": PhotoCaptureDate(date: interval.end, assumedLocalTimeZone: false)
            case "before.jpg": PhotoCaptureDate(date: interval.start.addingTimeInterval(-1), assumedLocalTimeZone: false)
            default: nil
            }
        }) { _, receivedPlan in
            #expect(receivedPlan == plan)
            return SpotlightGlobalSearchService.Page(hits: ["start.jpg", "end.jpg", "before.jpg", "unknown.jpg"].map {
                SpotlightGlobalSearchService.Hit(url: URL(filePath: "/fixture/\($0)"), isDirectory: false, isImage: true, byteSize: 100, modificationDate: interval.start)
            }, isTruncated: false)
        }
        let page = try await service.search(rootURL: URL(filePath: "/fixture"), plan: plan)
        #expect(page.results.map(\.item.name) == ["start.jpg"])
        #expect(page.results.first?.captureDate?.date == interval.start)
        #expect(page.message?.text.contains("1 candidate") == true)
        #expect(page.message?.text.contains("time zone") == true)
        #expect(page.message?.text.contains("Photos-library") == true)
    }

    @Test("Smart search rejects symlinks that resolve outside its search root")
    func symlinkScope() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let link = root.appending(path: "escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.deletingLastPathComponent())
        let service = SpotlightSmartSearchService(query: { _, _ in
            SpotlightGlobalSearchService.Page(hits: [Self.hit(link.appending(path: "report.pdf").path())], isTruncated: false)
        })
        let page = try await service.search(rootURL: root, plan: SmartSearchTestFixtures.plan())
        #expect(page.results.isEmpty)
    }

    private static func hit(_ path: String) -> SpotlightGlobalSearchService.Hit {
        SpotlightGlobalSearchService.Hit(
            url: URL(filePath: path), isDirectory: false, isImage: false, byteSize: 100, modificationDate: nil
        )
    }
}
