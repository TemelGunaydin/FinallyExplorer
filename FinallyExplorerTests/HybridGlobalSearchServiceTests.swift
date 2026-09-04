//
//  HybridGlobalSearchServiceTests.swift
//  FinallyExplorerTests
//

import Foundation
import Testing
@testable import FinallyExplorer

struct HybridGlobalSearchServiceTests {
    @Test("Root name search uses the bounded persistent macOS index")
    func rootNameSearchUsesSpotlight() async throws {
        let resultURL = URL(filePath: "/Users/example/Annual Report.pdf")
        let spotlight = SpotlightGlobalSearchServiceFake(
            page: SpotlightGlobalSearchService.Page(
                hits: [
                    SpotlightGlobalSearchService.Hit(
                        url: resultURL,
                        isDirectory: false,
                        isImage: false,
                        byteSize: 42,
                        modificationDate: nil
                    )
                ],
                isTruncated: false
            )
        )
        let fallback = NameSearchFallbackFake(
            page: Self.fallbackPage(
                for: URL(filePath: "/Users/example/Should Not Appear.txt")
            )
        )
        let service = HybridGlobalSearchService(
            spotlightService: spotlight,
            nameFallback: fallback.dependency
        )

        let page = try await service.search(
            rootURL: URL(filePath: "/", directoryHint: .isDirectory),
            query: "annual report",
            scope: .names,
            contentMode: .plain
        )

        #expect(page.results.map(\.item.url) == [resultURL])
        #expect(page.results.first?.relativePath == "Users/example/Annual Report.pdf")
        #expect(page.isIndexWarming == false)
        #expect(
            await spotlight.requests()
                == [
                    SpotlightSearchRequest(
                        rootURL: URL(
                            filePath: "/",
                            directoryHint: .isDirectory
                        ),
                        query: "annual report",
                        maximumCandidateCount: 800
                    )
                ]
        )
        #expect(await fallback.searchRequests().isEmpty)

