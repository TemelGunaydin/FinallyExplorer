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
    func shutdown() async
}

extension GlobalSearchServicing {
    func waitForInitialScan(rootURL: URL) async throws {
        try await prepare(rootURL: rootURL)
    }
}

/// Uses only FFF's native indexes for system-wide queries. In particular, it
/// does not supplement directory hits with a recursive FileManager walk: doing
/// that at `/` would duplicate FFF's scan and can make a first search appear to
/// freeze on large disks.
actor FFFGlobalSearchService: GlobalSearchServicing {
    private static let maximumResultCount = 120

    private let enginePool: FFFSearchEnginePool
    private var engine: FFFSearchEngine?
    private var engineRootURL: URL?
    private var lifecycleGeneration = 0

    init(enginePool: FFFSearchEnginePool = .shared) {
        self.enginePool = enginePool
    }

    func prepare(rootURL: URL) async throws {
        let resolvedRootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let engine = try await preparedEngine(for: resolvedRootURL)

        do {
            try await engine.waitForInitialScan()
            try Task.checkCancellation()

            guard self.engine === engine, engineRootURL == resolvedRootURL else {
                throw CancellationError()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await discardCurrentEngine(engine, rootURL: resolvedRootURL)
            throw error
        }
    }

    func search(
        rootURL: URL,
        query: String,
        scope: ExplorerSearchScope,
        contentMode: FFFContentSearchMode
    ) async throws -> GlobalSearchPage {
        let resolvedRootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
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
        let isIndexWarming = scanProgress.isScanning
            || scanProgress.isWarmupComplete == false

        switch scope {
        case .names:
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
                rootURL: resolvedRootURL,
                generation: generation
            )
            var notices: [String] = []
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
                isIndexWarming: isIndexWarming
            )

        case .contents:
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
                isIndexWarming: isIndexWarming
            )
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

    private func discardCurrentEngine(
        _ engine: FFFSearchEngine,
        rootURL: URL
    ) async {
        guard self.engine === engine, engineRootURL == rootURL else { return }

        lifecycleGeneration += 1
        self.engine = nil
        engineRootURL = nil
        await enginePool.release(engine, rootURL: rootURL)
    }

    func shutdown() async {
        lifecycleGeneration += 1
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

    private nonisolated static func nameResults(
        query: String,
        files: [FFFFileSearchHit],
        directories: [FFFDirectorySearchHit]
    ) -> [ExplorerSearchResult] {
        var seenURLs = Set<URL>()
        let directoryResults: [ExplorerSearchResult] = directories.compactMap {
            hit -> ExplorerSearchResult? in
            guard isVisible(relativePath: hit.relativePath),
                  seenURLs.insert(hit.url.standardizedFileURL).inserted else {
                return nil
            }

            return ExplorerSearchResult(
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
        }
        let fileResults: [ExplorerSearchResult] = files.compactMap {
            hit -> ExplorerSearchResult? in
            guard isVisible(relativePath: hit.relativePath),
                  seenURLs.insert(hit.url.standardizedFileURL).inserted else {
                return nil
            }

            return ExplorerSearchResult(
                id: "global-file:\(hit.url.path(percentEncoded: false))",
                item: fileItem(
                    url: hit.url,
                    byteSize: hit.byteSize,
                    modificationDate: hit.modificationDate
                ),
                relativePath: hit.relativePath,
                contentMatch: nil
            )
        }

        return (directoryResults + fileResults)
            .sorted { lhs, rhs in
                resultPrecedes(lhs, rhs, query: query)
            }
            .prefix(Self.maximumResultCount)
            .map { $0 }
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
        _ lhs: ExplorerSearchResult,
        _ rhs: ExplorerSearchResult,
        query: String
    ) -> Bool {
        let leftQuality = SearchTextMatch.match(
            in: lhs.item.name,
            matching: query
        )?.quality
        let rightQuality = SearchTextMatch.match(
            in: rhs.item.name,
            matching: query
        )?.quality

        if leftQuality != rightQuality {
            if let leftQuality, let rightQuality {
                return leftQuality < rightQuality
            }
            return leftQuality != nil
        }
        if lhs.item.isDirectory != rhs.item.isDirectory {
            return lhs.item.isDirectory
        }

        let comparison = lhs.relativePath.localizedCaseInsensitiveCompare(
            rhs.relativePath
        )
        return comparison == .orderedSame
            ? lhs.relativePath < rhs.relativePath
            : comparison == .orderedAscending
    }

    private nonisolated static func isVisible(relativePath: String) -> Bool {
        relativePath.split(separator: "/").allSatisfy {
            $0.hasPrefix(".") == false
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
