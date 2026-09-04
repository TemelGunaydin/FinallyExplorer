//
//  GlobalSearchService.swift
//  FinallyExplorer
//

import Foundation
import UniformTypeIdentifiers

nonisolated struct GlobalSearchPage: Sendable {
    let results: [ExplorerSearchResult]
    let message: ExplorerSearchMessage?
    let isIndexWarming: Bool

    init(
        results: [ExplorerSearchResult],
        message: ExplorerSearchMessage?,
        isIndexWarming: Bool = false
    ) {
        self.results = results
        self.message = message
        self.isIndexWarming = isIndexWarming
    }
}

nonisolated protocol GlobalSearchServicing: Sendable {
    func prepare(rootURL: URL) async throws

    func search(
        rootURL: URL,
        query: String,
        scope: ExplorerSearchScope,
        contentMode: FFFContentSearchMode
    ) async throws -> GlobalSearchPage

    func waitForInitialScan(rootURL: URL) async throws
    func rebuildContentIndex(rootURL: URL) async throws
    func shutdown() async
}

extension GlobalSearchServicing {
    func waitForInitialScan(rootURL: URL) async throws {
        try await prepare(rootURL: rootURL)
    }

    func rebuildContentIndex(rootURL: URL) async throws {
        try await prepare(rootURL: rootURL)
    }
}

/// A test seam for the name-only FFF fallback.
///
/// Production leaves this unset and uses the service-owned FFF engine. Tests can
/// provide a deterministic fallback without creating a native engine or scanning
/// the startup disk.
nonisolated struct HybridGlobalNameSearchFallback: Sendable {
    let search: @Sendable (URL, String) async throws -> GlobalSearchPage

    init(
        search: @escaping @Sendable (URL, String) async throws
            -> GlobalSearchPage
    ) {
        self.search = search
    }
}