        await service.shutdown()
    }

    @Test("Spotlight mapping removes hidden and duplicate results")
    func spotlightMappingFiltersHiddenAndDuplicateResults() async throws {
        let visibleURL = URL(filePath: "/Users/example/report.txt")
        let hiddenURL = URL(filePath: "/Users/example/.cache/report.txt")
        let visibleHit = SpotlightGlobalSearchService.Hit(
            url: visibleURL,
            isDirectory: false,
            isImage: false,
            byteSize: 12,
            modificationDate: nil
        )
        let spotlight = SpotlightGlobalSearchServiceFake(
            page: SpotlightGlobalSearchService.Page(
                hits: [visibleHit, visibleHit, SpotlightGlobalSearchService.Hit(
                    url: hiddenURL,
                    isDirectory: false,
                    isImage: false,
                    byteSize: 8,
                    modificationDate: nil
                )],
                isTruncated: false
            )
        )
        let service = HybridGlobalSearchService(
            spotlightService: spotlight
        )

        let page = try await service.search(
            rootURL: URL(filePath: "/", directoryHint: .isDirectory),
            query: "report",
            scope: .names,
            contentMode: .plain
        )

        #expect(page.results.map(\.item.url) == [visibleURL])
        await service.shutdown()
    }

    @Test("Repeated Spotlight failures enable fallback only after successful searches")
    func repeatedSpotlightFailuresEnableCircuitBreaker() async throws {
        let fallbackURL = URL(filePath: "/Users/example/Fallback Report.pdf")
        let spotlight = SpotlightGlobalSearchServiceFake {
            throw HybridGlobalSearchTestError.spotlightUnavailable
        }
        let fallback = NameSearchFallbackFake(
            page: Self.fallbackPage(for: fallbackURL)
        )
        let service = HybridGlobalSearchService(
            spotlightService: spotlight,
            nameFallback: fallback.dependency
        )

        let page = try await service.search(
            rootURL: Self.rootURL,
            query: "fallback report",
            scope: .names,
            contentMode: .plain
        )
        _ = try await service.search(
            rootURL: Self.rootURL,
            query: "second fallback report",
            scope: .names,
            contentMode: .plain
        )
        _ = try await service.search(
            rootURL: Self.rootURL,
            query: "third fallback report",
            scope: .names,
            contentMode: .plain
        )

        #expect(page.results.map(\.item.url) == [fallbackURL])
        #expect(
            page.message?.text.contains("macOS Search was unavailable") == true
        )
        #expect(await spotlight.requests().count == 2)
        #expect(await fallback.searchRequests().count == 3)
        await service.shutdown()
    }

    @Test("A Spotlight timeout falls back without waiting for the slow query")
    func spotlightTimeoutUsesNameFallback() async throws {
        let fallbackURL = URL(filePath: "/Users/example/Timeout Result.txt")
        let spotlight = SpotlightGlobalSearchServiceFake {
            try await Task.sleep(for: .seconds(60))
            return Self.emptySpotlightPage
        }
        let fallback = NameSearchFallbackFake(
            page: Self.fallbackPage(for: fallbackURL)
        )
        let service = HybridGlobalSearchService(
            spotlightService: spotlight,
            spotlightTimeout: .zero,
            nameFallback: fallback.dependency
        )

        let page = try await service.search(
            rootURL: Self.rootURL,
            query: "timeout",
            scope: .names,
            contentMode: .plain
        )

        #expect(page.results.map(\.item.url) == [fallbackURL])
        #expect(await fallback.searchRequests().count == 1)
        await service.shutdown()
    }

    @Test("Cancelling a Spotlight query never starts fallback search")
    func cancelledSpotlightSearchDoesNotFallback() async throws {
        let spotlight = SpotlightGlobalSearchServiceFake {
            try await Task.sleep(for: .seconds(60))
            return Self.emptySpotlightPage
        }
        let fallback = NameSearchFallbackFake(
            page: Self.fallbackPage(
                for: URL(filePath: "/Users/example/Should Not Appear.txt")
            )
        )
        let service = HybridGlobalSearchService(
            spotlightService: spotlight,
            spotlightTimeout: .seconds(60),
            nameFallback: fallback.dependency
        )
        let task = Task {
            try await service.search(
                rootURL: Self.rootURL,
                query: "cancelled",
                scope: .names,
                contentMode: .plain
            )
        }

        try await spotlight.waitForRequestCount(1)
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await fallback.searchRequests().isEmpty)
        await service.shutdown()
    }

    @Test("Shutdown during a failed Spotlight query cannot recreate fallback")
    func shutdownDuringSpotlightDoesNotStartFallback() async throws {
        let spotlight = ControlledSpotlightGlobalSearchService()
        let fallback = NameSearchFallbackFake(
            page: Self.fallbackPage(
                for: URL(filePath: "/Users/example/Should Not Appear.txt")
            )
        )
        let service = HybridGlobalSearchService(
            spotlightService: spotlight,
            spotlightTimeout: .seconds(60),
            nameFallback: fallback.dependency
        )
        let task = Task {
            try await service.search(
                rootURL: Self.rootURL,
                query: "shutdown",
                scope: .names,
                contentMode: .plain
            )
        }

        try await spotlight.waitUntilRequested()
        await service.shutdown()
        await spotlight.fail()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await fallback.searchRequests().isEmpty)
    }

    @Test("An empty Spotlight result uses fuzzy fallback without tripping the breaker")
    func emptySpotlightResultUsesPerQueryFallback() async throws {
        let fallbackURL = URL(filePath: "/Users/example/Fuzzy Result.txt")
        let spotlight = SpotlightGlobalSearchServiceFake(
            page: Self.emptySpotlightPage
        )
        let fallback = NameSearchFallbackFake(
            page: Self.fallbackPage(for: fallbackURL)
        )
        let service = HybridGlobalSearchService(
            spotlightService: spotlight,
            nameFallback: fallback.dependency
        )

        let page = try await service.search(
            rootURL: Self.rootURL,
            query: "fzzy result",
            scope: .names,
            contentMode: .plain
        )
        let secondPage = try await service.search(
            rootURL: Self.rootURL,
            query: "another fzzy result",
            scope: .names,
            contentMode: .plain
        )

        #expect(page.results.map(\.item.url) == [fallbackURL])
        #expect(secondPage.results.map(\.item.url) == [fallbackURL])
        #expect(await spotlight.requests().count == 2)
        #expect(
            await fallback.searchRequests()
                == [
                    NameFallbackRequest(
                        rootURL: Self.rootURL,
                        query: "fzzy result"
                    ),
                    NameFallbackRequest(
                        rootURL: Self.rootURL,
                        query: "another fzzy result"
                    ),
                ]
        )

        // A successful empty query remains a per-query fallback, and a new
        // service lifecycle still starts with the persistent index.
        await service.shutdown()
        _ = try await service.search(
            rootURL: Self.rootURL,
            query: "after shutdown",
            scope: .names,
            contentMode: .plain
        )
        #expect(await spotlight.requests().count == 3)
        await service.shutdown()
    }

    private static let rootURL = URL(
        filePath: "/",
        directoryHint: .isDirectory
    )

    private nonisolated static let emptySpotlightPage =
        SpotlightGlobalSearchService.Page(
            hits: [],
            isTruncated: false
        )

    private static func fallbackPage(for url: URL) -> GlobalSearchPage {
        GlobalSearchPage(
            results: [
                ExplorerSearchResult(
                    id: "fallback:\(url.path(percentEncoded: false))",
                    item: FileItem(
                        url: url,
                        isDirectory: false,
                        isImage: false,
                        fileSize: 1,
                        modificationDate: nil
                    ),
                    relativePath: String(
                        url.path(percentEncoded: false).dropFirst()
                    ),
                    contentMatch: nil
                )
            ],
            message: nil
        )
    }
}

