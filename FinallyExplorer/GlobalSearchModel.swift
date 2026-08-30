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
    private(set) var message: ExplorerSearchMessage?

    @ObservationIgnored private let service: any GlobalSearchServicing
    @ObservationIgnored private let debounce: @Sendable () async throws -> Void
    @ObservationIgnored private var requestGeneration = 0
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

    func request(in rootURL: URL) -> GlobalSearchRequest {
        GlobalSearchRequest(
            rootURL: rootURL,
            query: query,
            scope: scope,
            contentMode: contentMode
        )
    }

    func search(in rootURL: URL) async {
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
        results = []
        selectedResultID = nil
        message = nil

        do {
            if applyingDebounce {
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

            if page.isIndexWarming {
                beginWarmupRefresh(for: rootURL)
            }
        } catch is CancellationError {
            guard generation == requestGeneration else { return }
            isSearching = false
        } catch {
            guard generation == requestGeneration, Task.isCancelled == false else {
                return
            }
            results = []
            selectedResultID = nil
            message = .error(error.localizedDescription)
            isSearching = false
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
        cancelWarmup()
        query = ""
        resetVisibleState()
    }

    func shutdown() async {
        requestGeneration += 1
        cancelWarmup()
        resetVisibleState()
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
                      self.warmupGeneration == generation,
                      self.hasQuery else {
                    return
                }

                self.warmupTask = nil
                await self.search(in: rootURL, applyingDebounce: false)
            } catch is CancellationError {
                // Query changes and shutdown own cancellation.
            } catch {
                guard let self, self.warmupGeneration == generation else {
                    return
                }
                self.warmupTask = nil
                if self.hasQuery {
                    self.message = .notice(
                        "The search index is still warming: \(error.localizedDescription)"
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
        message = nil
    }
}