/// Uses macOS's persistent Spotlight catalog for global name queries and starts
/// FFF lazily for content/grep work or when Spotlight cannot satisfy a fuzzy
/// name query. This avoids a startup-disk scan at every app launch without
/// weakening the existing search modes.
actor HybridGlobalSearchService: GlobalSearchServicing {
    private nonisolated enum PersistentNameSearchError: Error, Sendable {
        case timedOut
    }

    private static let maximumResultCount = 120
    private static let maximumSpotlightCandidateCount = 800
    private static let spotlightFailureThreshold = 2
    private let enginePool: FFFSearchEnginePool
    private let spotlightService: any SpotlightGlobalSearchServicing
    private let spotlightTimeout: Duration
    private let injectedNameFallback: HybridGlobalNameSearchFallback?
    private var engine: FFFSearchEngine?
    private var engineRootURL: URL?
    private var lifecycleGeneration = 0
    private var usesFFFNameFallback = false
    private var consecutiveSpotlightFailures = 0

    init(
        enginePool: FFFSearchEnginePool = .shared,
        spotlightService: any SpotlightGlobalSearchServicing =
            SpotlightGlobalSearchService(),
        spotlightTimeout: Duration = .seconds(2),
        nameFallback: HybridGlobalNameSearchFallback? = nil
    ) {
        self.enginePool = enginePool
        self.spotlightService = spotlightService
        self.spotlightTimeout = spotlightTimeout
        injectedNameFallback = nameFallback
    }

    func prepare(rootURL: URL) async throws {
        let resolvedRootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        guard FFFSearchValueMapper.isLocalFileURL(resolvedRootURL) else {
            throw FFFSearchError.invalidRootURL(rootURL)
        }
        try Task.checkCancellation()
    }

    func search(
        rootURL: URL,
        query: String,
        scope: ExplorerSearchScope,
        contentMode: FFFContentSearchMode
    ) async throws -> GlobalSearchPage {
        let resolvedRootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        try await prepare(rootURL: resolvedRootURL)

        switch scope {
        case .names:
            if Self.usesPersistentSpotlightIndex(for: resolvedRootURL) {
                if usesFFFNameFallback {
                    return try await fffNamePage(
                        rootURL: resolvedRootURL,
                        query: query
                    )
                }

                let generation = lifecycleGeneration
                let persistentPage: SpotlightGlobalSearchService.Page
                do {
                    persistentPage = try await spotlightPage(
                        rootURL: resolvedRootURL,
                        query: query
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // `shutdown()` advances this generation. An older Spotlight
                    // request must not create a fresh FFF engine after teardown.
                    try validateLifecycle(generation: generation)
                    let fallbackPage = try await fffNamePage(
                        rootURL: resolvedRootURL,
                        query: query,
                        fallbackNotice: "macOS Search was unavailable, so fallback search is scanning for matches."
                    )
                    consecutiveSpotlightFailures += 1
                    usesFFFNameFallback = consecutiveSpotlightFailures
                        >= Self.spotlightFailureThreshold
                    return fallbackPage
                }

                try validateLifecycle(generation: generation)
                consecutiveSpotlightFailures = 0
                let spotlightResults = Self.nameResults(
                    query: query,
                    rootURL: resolvedRootURL,
                    spotlightHits: persistentPage.hits
                )

                // A successful empty Spotlight query can still be a fuzzy-name
                // match in FFF. Start that fallback lazily for this active
                // search, never during app launch; the pooled engine is reused
                // by later queries instead of creating another root scan.
                if spotlightResults.isEmpty {
                    try validateLifecycle(generation: generation)
                    return try await fffNamePage(
                        rootURL: resolvedRootURL,
                        query: query
                    )
                }

                return GlobalSearchPage(
                    results: spotlightResults,
                    message: persistentPage.isTruncated
                        || persistentPage.hits.count > Self.maximumResultCount
                        ? .notice(
                            "Showing the closest matches. Refine the search to narrow the result set."
                        )
                        : nil
                )
            }

            return try await fffNamePage(
                rootURL: resolvedRootURL,
                query: query
            )

        case .contents:
            let engine = try await preparedEngine(for: resolvedRootURL)
            let generation = lifecycleGeneration
            try validateCurrentEngine(
                engine,
                rootURL: resolvedRootURL,
                generation: generation
            )
            let scanProgress = try await engine.scanProgress()
            try validateCurrentEngine(
                engine,
                rootURL: resolvedRootURL,
                generation: generation
            )
            let page = try await engine.searchContentPage(
                query: query,
                mode: contentMode,
                limit: Self.maximumResultCount,
                timeBudgetMilliseconds: 350
            )
            try validateCurrentEngine(
                engine,
                rootURL: resolvedRootURL,
                generation: generation
            )

            var notices: [String] = []
            if page.isTruncated {
                notices.append(
                    "Searched \(page.totalFilesSearched) of \(page.filteredFileCount) eligible files. Refine the search to scan fewer files."
                )
            }
            if let regexFallbackError = page.regexFallbackError {
                notices.append(
                    "The regex was invalid (\(regexFallbackError)); it was searched for literally."
                )
            }

            return GlobalSearchPage(
                results: Self.contentResults(page.hits),
                message: notices.isEmpty
                    ? nil
                    : .notice(notices.joined(separator: " ")),
                isIndexWarming: scanProgress.isScanning
                    || scanProgress.isWarmupComplete == false
            )
        }
    }

    private func spotlightPage(
        rootURL: URL,
        query: String
    ) async throws -> SpotlightGlobalSearchService.Page {
        let service = spotlightService
        let timeout = spotlightTimeout

        return try await withThrowingTaskGroup(
            of: SpotlightGlobalSearchService.Page.self
        ) { group in
            group.addTask {
                try await service.search(
                    rootURL: rootURL,
                    query: query,
                    maximumCandidateCount: Self.maximumSpotlightCandidateCount
                )
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw PersistentNameSearchError.timedOut
            }

            defer { group.cancelAll() }
            guard let firstResult = try await group.next() else {
                throw CancellationError()
            }
            return firstResult
        }
    }

    private func fffNamePage(
        rootURL: URL,
        query: String,
        fallbackNotice: String? = nil
    ) async throws -> GlobalSearchPage {
        if let injectedNameFallback {
            let generation = lifecycleGeneration
            let page = try await injectedNameFallback.search(rootURL, query)
            try validateLifecycle(generation: generation)
            return Self.prependingNotice(fallbackNotice, to: page)
        }

        let engine = try await preparedEngine(for: rootURL)
        let generation = lifecycleGeneration
        try validateCurrentEngine(
            engine,
            rootURL: rootURL,
            generation: generation
        )
        let scanProgress = try await engine.scanProgress()
        try validateCurrentEngine(
            engine,
            rootURL: rootURL,
            generation: generation
        )
        async let filePage = engine.searchFilesPage(
            query: query,
            limit: Self.maximumResultCount
        )
        async let directoryHits = engine.searchDirectories(
            query: query,
            limit: Self.maximumResultCount
        )

        let (files, directories) = try await (filePage, directoryHits)
        try validateCurrentEngine(
            engine,
            rootURL: rootURL,
            generation: generation
        )
        var notices = fallbackNotice.map { [$0] } ?? []
        if files.isTruncated {
            notices.append(
                "Showing the closest \(Self.maximumResultCount) file matches. Refine the search to see a narrower result set."
            )
        }
        return GlobalSearchPage(
            results: Self.nameResults(
                query: query,
                files: files.hits,
                directories: directories
            ),
            message: notices.isEmpty
                ? nil
                : .notice(notices.joined(separator: " ")),
            isIndexWarming: scanProgress.isScanning
                || scanProgress.isWarmupComplete == false
        )
    }

    func waitForInitialScan(rootURL: URL) async throws {
        let resolvedRootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        guard let engine, engineRootURL == resolvedRootURL else { return }
        let generation = lifecycleGeneration

        try await engine.waitForInitialScan()
        try validateCurrentEngine(
            engine,
            rootURL: resolvedRootURL,
            generation: generation
        )
    }

    func rebuildContentIndex(rootURL: URL) async throws {
        let resolvedRootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        try await prepare(rootURL: resolvedRootURL)
        let engine = try await preparedEngine(for: resolvedRootURL)
        let generation = lifecycleGeneration
        let progress = try await engine.scanProgress()

        if progress.isScanning || progress.isWarmupComplete == false {
            try await engine.waitForInitialScan()
        } else {
            try await engine.rescan()
        }

        try validateCurrentEngine(
            engine,
            rootURL: resolvedRootURL,
            generation: generation
        )
    }

    private func validateLifecycle(generation: Int) throws {
        try Task.checkCancellation()
        guard lifecycleGeneration == generation else {
            throw CancellationError()
        }
    }

    private func validateCurrentEngine(
        _ engine: FFFSearchEngine,
        rootURL: URL,
        generation: Int
    ) throws {
        try Task.checkCancellation()
        guard lifecycleGeneration == generation,
              self.engine === engine,
              engineRootURL == rootURL else {
            throw CancellationError()
        }
    }

    func shutdown() async {
        lifecycleGeneration += 1
        usesFFFNameFallback = false
        consecutiveSpotlightFailures = 0
        let oldEngine = engine
        let oldRootURL = engineRootURL
        engine = nil
        engineRootURL = nil

        if let oldEngine, let oldRootURL {
            await enginePool.release(oldEngine, rootURL: oldRootURL)
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

        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        let oldEngine = engine
        let oldRootURL = engineRootURL
        engine = nil
        engineRootURL = nil

        if let oldEngine, let oldRootURL {
            await enginePool.release(oldEngine, rootURL: oldRootURL)
        }

        guard lifecycleGeneration == generation else {
            throw CancellationError()
        }
        try Task.checkCancellation()

        let newEngine = try await enginePool.acquire(rootURL: resolvedRootURL)

        do {
            try Task.checkCancellation()
            guard lifecycleGeneration == generation else {
                throw CancellationError()
            }
            engine = newEngine
            engineRootURL = resolvedRootURL
            return newEngine
        } catch {
            await enginePool.release(newEngine, rootURL: resolvedRootURL)
            throw error
        }
    }

    private nonisolated static func usesPersistentSpotlightIndex(
        for rootURL: URL
    ) -> Bool {
        rootURL.path(percentEncoded: false) == "/"
    }

    private nonisolated static func prependingNotice(
        _ notice: String?,
        to page: GlobalSearchPage
    ) -> GlobalSearchPage {
        guard let notice else { return page }

        let message: ExplorerSearchMessage
        switch page.message {
        case let .notice(existingNotice):
            message = .notice("\(notice) \(existingNotice)")
        case let .error(errorMessage):
            message = .error(errorMessage)
        case nil:
            message = .notice(notice)
        }

        return GlobalSearchPage(
            results: page.results,
            message: message,
            isIndexWarming: page.isIndexWarming
        )
    }

    private nonisolated static func nameResults(
        query: String,
        rootURL: URL,
        spotlightHits: [SpotlightGlobalSearchService.Hit]
    ) -> [ExplorerSearchResult] {
        var seenURLs = Set<URL>()
        let rankedResults: [RankedGlobalSearchResult] = spotlightHits.compactMap {
            hit -> RankedGlobalSearchResult? in
            let url = hit.url.standardizedFileURL
            let relativePath = relativePath(for: url, rootURL: rootURL)
            guard isVisible(relativePath: relativePath),
                  seenURLs.insert(url).inserted else {
                return nil
            }

            let item = FileItem(
                url: url,
                isDirectory: hit.isDirectory,
                isImage: hit.isImage,
                fileSize: hit.byteSize.map { Int64(clamping: $0) },
                modificationDate: hit.modificationDate
            )
            let quality = SearchTextMatch.match(
                in: item.name,
                matching: query
            )?.quality ?? SearchTextMatch.match(
                in: relativePath,
                matching: query
            )?.quality
            guard let quality else { return nil }

            return RankedGlobalSearchResult(
                result: ExplorerSearchResult(
                    id: "global-spotlight:\(url.path(percentEncoded: false))",
                    item: item,
                    relativePath: relativePath,
                    contentMatch: nil
                ),
                quality: quality,
                nativeScore: 0
            )
        }

        return rankedResults
            .sorted { lhs, rhs in
                resultPrecedes(lhs, rhs)
            }
            .prefix(Self.maximumResultCount)
            .map(\.result)
    }

    private nonisolated static func nameResults(
        query: String,
        files: [FFFFileSearchHit],
        directories: [FFFDirectorySearchHit]
    ) -> [ExplorerSearchResult] {
        var seenURLs = Set<URL>()
        let directoryResults: [RankedGlobalSearchResult] = directories.compactMap {
            hit -> RankedGlobalSearchResult? in
            guard isVisible(relativePath: hit.relativePath),
                  seenURLs.insert(hit.url.standardizedFileURL).inserted else {
                return nil
            }

            let result = ExplorerSearchResult(
                id: "global-directory:\(hit.url.path(percentEncoded: false))",
                item: FileItem(
                    url: hit.url,
                    isDirectory: true,
                    isImage: false,
                    fileSize: nil,
                    modificationDate: nil
                ),
                relativePath: hit.relativePath,
                contentMatch: nil
            )
            return RankedGlobalSearchResult(
                result: result,
                quality: SearchTextMatch.match(
                    in: result.item.name,
                    matching: query
                )?.quality,
                nativeScore: hit.score
            )
        }
        let fileResults: [RankedGlobalSearchResult] = files.compactMap {
            hit -> RankedGlobalSearchResult? in
            guard isVisible(relativePath: hit.relativePath),
                  seenURLs.insert(hit.url.standardizedFileURL).inserted else {
                return nil
            }

            let result = ExplorerSearchResult(
                id: "global-file:\(hit.url.path(percentEncoded: false))",
                item: fileItem(
                    url: hit.url,
                    byteSize: hit.byteSize,
                    modificationDate: hit.modificationDate
                ),
                relativePath: hit.relativePath,
                contentMatch: nil
            )
            return RankedGlobalSearchResult(
                result: result,
                quality: SearchTextMatch.match(
                    in: result.item.name,
                    matching: query
                )?.quality,
                nativeScore: hit.score
            )
        }

        return (directoryResults + fileResults)
            .sorted { lhs, rhs in
                resultPrecedes(lhs, rhs)
            }
            .prefix(Self.maximumResultCount)
            .map(\.result)
    }

    private nonisolated static func contentResults(
        _ hits: [FFFContentSearchHit]
    ) -> [ExplorerSearchResult] {
        hits.compactMap { hit in
            guard isVisible(relativePath: hit.relativePath) else { return nil }

            return ExplorerSearchResult(
                id: "global-content:\(hit.id)",
                item: fileItem(
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

    private nonisolated static func resultPrecedes(
        _ lhs: RankedGlobalSearchResult,
        _ rhs: RankedGlobalSearchResult
    ) -> Bool {
        if lhs.quality != rhs.quality {
            if let leftQuality = lhs.quality,
               let rightQuality = rhs.quality {
                return leftQuality < rightQuality
            }
            return lhs.quality != nil
        }
        if lhs.nativeScore != rhs.nativeScore {
            return lhs.nativeScore > rhs.nativeScore
        }
        if lhs.result.item.isDirectory != rhs.result.item.isDirectory {
            return lhs.result.item.isDirectory
        }

        let comparison = lhs.result.relativePath.localizedCaseInsensitiveCompare(
            rhs.result.relativePath
        )
        return comparison == .orderedSame
            ? lhs.result.relativePath < rhs.result.relativePath
            : comparison == .orderedAscending
    }

    private nonisolated static func isVisible(relativePath: String) -> Bool {
        relativePath.split(separator: "/").allSatisfy {
            $0.hasPrefix(".") == false
        }
    }

    private nonisolated static func relativePath(
        for url: URL,
        rootURL: URL
    ) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        let rootPath = rootURL.standardizedFileURL.path(percentEncoded: false)

        guard rootPath != "/" else {
            return path.hasPrefix("/") ? String(path.dropFirst()) : path
        }
        guard path != rootPath else { return url.lastPathComponent }
        let prefix = rootPath + "/"
        return path.hasPrefix(prefix)
            ? String(path.dropFirst(prefix.count))
            : path
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
