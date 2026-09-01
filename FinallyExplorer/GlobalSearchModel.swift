//
//  GlobalSearchModel.swift
//  FinallyExplorer
//

import Foundation
import Observation

nonisolated struct GlobalSearchRequest: Hashable, Sendable {
    let rootURL: URL
    let query: String
    let scope: ExplorerSearchScope
    let contentMode: FFFContentSearchMode
}

nonisolated enum GlobalSearchIndexState: Equatable, Sendable {
    case idle
    case indexing(rootURL: URL)
    case ready(rootURL: URL)
    case failed(rootURL: URL, message: String)
}

nonisolated enum GlobalSearchSelectionMovement: Sendable {
    case previous
    case next
}

@MainActor
@Observable
final class GlobalSearchModel {
    var query = ""
    var scope: ExplorerSearchScope = .names
    var contentMode: FFFContentSearchMode = .plain

    private(set) var results: [ExplorerSearchResult] = []
    private(set) var selectedResultID: ExplorerSearchResult.ID?
    private(set) var isSearching = false
    private(set) var isPreparingResults = false
    private(set) var indexState: GlobalSearchIndexState = .idle
    private(set) var message: ExplorerSearchMessage?

    @ObservationIgnored private let service: any GlobalSearchServicing
    @ObservationIgnored private let debounce: @Sendable () async throws -> Void
    @ObservationIgnored private var lifecycleGeneration = 0
    @ObservationIgnored private var requestGeneration = 0
    @ObservationIgnored private var preparationGeneration = 0
    @ObservationIgnored private var warmupGeneration = 0
    @ObservationIgnored private var warmupTask: Task<Void, Never>?

