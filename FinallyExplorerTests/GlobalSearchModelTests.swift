//
//  GlobalSearchModelTests.swift
//  FinallyExplorerTests
//

import Foundation
import Testing
@testable import FinallyExplorer

@MainActor
struct GlobalSearchModelTests {
    private let rootURL = URL(filePath: "/", directoryHint: .isDirectory)

    @Test("The closest result starts selected and arrow movement wraps at both bounds")
    func keyboardSelectionWraps() async throws {
        let results = [
            globalResult(named: "alpha.txt"),
            globalResult(named: "beta.txt"),
            globalResult(named: "gamma.txt"),
        ]
        let service = GlobalSearchServiceStub(
            pages: ["a": GlobalSearchPage(results: results, message: nil)]
        )
        let model = GlobalSearchModel(service: service, debounce: {})
        model.query = "a"

        await model.search(in: rootURL)
        #expect(model.selectedResultID == results[0].id)

        model.moveSelection(.previous)
        #expect(model.selectedResultID == results[2].id)

        model.moveSelection(.next)
        #expect(model.selectedResultID == results[0].id)

        model.moveSelection(.next)
        #expect(model.selectedResultID == results[1].id)

        let unknown = globalResult(named: "not-in-results.txt")
        model.select(unknown)
        #expect(model.selectedResultID == results[1].id)
    }

    @Test("Blank input performs no I/O and clearing removes every visible state value")
    func blankAndClearAreSideEffectFree() async {
        let service = GlobalSearchServiceStub(pages: [:])
        let model = GlobalSearchModel(service: service, debounce: {})

        model.query = "   \n"
        await model.search(in: rootURL)
        #expect(await service.recordedCalls().isEmpty)
        #expect(model.results.isEmpty)
        #expect(model.selectedResultID == nil)
        #expect(model.isSearching == false)

        model.query = "needle"
        model.clear()
        #expect(model.query.isEmpty)
        #expect(model.message == nil)
    }

    @Test("Content scope and grep mode are forwarded without being weakened")
    func forwardsGrepConfiguration() async throws {
        let result = globalResult(named: "Source.swift", content: "let needle = 1")
        let service = GlobalSearchServiceStub(
            pages: [
                "needle": GlobalSearchPage(results: [result], message: nil)
            ]
        )
        let model = GlobalSearchModel(service: service, debounce: {})
        model.query = "needle"
        model.scope = .contents
        model.contentMode = .regex

        await model.search(in: rootURL)

        let call = try #require(await service.recordedCalls().first)
        #expect(call.rootURL == rootURL)
        #expect(call.query == "needle")
        #expect(call.scope == .contents)
        #expect(call.contentMode == .regex)
        #expect(model.results == [result])
    }

    @Test("A late result from an older query cannot corrupt the newest search")
    func staleCompletionIsDiscarded() async {
        let service = ControlledGlobalSearchService()
        let model = GlobalSearchModel(service: service, debounce: {})

        model.query = "old"
        let oldTask = Task { await model.search(in: rootURL) }
        await service.waitUntilRequested("old")

        model.query = "new"
        let newTask = Task { await model.search(in: rootURL) }
        await service.waitUntilRequested("new")

        let newResult = globalResult(named: "new.txt")
        await service.resolve(
            "new",
            with: GlobalSearchPage(results: [newResult], message: nil)
        )
        await newTask.value

        let oldResult = globalResult(named: "old.txt")
        await service.resolve(
            "old",
            with: GlobalSearchPage(results: [oldResult], message: nil)
        )
        await oldTask.value

        #expect(model.query == "new")
        #expect(model.results == [newResult])
        #expect(model.selectedResultID == newResult.id)
    }

    @Test("A partial FFF index refreshes the active query when warm-up completes")
    func warmIndexRefreshesActiveQuery() async {
        let result = globalResult(named: "eventual.txt")
        let service = WarmingGlobalSearchService(result: result)
        let model = GlobalSearchModel(service: service, debounce: {})
        model.query = "eventual"

        await model.search(in: rootURL)
        #expect(model.results.isEmpty)
        #expect(model.message == .notice("Indexing for testing."))

        await service.waitUntilWarmupIsObserved()
        await service.finishInitialScan()

        for _ in 0..<1_000 {
            if model.results == [result] { break }
            await Task.yield()
        }

        #expect(model.results == [result])
        #expect(model.selectedResultID == result.id)
        #expect(await service.searchCount() == 2)
        await model.shutdown()
    }

