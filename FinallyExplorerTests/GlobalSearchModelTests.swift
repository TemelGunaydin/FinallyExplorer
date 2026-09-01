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

    @Test("Index preparation gates search and runs the latest queued query when ready")
    func preparationGatesSearchUntilReady() async {
        let result = globalResult(named: "needle.txt")
        let service = GatedPreparationGlobalSearchService(result: result)
        let model = GlobalSearchModel(service: service, debounce: {})

        #expect(model.isIndexing(in: rootURL))
        #expect(model.isIndexReady(in: rootURL) == false)

        let preparationTask = Task {
            await model.prepare(in: rootURL)
        }
        await service.waitUntilPreparationIsRequested()

        model.query = "needle"
        await model.search(in: rootURL)
        #expect(await service.searchCount() == 0)
        #expect(model.isIndexing(in: rootURL))

        await service.finishPreparation()
        await preparationTask.value

        #expect(model.isIndexReady(in: rootURL))
        #expect(model.isIndexing(in: rootURL) == false)
        #expect(model.results == [result])
        #expect(await service.preparationCount() == 1)
        #expect(await service.searchCount() == 1)
        await model.shutdown()
    }

    @Test("Failed index preparation stays unavailable and can be retried")
    func failedPreparationCanRetry() async {
        let service = GatedPreparationGlobalSearchService(
            result: globalResult(named: "unused.txt")
        )
        let model = GlobalSearchModel(service: service, debounce: {})

        let failedPreparation = Task {
            await model.prepare(in: rootURL)
        }
        await service.waitUntilPreparationIsRequested()
        await service.failPreparation()
        await failedPreparation.value

        #expect(model.isIndexReady(in: rootURL) == false)
        #expect(model.isIndexing(in: rootURL) == false)
        #expect(
            model.indexFailureMessage(in: rootURL)
                == "Search failed for testing."
        )

        let retry = Task {
            await model.prepare(in: rootURL)
        }
        await service.waitUntilPreparationIsRequested()
        #expect(model.isIndexing(in: rootURL))
        await service.finishPreparation()
        await retry.value

        #expect(model.isIndexReady(in: rootURL))
        #expect(model.indexFailureMessage(in: rootURL) == nil)
        #expect(await service.preparationCount() == 2)
        await model.shutdown()
    }

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
        await model.prepare(in: rootURL)
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
        await model.prepare(in: rootURL)

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
        await model.prepare(in: rootURL)
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

    @Test("Filename search is immediate while content search remains debounced")
    func debounceDependsOnScope() async {
        let result = globalResult(named: "needle.txt")
        let service = GlobalSearchServiceStub(
            pages: [
                "needle": GlobalSearchPage(results: [result], message: nil)
            ]
        )
        let debounceCounter = GlobalSearchDebounceCounter()
        let model = GlobalSearchModel(service: service) {
            await debounceCounter.recordCall()
        }
        await model.prepare(in: rootURL)
        model.query = "needle"

        await model.search(in: rootURL)
        #expect(await debounceCounter.callCount() == 0)

        model.scope = .contents
        await model.search(in: rootURL)
        #expect(await debounceCounter.callCount() == 1)
    }

    @Test("A late result from an older query cannot corrupt the newest search")
    func staleCompletionIsDiscarded() async {
        let service = ControlledGlobalSearchService()
        let model = GlobalSearchModel(service: service, debounce: {})
        await model.prepare(in: rootURL)

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
        await model.prepare(in: rootURL)
        model.query = "eventual"

        await model.search(in: rootURL)
        #expect(model.results.isEmpty)
        #expect(model.message == nil)
        #expect(model.isPreparingResults)

        await service.waitUntilWarmupIsObserved()
        await service.finishInitialScan()

        for _ in 0..<1_000 {
            if model.results == [result] { break }
            await Task.yield()
        }

        #expect(model.results == [result])
        #expect(model.selectedResultID == result.id)
        #expect(model.isPreparingResults == false)
        #expect(await service.searchCount() == 2)
        await model.shutdown()
    }

    @Test("Clearing a query does not strand an index warm-up")
    func clearKeepsWarmupAliveUntilIndexIsReady() async {
        let service = WarmingGlobalSearchService(
            result: globalResult(named: "unused.txt")
        )
        let model = GlobalSearchModel(service: service, debounce: {})
        await model.prepare(in: rootURL)
        model.query = "eventual"

        await model.search(in: rootURL)
        await service.waitUntilWarmupIsObserved()
        #expect(model.isIndexing(in: rootURL))

        model.clear()
        #expect(model.query.isEmpty)
        #expect(model.isIndexing(in: rootURL))

        await service.finishInitialScan()
        for _ in 0..<1_000 {
            if model.isIndexReady(in: rootURL) { break }
            await Task.yield()
        }

        #expect(model.isIndexReady(in: rootURL))
        #expect(model.results.isEmpty)
        #expect(await service.searchCount() == 1)
        await model.shutdown()
    }

    @Test("Service failures become visible and shutdown releases the service")
    func errorAndShutdownLifecycle() async {
        let service = GlobalSearchServiceStub(
            pages: [:],
            error: GlobalSearchTestError.failed
        )
        let model = GlobalSearchModel(service: service, debounce: {})
        await model.prepare(in: rootURL)
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

private actor GlobalSearchDebounceCounter {
    private var count = 0

    func recordCall() {
        count += 1
    }

    func callCount() -> Int {
        count
    }
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

    func prepare(rootURL: URL) async throws {}

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

    func prepare(rootURL: URL) async throws {}

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

    func prepare(rootURL: URL) async throws {}

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
                message: nil,
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

private actor GatedPreparationGlobalSearchService: GlobalSearchServicing {
    private let result: ExplorerSearchResult
    private var preparationRequests = 0
    private var searches = 0
    private var preparationContinuation: CheckedContinuation<Void, any Error>?

    init(result: ExplorerSearchResult) {
        self.result = result
    }

    func prepare(rootURL: URL) async throws {
        preparationRequests += 1
        try await withCheckedThrowingContinuation { continuation in
            preparationContinuation = continuation
        }
    }

    func search(
        rootURL: URL,
        query: String,
        scope: ExplorerSearchScope,
        contentMode: FFFContentSearchMode
    ) async throws -> GlobalSearchPage {
        searches += 1
        return GlobalSearchPage(results: [result], message: nil)
    }

    func shutdown() async {
        preparationContinuation?.resume(throwing: CancellationError())
        preparationContinuation = nil
    }

    func waitUntilPreparationIsRequested() async {
        while preparationContinuation == nil {
            await Task.yield()
        }
    }

    func finishPreparation() {
        preparationContinuation?.resume()
        preparationContinuation = nil
    }

    func failPreparation() {
        preparationContinuation?.resume(throwing: GlobalSearchTestError.failed)
        preparationContinuation = nil
    }

    func preparationCount() -> Int {
        preparationRequests
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