    init(
        service: (any GlobalSearchServicing)? = nil,
        debounce: @escaping @Sendable () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(150))
        }
    ) {
        self.service = service ?? FFFGlobalSearchService()
        self.debounce = debounce
    }

    deinit {
        warmupTask?.cancel()
    }

    var selectedResult: ExplorerSearchResult? {
        guard let selectedResultID else { return nil }
        return results.first { $0.id == selectedResultID }
    }

    var hasQuery: Bool {
        normalizedQuery.isEmpty == false
    }

    func isIndexReady(in rootURL: URL) -> Bool {
        guard case let .ready(readyRootURL) = indexState else { return false }
        return readyRootURL == Self.canonicalRootURL(rootURL)
    }

    func isIndexing(in rootURL: URL) -> Bool {
        let canonicalRootURL = Self.canonicalRootURL(rootURL)
        switch indexState {
        case .idle:
            return true
        case .indexing:
            return true
        case let .ready(readyRootURL):
            return readyRootURL != canonicalRootURL
        case let .failed(failedRootURL, _):
            return failedRootURL != canonicalRootURL
        }
    }

    func indexFailureMessage(in rootURL: URL) -> String? {
        guard case let .failed(failedRootURL, message) = indexState,
              failedRootURL == Self.canonicalRootURL(rootURL) else {
            return nil
        }
        return message
    }

    func request(in rootURL: URL) -> GlobalSearchRequest {
        GlobalSearchRequest(
            rootURL: rootURL,
            query: query,
            scope: scope,
            contentMode: contentMode
        )
    }

    func runIndexLifecycle(in rootURL: URL) async {
        lifecycleGeneration += 1
        let generation = lifecycleGeneration

        await prepare(in: rootURL)

        do {
            while Task.isCancelled == false {
                try await Task.sleep(for: .seconds(60))
            }
        } catch is CancellationError {
            // View disappearance and root changes own cancellation.
        } catch {
            // Task.sleep(for:) only throws for cancellation.
        }

        await shutdown(ifLifecycleGeneration: generation)
    }

    func prepare(in rootURL: URL) async {
        let canonicalRootURL = Self.canonicalRootURL(rootURL)
        if case let .ready(readyRootURL) = indexState,
           readyRootURL == canonicalRootURL {
            return
        }

        preparationGeneration += 1
        let generation = preparationGeneration
        requestGeneration += 1
        cancelWarmup()
        resetVisibleState()
        indexState = .indexing(rootURL: canonicalRootURL)

        do {
            try await service.prepare(rootURL: canonicalRootURL)
            try Task.checkCancellation()
            guard generation == preparationGeneration else { return }

            indexState = .ready(rootURL: canonicalRootURL)
            if hasQuery {
                await search(in: canonicalRootURL, applyingDebounce: false)
            }
        } catch is CancellationError {
            guard generation == preparationGeneration else { return }
            indexState = .idle
        } catch {
            guard generation == preparationGeneration, Task.isCancelled == false else {
                return
            }
            indexState = .failed(
                rootURL: canonicalRootURL,
                message: error.localizedDescription
            )
            isPreparingResults = false
        }
    }

    func search(in rootURL: URL) async {
        guard isIndexReady(in: rootURL) else { return }
        await search(in: rootURL, applyingDebounce: true)
    }

    private func search(in rootURL: URL, applyingDebounce: Bool) async {
        requestGeneration += 1
        let generation = requestGeneration
        let requestedQuery = normalizedQuery
        let requestedScope = scope
        let requestedContentMode = contentMode
        cancelWarmup()

        guard requestedQuery.isEmpty == false else {
            resetVisibleState()
            return
        }

        isSearching = true
        isPreparingResults = false
        results = []
        selectedResultID = nil
        message = nil

        do {
            if applyingDebounce, requestedScope == .contents {
                try await debounce()
            }
            try Task.checkCancellation()
            guard isCurrent(
                generation: generation,
                query: requestedQuery,
                scope: requestedScope,
                contentMode: requestedContentMode
            ) else {
                return
            }

            let page = try await service.search(
                rootURL: rootURL,
                query: requestedQuery,
                scope: requestedScope,
                contentMode: requestedContentMode
            )
            try Task.checkCancellation()
            guard isCurrent(
                generation: generation,
                query: requestedQuery,
                scope: requestedScope,
                contentMode: requestedContentMode
            ) else {
                return
            }

            results = page.results
            selectedResultID = page.results.first?.id
            message = page.message
            isSearching = false
            isPreparingResults = page.isIndexWarming
            indexState = page.isIndexWarming
                ? .indexing(rootURL: Self.canonicalRootURL(rootURL))
                : .ready(rootURL: Self.canonicalRootURL(rootURL))

            if page.isIndexWarming {
                beginWarmupRefresh(for: rootURL)
            }
        } catch is CancellationError {
            guard generation == requestGeneration else { return }
            isSearching = false
            isPreparingResults = false
        } catch {
            guard generation == requestGeneration, Task.isCancelled == false else {
                return
            }
            results = []
            selectedResultID = nil
            message = .error(error.localizedDescription)
            isSearching = false
            isPreparingResults = false
        }
    }

    func select(_ result: ExplorerSearchResult) {
        guard results.contains(where: { $0.id == result.id }) else { return }
        selectedResultID = result.id
    }

    func moveSelection(_ movement: GlobalSearchSelectionMovement) {
        guard results.isEmpty == false else {
            selectedResultID = nil
            return
        }

        guard let selectedResultID,
              let index = results.firstIndex(where: { $0.id == selectedResultID }) else {
            self.selectedResultID = movement == .next
                ? results.first?.id
                : results.last?.id
            return
        }

        switch movement {
        case .previous:
            let previousIndex = index == results.startIndex
                ? results.index(before: results.endIndex)
                : results.index(before: index)
            self.selectedResultID = results[previousIndex].id
        case .next:
            let nextIndex = results.index(after: index)
            self.selectedResultID = nextIndex == results.endIndex
                ? results.first?.id
                : results[nextIndex].id
        }
    }

    func clear() {
        requestGeneration += 1
        query = ""
        resetVisibleState()
    }

    func shutdown() async {
        lifecycleGeneration += 1
        await performShutdown()
    }

    private func shutdown(ifLifecycleGeneration generation: Int) async {
        guard lifecycleGeneration == generation else { return }
        lifecycleGeneration += 1
        await performShutdown()
    }

    private func performShutdown() async {
        preparationGeneration += 1
        requestGeneration += 1
        cancelWarmup()
        resetVisibleState()
        indexState = .idle
        await service.shutdown()
    }

    private func beginWarmupRefresh(for rootURL: URL) {
        warmupGeneration += 1
        let generation = warmupGeneration
        warmupTask?.cancel()

        warmupTask = Task { @MainActor [weak self, service] in
            do {
                try await service.waitForInitialScan(rootURL: rootURL)
                guard let self,
                      self.warmupGeneration == generation else {
                    return
                }

                self.warmupTask = nil
                self.indexState = .ready(rootURL: Self.canonicalRootURL(rootURL))
                self.isPreparingResults = false
                if self.hasQuery {
                    await self.search(in: rootURL, applyingDebounce: false)
                }
            } catch is CancellationError {
                // Query changes and shutdown own cancellation.
            } catch {
                guard let self, self.warmupGeneration == generation else {
                    return
                }
                self.warmupTask = nil
                self.isPreparingResults = false
                self.indexState = .failed(
                    rootURL: Self.canonicalRootURL(rootURL),
                    message: error.localizedDescription
                )
                if self.hasQuery {
                    self.message = .notice(
                        "Search preparation is taking longer than expected."
                    )
                }
            }
        }
    }

    private func cancelWarmup() {
        warmupGeneration += 1
        warmupTask?.cancel()
        warmupTask = nil
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func canonicalRootURL(_ rootURL: URL) -> URL {
        rootURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func isCurrent(
        generation: Int,
        query: String,
        scope: ExplorerSearchScope,
        contentMode: FFFContentSearchMode
    ) -> Bool {
        generation == requestGeneration
            && normalizedQuery == query
            && self.scope == scope
            && self.contentMode == contentMode
    }

    private func resetVisibleState() {
        results = []
        selectedResultID = nil
        isSearching = false
        isPreparingResults = false
        message = nil
    }
}
