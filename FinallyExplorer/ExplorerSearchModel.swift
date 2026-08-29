//
//  ExplorerSearchModel.swift
//  FinallyExplorer
//

import Foundation
import Observation
import UniformTypeIdentifiers

nonisolated enum ExplorerSearchScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case names
    case contents

    var id: Self { self }

    var title: String {
        switch self {
        case .names:
            "Names"
        case .contents:
            "Contents"
        }
    }
}

nonisolated struct ExplorerContentMatch: Hashable, Sendable {
    let lineContent: String
    let lineNumber: UInt64
    let column: UInt32
    let matchByteRanges: [Range<Int>]
    let contextBefore: [String]
    let contextAfter: [String]
    let isDefinition: Bool
}

nonisolated struct ExplorerSearchResult: Identifiable, Hashable, Sendable {
    let id: String
    let item: FileItem
    let relativePath: String
    let contentMatch: ExplorerContentMatch?

    var isContentMatch: Bool { contentMatch != nil }
}

nonisolated struct ExplorerSearchRequest: Hashable, Sendable {
    let rootURL: URL?
    let query: String
    let scope: ExplorerSearchScope
    let contentMode: FFFContentSearchMode
}

/// Keeps recoverable search state visible without treating an incomplete page
/// as a failed search. FFF can return useful partial results while it warms an
/// index or reaches a caller-imposed page/time limit.
nonisolated enum ExplorerSearchMessage: Equatable, Sendable {
    case error(String)
    case notice(String)

    var text: String {
        switch self {
        case let .error(message), let .notice(message):
            message
        }
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

@MainActor
@Observable
final class ExplorerSearchModel {
    var query = ""
    var scope: ExplorerSearchScope = .names
    var contentMode: FFFContentSearchMode = .plain

    private(set) var results: [ExplorerSearchResult] = []
    private(set) var isSearching = false
    private(set) var errorMessage: ExplorerSearchMessage?
    private(set) var isIndexWarming = false

    @ObservationIgnored private var engine: FFFSearchEngine?
    @ObservationIgnored private var engineRootURL: URL?
    @ObservationIgnored private var requestGeneration = 0
    @ObservationIgnored private var warmupGeneration = 0
    @ObservationIgnored private var warmupTask: Task<Void, Never>?
    @ObservationIgnored private let debounce: @Sendable () async throws -> Void
    @ObservationIgnored private let directorySearchService: DirectorySearchService
    @ObservationIgnored private let enginePool: FFFSearchEnginePool

    init(
        debounce: @escaping @Sendable () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(150))
        },
        directorySearchService: DirectorySearchService = DirectorySearchService(),
        enginePool: FFFSearchEnginePool = .shared
    ) {
        self.debounce = debounce
        self.directorySearchService = directorySearchService
        self.enginePool = enginePool
    }

    deinit {
        warmupTask?.cancel()

        // Pane removal does not have an async lifecycle callback. Return the
        // lease here as a safety net so a closed split cannot retain a native
        // FFF index for the rest of the app session.
        guard let engine, let engineRootURL else { return }
        let enginePool = enginePool
        Task {
            await enginePool.release(engine, rootURL: engineRootURL)
        }
    }

    var isSearchActive: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func request(in rootURL: URL?) -> ExplorerSearchRequest {
        ExplorerSearchRequest(
            rootURL: rootURL,
            query: query,
            scope: scope,
            contentMode: contentMode
        )
    }

    func search(in rootURL: URL?) async {
        await search(in: rootURL, applyingDebounce: true)
    }

    private func search(in rootURL: URL?, applyingDebounce: Bool) async {
        requestGeneration += 1
        let generation = requestGeneration
        let searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedScope = scope
        let requestedContentMode = contentMode

        guard searchQuery.isEmpty == false else {
            results = []
            errorMessage = nil
            isSearching = false
            return
        }

        guard let rootURL else {
            results = []
            errorMessage = .error(DirectoryAccessError.invalidURL.localizedDescription)
            isSearching = false
            return
        }

        isSearching = true
        results = []
        errorMessage = isIndexWarming
            ? .notice("Indexing this folder. Results will refresh automatically.")
            : nil

        do {
            if applyingDebounce {
                try await debounce()
            }
            try Task.checkCancellation()

            guard generation == requestGeneration,
                  query.trimmingCharacters(in: .whitespacesAndNewlines) == searchQuery,
                  scope == requestedScope,
                  contentMode == requestedContentMode else {
                return
            }

            let engine = try await preparedEngine(for: rootURL)
            try Task.checkCancellation()

            let newResults: [ExplorerSearchResult]
            switch requestedScope {
            case .names:
                // The catalog task is owned by DirectorySearchService, rather
                // than by this keystroke. It is therefore built once and
                // reused by later queries for the same folder.
                async let directoryPage = directorySearchService.searchPage(
                    in: rootURL,
                    matching: searchQuery,
                    limit: 100
                )

                let filePage = try await engine.searchFilesPage(
                    query: searchQuery,
                    limit: 100
                )
                try Task.checkCancellation()

                guard isCurrentRequest(
                    generation: generation,
                    query: searchQuery,
                    scope: requestedScope,
                    contentMode: requestedContentMode
                ) else {
                    return
                }

                // Surface indexed file hits as soon as FFF has them. The
                // folder supplement may still be building its cache on the
                // first query in a large tree.
                results = Self.makeNameResults(
                    files: filePage.hits,
                    directories: []
                )
                errorMessage = nameSearchMessage(filePage: filePage)

                do {
                    let page = try await directoryPage
                    try Task.checkCancellation()

                    guard isCurrentRequest(
                        generation: generation,
                        query: searchQuery,
                        scope: requestedScope,
                        contentMode: requestedContentMode
                    ) else {
                        return
                    }

                    newResults = Self.makeNameResults(
                        files: filePage.hits,
                        directories: page.results
                    )
                    results = newResults
                    errorMessage = nameSearchMessage(
                        filePage: filePage,
                        directoryPage: page
                    )
                    isSearching = false
                    return
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    guard isCurrentRequest(
                        generation: generation,
                        query: searchQuery,
                        scope: requestedScope,
                        contentMode: requestedContentMode
                    ) else {
                        return
                    }

                    // Directory discovery is a supplement to FFF's file
                    // index. Keep useful file hits visible if that isolated
                    // filesystem walk cannot complete.
                    errorMessage = nameSearchMessage(
                        filePage: filePage,
                        directoryFailure: error.localizedDescription
                    )
                    isSearching = false
                    return
                }

            case .contents:
                let page = try await engine.searchContentPage(
                    query: searchQuery,
                    mode: requestedContentMode,
                    limit: 100,
                    timeBudgetMilliseconds: 250
                )
                try Task.checkCancellation()
                newResults = Self.makeContentResults(page.hits)
                errorMessage = contentSearchMessage(page)
            }

            guard generation == requestGeneration,
                  query.trimmingCharacters(in: .whitespacesAndNewlines) == searchQuery,
                  scope == requestedScope,
                  contentMode == requestedContentMode else {
                return
            }

            results = newResults
            isSearching = false
        } catch is CancellationError {
            guard generation == requestGeneration else { return }
            isSearching = false
        } catch {
            guard generation == requestGeneration, Task.isCancelled == false else { return }
            results = []
            errorMessage = .error(error.localizedDescription)
            isSearching = false
        }
    }

    func shutdown() async {
        requestGeneration += 1
        cancelWarmup()
        results = []
        errorMessage = nil
        isSearching = false

        let oldEngine = engine
        let oldRootURL = engineRootURL
        engine = nil
        engineRootURL = nil
        await directorySearchService.shutdown()
        if let oldEngine, let oldRootURL {
            await enginePool.release(oldEngine, rootURL: oldRootURL)
        }
    }

    /// Keeps the explicitly-scanned FFF index in sync after FinallyExplorer
    /// copies or moves an item. Watch mode is intentionally disabled, so app
    /// initiated file changes need one explicit rescan.
    func filesDidChange(in rootURL: URL?) async {
        requestGeneration += 1
        results = []
        errorMessage = nil
        isSearching = false

        await directorySearchService.invalidate(root: rootURL)

        guard let rootURL else {
            if isSearchActive {
                errorMessage = .error(DirectoryAccessError.invalidURL.localizedDescription)
            }
            return
        }

        guard FFFSearchValueMapper.isLocalFileURL(rootURL) else {
            if isSearchActive {
                errorMessage = .error(
                    FFFSearchError.invalidRootURL(rootURL).localizedDescription
                )
            }
            return
        }

        do {
            let resolvedRootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
            if let engine, engineRootURL == resolvedRootURL {
                cancelWarmup()
                try await engine.rescan()
            }

            try Task.checkCancellation()

            if isSearchActive {
                await search(in: rootURL)
            }
        } catch is CancellationError {
            return
        } catch {
            guard Task.isCancelled == false else { return }

            if isSearchActive {
                results = []
                errorMessage = .error(error.localizedDescription)
                isSearching = false
            }
        }
    }

    private func preparedEngine(for rootURL: URL) async throws -> FFFSearchEngine {
        guard FFFSearchValueMapper.isLocalFileURL(rootURL) else {
            throw FFFSearchError.invalidRootURL(rootURL)
        }

        let resolvedRootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()

        if let engine, engineRootURL == resolvedRootURL {
            return engine
        }

        cancelWarmup()
        let oldEngine = engine
        let oldRootURL = engineRootURL
        engine = nil
        engineRootURL = nil
        if let oldEngine, let oldRootURL {
            await enginePool.release(oldEngine, rootURL: oldRootURL)
        }

        let newEngine = try await enginePool.acquire(rootURL: resolvedRootURL)
        do {
            try Task.checkCancellation()

            engine = newEngine
            engineRootURL = resolvedRootURL
            beginWarmup(for: newEngine, rootURL: resolvedRootURL)
            return newEngine
        } catch {
            await enginePool.release(newEngine, rootURL: resolvedRootURL)
            throw error
        }
    }

    /// Warm-up belongs to the engine/root lifetime, not the current SwiftUI
    /// search task. This keeps rapid query edits from repeatedly cancelling
    /// and recreating FFF's initial scan.
    private func beginWarmup(for engine: FFFSearchEngine, rootURL: URL) {
        warmupGeneration += 1
        let generation = warmupGeneration
        warmupTask?.cancel()
        isIndexWarming = true

        warmupTask = Task { @MainActor [weak self, engine] in
            do {
                try await engine.waitForInitialScan()
                guard let self,
                      self.isCurrentWarmup(
                          engine,
                          rootURL: rootURL,
                          generation: generation
                      ) else {
                    return
                }

                self.warmupTask = nil
                self.isIndexWarming = false

                // A partial-index response is useful immediately. Refresh the
                // active query once it can be complete without making the
                // user type again.
                if self.isSearchActive {
                    await self.search(in: rootURL, applyingDebounce: false)
                }
            } catch is CancellationError {
                // Root changes and explicit shutdown own cancellation; both
                // already reset the visible warm-up state.
            } catch {
                guard let self,
                      self.isCurrentWarmup(
                          engine,
                          rootURL: rootURL,
                          generation: generation
                      ) else {
                    return
                }

                self.warmupTask = nil
                self.isIndexWarming = false
                if self.isSearchActive {
                    self.errorMessage = .notice(
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
        isIndexWarming = false
    }

    private func isCurrentWarmup(
        _ candidate: FFFSearchEngine,
        rootURL: URL,
        generation: Int
    ) -> Bool {
        engine === candidate
            && engineRootURL == rootURL
            && warmupGeneration == generation
    }

    private func isCurrentRequest(
        generation: Int,
        query: String,
        scope: ExplorerSearchScope,
        contentMode: FFFContentSearchMode
    ) -> Bool {
        generation == requestGeneration
            && self.query.trimmingCharacters(in: .whitespacesAndNewlines) == query
            && self.scope == scope
            && self.contentMode == contentMode
    }

    private func nameSearchMessage(
        filePage: FFFFileSearchPage,
        directoryPage: DirectorySearchPage? = nil,
        directoryFailure: String? = nil
    ) -> ExplorerSearchMessage? {
        var messages: [String] = []

        if isIndexWarming {
            messages.append("Indexing this folder. Results will refresh automatically.")
        }

        if filePage.isTruncated {
            messages.append(
                "Showing the first \(filePage.hits.count) of \(filePage.totalMatched) matching files. Refine the search to see more."
            )
        }

        if let directoryPage, directoryPage.isTruncated {
            messages.append(
                "Showing the first \(directoryPage.results.count) of \(directoryPage.totalMatched) matching folders. Refine the search to see more."
            )
        }

        if let directoryFailure {
            messages.append("Folder matches are unavailable: \(directoryFailure)")
        }

        guard messages.isEmpty == false else { return nil }
        return .notice(messages.joined(separator: " "))
    }

    private func contentSearchMessage(
        _ page: FFFContentSearchPage
    ) -> ExplorerSearchMessage? {
        var messages: [String] = []

        if isIndexWarming {
            messages.append("Indexing this folder. Results will refresh automatically.")
        }

        if page.isTruncated {
            messages.append(
                "Searched \(page.totalFilesSearched) of \(page.filteredFileCount) eligible files. Refine the search to include the remaining files."
            )
        }

        if page.totalFiles > page.filteredFileCount {
            messages.append(
                "\(page.totalFiles - page.filteredFileCount) indexed files were excluded by content-search filters."
            )
        }

        if let regexFallbackError = page.regexFallbackError {
            messages.append(
                "The regex was invalid (\(regexFallbackError)); FFF searched for it literally."
            )
        }

        guard messages.isEmpty == false else { return nil }
        return .notice(messages.joined(separator: " "))
    }

    private nonisolated static func makeNameResults(
        files: [FFFFileSearchHit],
        directories: [DirectorySearchResult]
    ) -> [ExplorerSearchResult] {
        let directoryResults = directories.map { directory in
            return ExplorerSearchResult(
                id: "directory:\(directory.url.path(percentEncoded: false))",
                item: FileItem(
                    url: directory.url,
                    isDirectory: true,
                    isImage: false,
                    fileSize: nil,
                    modificationDate: nil
                ),
                relativePath: directory.relativePath,
                contentMatch: nil
            )
        }

        let fileResults = files.lazy
            .filter { Self.isVisible(relativePath: $0.relativePath) }
            .map { hit in
                ExplorerSearchResult(
                    id: "file:\(hit.url.path(percentEncoded: false))",
                    item: Self.fileItem(
                        url: hit.url,
                        byteSize: hit.byteSize,
                        modificationDate: hit.modificationDate
                    ),
                    relativePath: hit.relativePath,
                    contentMatch: nil
                )
            }

        return directoryResults + Array(fileResults)
    }

    private nonisolated static func makeContentResults(
        _ matches: [FFFContentSearchHit]
    ) -> [ExplorerSearchResult] {
        matches.compactMap { hit in
            guard Self.isVisible(relativePath: hit.relativePath) else { return nil }

            return ExplorerSearchResult(
                id: "content:\(hit.id)",
                item: Self.fileItem(
                    url: hit.url,
                    byteSize: hit.byteSize,
                    modificationDate: hit.modificationDate
                ),
                relativePath: hit.relativePath,
                contentMatch: ExplorerContentMatch(
                    lineContent: hit.lineContent,
                    lineNumber: hit.lineNumber,
                    column: hit.column,
                    matchByteRanges: hit.matchByteRanges,
                    contextBefore: hit.contextBefore,
                    contextAfter: hit.contextAfter,
                    isDefinition: hit.isDefinition
                )
            )
        }
    }

    private nonisolated static func isVisible(relativePath: String) -> Bool {
        relativePath.split(separator: "/").allSatisfy { component in
            component.hasPrefix(".") == false
        }
    }

    private nonisolated static func fileItem(
        url: URL,
        byteSize: UInt64,
        modificationDate: Date?
    ) -> FileItem {
        let contentType = UTType(filenameExtension: url.pathExtension)

        return FileItem(
            url: url,
            isDirectory: false,
            isImage: contentType?.conforms(to: .image) == true,
            fileSize: Int64(clamping: byteSize),
            modificationDate: modificationDate
        )
    }
}