    @Test("Service failures become visible and shutdown releases the service")
    func errorAndShutdownLifecycle() async {
        let service = GlobalSearchServiceStub(
            pages: [:],
            error: GlobalSearchTestError.failed
        )
        let model = GlobalSearchModel(service: service, debounce: {})
        model.query = "needle"

        await model.search(in: rootURL)
        #expect(model.results.isEmpty)
        #expect(model.message == .error("Search failed for testing."))

        await model.shutdown()
        #expect(await service.shutdownCount() == 1)
        #expect(model.message == nil)
    }
}

private nonisolated struct GlobalSearchCall: Sendable {
    let rootURL: URL
    let query: String
    let scope: ExplorerSearchScope
    let contentMode: FFFContentSearchMode
}

private actor GlobalSearchServiceStub: GlobalSearchServicing {
    private let pages: [String: GlobalSearchPage]
    private let error: GlobalSearchTestError?
    private var calls: [GlobalSearchCall] = []
    private var shutdowns = 0

    init(
        pages: [String: GlobalSearchPage],
        error: GlobalSearchTestError? = nil
    ) {
        self.pages = pages
        self.error = error
    }

    func search(
        rootURL: URL,
        query: String,
        scope: ExplorerSearchScope,
        contentMode: FFFContentSearchMode
    ) async throws -> GlobalSearchPage {
        calls.append(
            GlobalSearchCall(
                rootURL: rootURL,
                query: query,
                scope: scope,
                contentMode: contentMode
            )
        )
        if let error { throw error }
        return pages[query] ?? GlobalSearchPage(results: [], message: nil)
    }

    func shutdown() async {
        shutdowns += 1
    }

    func recordedCalls() -> [GlobalSearchCall] {
        calls
    }

    func shutdownCount() -> Int {
        shutdowns
    }
}

private actor ControlledGlobalSearchService: GlobalSearchServicing {
    private var continuations: [
        String: CheckedContinuation<GlobalSearchPage, any Error>
    ] = [:]

    func search(
        rootURL: URL,
        query: String,
        scope: ExplorerSearchScope,
        contentMode: FFFContentSearchMode
    ) async throws -> GlobalSearchPage {
        try await withCheckedThrowingContinuation { continuation in
            continuations[query] = continuation
        }
    }

    func shutdown() async {
        let pendingContinuations = continuations.values
        continuations.removeAll()
        for continuation in pendingContinuations {
            continuation.resume(throwing: CancellationError())
        }
    }

    func waitUntilRequested(_ query: String) async {
        while continuations[query] == nil {
            await Task.yield()
        }
    }

    func resolve(_ query: String, with page: GlobalSearchPage) {
        continuations.removeValue(forKey: query)?.resume(returning: page)
    }
}

private actor WarmingGlobalSearchService: GlobalSearchServicing {
    private let result: ExplorerSearchResult
    private var searches = 0
    private var warmupContinuation: CheckedContinuation<Void, any Error>?

    init(result: ExplorerSearchResult) {
        self.result = result
    }

    func search(
        rootURL: URL,
        query: String,
        scope: ExplorerSearchScope,
        contentMode: FFFContentSearchMode
    ) async throws -> GlobalSearchPage {
        searches += 1
        if searches == 1 {
            return GlobalSearchPage(
                results: [],
                message: .notice("Indexing for testing."),
                isIndexWarming: true
            )
        }
        return GlobalSearchPage(results: [result], message: nil)
    }

    func waitForInitialScan(rootURL: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            warmupContinuation = continuation
        }
    }

    func shutdown() async {
        warmupContinuation?.resume(throwing: CancellationError())
        warmupContinuation = nil
    }

    func waitUntilWarmupIsObserved() async {
        while warmupContinuation == nil {
            await Task.yield()
        }
    }

    func finishInitialScan() {
        warmupContinuation?.resume()
        warmupContinuation = nil
    }

    func searchCount() -> Int {
        searches
    }
}

private nonisolated enum GlobalSearchTestError: LocalizedError {
    case failed

    var errorDescription: String? {
        "Search failed for testing."
    }
}

private nonisolated func globalResult(
    named name: String,
    content: String? = nil
) -> ExplorerSearchResult {
    let url = URL(filePath: "/Fixture/\(name)", directoryHint: .notDirectory)
    let contentMatch = content.map {
        ExplorerContentMatch(
            lineContent: $0,
            lineNumber: 1,
            column: 4,
            matchByteRanges: [4..<10],
            contextBefore: [],
            contextAfter: [],
            isDefinition: false
        )
    }
    return ExplorerSearchResult(
        id: "test:\(url.path())",
        item: FileItem(
            url: url,
            isDirectory: false,
            isImage: false,
            fileSize: 10,
            modificationDate: nil
        ),
        relativePath: name,
        contentMatch: contentMatch
    )
}