private nonisolated struct SpotlightSearchRequest: Equatable, Sendable {
    let rootURL: URL
    let query: String
    let maximumCandidateCount: Int
}

private actor SpotlightGlobalSearchServiceFake:
    SpotlightGlobalSearchServicing {
    private let response: @Sendable () async throws
        -> SpotlightGlobalSearchService.Page
    private var recordedRequests: [SpotlightSearchRequest] = []

    init(page: SpotlightGlobalSearchService.Page) {
        response = { page }
    }

    init(
        response: @escaping @Sendable () async throws
            -> SpotlightGlobalSearchService.Page
    ) {
        self.response = response
    }

    func search(
        rootURL: URL,
        query: String,
        maximumCandidateCount: Int
    ) async throws -> SpotlightGlobalSearchService.Page {
        recordedRequests.append(
            SpotlightSearchRequest(
                rootURL: rootURL,
                query: query,
                maximumCandidateCount: maximumCandidateCount
            )
        )
        return try await response()
    }

    func requests() -> [SpotlightSearchRequest] {
        recordedRequests
    }

    func waitForRequestCount(_ count: Int) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while recordedRequests.count < count, clock.now < deadline {
            await Task.yield()
        }
        guard recordedRequests.count >= count else {
            throw HybridGlobalSearchTestError.timedOutWaitingForRequest
        }
    }
}

private nonisolated struct NameFallbackRequest: Equatable, Sendable {
    let rootURL: URL
    let query: String
}

private actor NameSearchFallbackFake {
    private let page: GlobalSearchPage
    private var recordedSearchRequests: [NameFallbackRequest] = []

    init(page: GlobalSearchPage) {
        self.page = page
    }

    nonisolated var dependency: HybridGlobalNameSearchFallback {
        HybridGlobalNameSearchFallback(
            search: { [self] rootURL, query in
                await search(rootURL: rootURL, query: query)
            }
        )
    }

    private func search(
        rootURL: URL,
        query: String
    ) -> GlobalSearchPage {
        recordedSearchRequests.append(
            NameFallbackRequest(rootURL: rootURL, query: query)
        )
        return page
    }

    func searchRequests() -> [NameFallbackRequest] {
        recordedSearchRequests
    }
}

private actor ControlledSpotlightGlobalSearchService:
    SpotlightGlobalSearchServicing {
    private var continuation: CheckedContinuation<
        SpotlightGlobalSearchService.Page,
        any Error
    >?

    func search(
        rootURL: URL,
        query: String,
        maximumCandidateCount: Int
    ) async throws -> SpotlightGlobalSearchService.Page {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilRequested() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while continuation == nil, clock.now < deadline {
            await Task.yield()
        }
        guard continuation != nil else {
            throw HybridGlobalSearchTestError.timedOutWaitingForRequest
        }
    }

    func fail() {
        continuation?.resume(
            throwing: HybridGlobalSearchTestError.spotlightUnavailable
        )
        continuation = nil
    }
}

private nonisolated enum HybridGlobalSearchTestError: Error, Sendable {
    case spotlightUnavailable
    case timedOutWaitingForRequest
}
