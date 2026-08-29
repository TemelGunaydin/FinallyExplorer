//
//  DirectorySearchService.swift
//  FinallyExplorer
//

import Foundation

nonisolated struct DirectorySearchResult: Identifiable, Hashable, Sendable {
    let url: URL
    let relativePath: String
    let matchScore: Int

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// Metadata retained alongside a directory page so callers can distinguish a
/// complete zero-result search from a deliberately capped result list.
nonisolated struct DirectorySearchPage: Equatable, Sendable {
    let results: [DirectorySearchResult]
    let totalMatched: Int

    var isTruncated: Bool {
        results.count < totalMatched
    }
}

nonisolated enum DirectorySearchError: LocalizedError, Equatable, Sendable {
    case rootIsNotDirectory(path: String)
    case unableToEnumerate(path: String)

    var errorDescription: String? {
        switch self {
        case let .rootIsNotDirectory(path):
            "The search root is not a directory.\n\nPath: \(path)"
        case let .unableToEnumerate(path):
            "Unable to search this directory.\n\nPath: \(path)"
        }
    }
}

/// Maintains one cancellable, immutable directory catalog per active root.
///
/// FFF does not return empty or ancestor-only folders, so the catalog remains
/// the small filesystem-backed supplement to its file index. Building it is
/// intentionally independent of an individual search request: typing another
/// character must not restart a recursive filesystem walk.
actor DirectorySearchService {
    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
    ]

    private struct CatalogEntry: Hashable, Sendable {
        let url: URL
        let relativePath: String
        let normalizedName: String
        let normalizedRelativePath: String
    }

    private struct Catalog: Sendable {
        let rootURL: URL
        let entries: [CatalogEntry]
    }

    private let onCatalogBuild: @Sendable () async -> Void

    private var catalog: Catalog?
    private var catalogRootURL: URL?
    private var catalogGeneration = 0
    private var catalogBuildTask: Task<Catalog, Error>?

    init(
        onCatalogBuild: @escaping @Sendable () async -> Void = {}
    ) {
        self.onCatalogBuild = onCatalogBuild
    }

    deinit {
        catalogBuildTask?.cancel()
    }

    /// Searches the cached visible-folder catalog below `root`.
    ///
    /// The first request for a root starts exactly one catalog build. Later
    /// requests await the same owned task rather than recursively enumerating
    /// the tree again. The build continues if an individual caller is
    /// cancelled, allowing the next keystroke to reuse it.
    func searchPage(
        in root: URL,
        matching query: String,
        limit: Int? = nil
    ) async throws -> DirectorySearchPage {
        try Task.checkCancellation()

        guard limit.map({ $0 > 0 }) ?? true else {
            return DirectorySearchPage(results: [], totalMatched: 0)
        }

        let resolvedRoot = try Self.validatedRootURL(root)
        let catalog = try await catalog(for: resolvedRoot)
        try Task.checkCancellation()

        let normalizedQuery = Self.normalized(
            query.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return Self.makePage(
            from: catalog.entries,
            matching: normalizedQuery,
            limit: limit
        )
    }

    /// Compatibility convenience for call sites that only need the rows.
    func search(
        in root: URL,
        matching query: String,
        limit: Int? = nil
    ) async throws -> [DirectorySearchResult] {
        try await searchPage(in: root, matching: query, limit: limit).results
    }

    /// Invalidates a root after an operation known to alter its folder tree.
    /// A pending build for that root is cancelled; a later query recreates it.
    func invalidate(root: URL?) {
        guard let root,
              Self.isLocalFileURL(root) else {
            return
        }

        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        guard catalogRootURL == resolvedRoot else { return }

        catalogGeneration += 1
        catalog = nil
        catalogRootURL = nil
        catalogBuildTask?.cancel()
        catalogBuildTask = nil
    }

    func shutdown() {
        catalogGeneration += 1
        catalog = nil
        catalogRootURL = nil
        catalogBuildTask?.cancel()
        catalogBuildTask = nil
    }

    private func catalog(for rootURL: URL) async throws -> Catalog {
        while true {
            if let catalog, catalog.rootURL == rootURL {
                return catalog
            }

            let generation: Int
            let task: Task<Catalog, Error>

            if catalogRootURL == rootURL, let catalogBuildTask {
                generation = catalogGeneration
                task = catalogBuildTask
            } else {
                catalogBuildTask?.cancel()
                catalog = nil
                catalogRootURL = rootURL
                catalogGeneration += 1
                generation = catalogGeneration

                let onCatalogBuild = onCatalogBuild
                task = Task(priority: .userInitiated) {
                    await onCatalogBuild()
                    return try await Self.buildCatalog(at: rootURL)
                }
                catalogBuildTask = task
            }

            do {
                let builtCatalog = try await task.value

                guard catalogRootURL == rootURL,
                      catalogGeneration == generation else {
                    // A newer root has superseded this model's only active
                    // catalog. Do not let the old caller restart its scan and
                    // cancel the newer one in a root-switch ping-pong.
                    throw CancellationError()
                }

                // Publish the immutable catalog before honoring this
                // particular caller's cancellation. The owned build may have
                // completed successfully while a stale keystroke was being
                // cancelled; the next query should still reuse its work.
                catalog = builtCatalog
                catalogBuildTask = nil
                try Task.checkCancellation()
                return builtCatalog
            } catch is CancellationError {
                guard catalogRootURL == rootURL,
                      catalogGeneration == generation else {
                    throw CancellationError()
                }

                catalogBuildTask = nil
                throw CancellationError()
            } catch {
                guard catalogRootURL == rootURL,
                      catalogGeneration == generation else {
                    throw CancellationError()
                }

                catalogBuildTask = nil
                throw error
            }
        }
    }

    @concurrent
    private static func buildCatalog(at rootURL: URL) async throws -> Catalog {
        let rootURL = try validatedRootURL(rootURL)
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            throw DirectorySearchError.unableToEnumerate(path: rootURL.path)
        }

        var entries: [CatalogEntry] = []

        while let childURL = enumerator.nextObject() as? URL {
            try Task.checkCancellation()

            guard let values = try? childURL.resourceValues(forKeys: resourceKeys),
                  values.isDirectory == true else {
                continue
            }

            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
            }

            let relativePath = relativePath(of: childURL, below: rootURL)
            entries.append(
                CatalogEntry(
                    url: childURL,
                    relativePath: relativePath,
                    normalizedName: normalized(childURL.lastPathComponent),
                    normalizedRelativePath: normalized(relativePath)
                )
            )
        }

        try Task.checkCancellation()
        return Catalog(rootURL: rootURL, entries: entries)
    }

    private static func makePage(
        from entries: [CatalogEntry],
        matching query: String,
        limit: Int?
    ) -> DirectorySearchPage {
        let maximumResults = limit ?? .max
        var results: [DirectorySearchResult] = []
        var totalMatched = 0

        for entry in entries {
            guard let matchScore = matchScore(
                query: query,
                normalizedName: entry.normalizedName,
                normalizedRelativePath: entry.normalizedRelativePath
            ) else {
                continue
            }

            totalMatched += 1
            let result = DirectorySearchResult(
                url: entry.url,
                relativePath: entry.relativePath,
                matchScore: matchScore
            )

            guard results.count >= maximumResults else {
                results.append(result)
                continue
            }

            guard let worstIndex = results.indices.max(by: {
                displayOrder(results[$0], results[$1])
            }), displayOrder(result, results[worstIndex]) else {
                continue
            }

            results[worstIndex] = result
        }

        results.sort(by: displayOrder)
        return DirectorySearchPage(results: results, totalMatched: totalMatched)
    }

    private static func validatedRootURL(_ root: URL) throws -> URL {
        guard isLocalFileURL(root) else {
            throw DirectorySearchError.rootIsNotDirectory(path: root.absoluteString)
        }

        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let rootValues: URLResourceValues
        do {
            rootValues = try resolvedRoot.resourceValues(forKeys: [.isDirectoryKey])
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw DirectorySearchError.rootIsNotDirectory(path: resolvedRoot.path)
        } catch {
            throw DirectorySearchError.unableToEnumerate(path: resolvedRoot.path)
        }

        guard rootValues.isDirectory == true else {
            throw DirectorySearchError.rootIsNotDirectory(path: resolvedRoot.path)
        }

        return resolvedRoot
    }

    private static func isLocalFileURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        guard let host = url.host, host.isEmpty == false else { return true }
        return host.caseInsensitiveCompare("localhost") == .orderedSame
    }

    private static func relativePath(of child: URL, below root: URL) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let childPath = child.standardizedFileURL.path

        guard childPath.hasPrefix(rootPath) else {
            return child.lastPathComponent
        }

        return String(childPath.dropFirst(rootPath.count))
    }

    private static func matchScore(
        query: String,
        normalizedName: String,
        normalizedRelativePath: String
    ) -> Int? {
        guard query.isEmpty == false else { return 0 }

        let nameScore = fuzzyScore(query: query, candidate: normalizedName)
        let pathScore = fuzzyScore(
            query: query,
            candidate: normalizedRelativePath
        ).map { $0 + 80 }

        return switch (nameScore, pathScore) {
        case let (nameScore?, pathScore?):
            min(nameScore, pathScore)
        case let (nameScore?, nil):
            nameScore
        case let (nil, pathScore?):
            pathScore
        case (nil, nil):
            nil
        }
    }

    private static func fuzzyScore(query: String, candidate: String) -> Int? {
        if candidate == query {
            return 0
        }

        if candidate.hasPrefix(query) {
            return 10 + candidate.count - query.count
        }

        if let range = candidate.range(of: query) {
            let offset = candidate.distance(from: candidate.startIndex, to: range.lowerBound)
            return 40 + offset + candidate.count - query.count
        }

        var queryIndex = query.startIndex
        var previousMatchOffset: Int?
        var firstMatchOffset: Int?
        var gapCount = 0

        for (candidateOffset, character) in candidate.enumerated() {
            guard queryIndex < query.endIndex,
                  character == query[queryIndex] else {
                continue
            }

            firstMatchOffset = firstMatchOffset ?? candidateOffset
            if let previousMatchOffset {
                gapCount += max(0, candidateOffset - previousMatchOffset - 1)
            }

            previousMatchOffset = candidateOffset
            query.formIndex(after: &queryIndex)

            if queryIndex == query.endIndex {
                return 100
                    + (firstMatchOffset ?? 0)
                    + gapCount * 3
                    + candidate.count - query.count
            }
        }

        return nil
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }

    private static func displayOrder(
        _ lhs: DirectorySearchResult,
        _ rhs: DirectorySearchResult
    ) -> Bool {
        if lhs.matchScore != rhs.matchScore {
            return lhs.matchScore < rhs.matchScore
        }

        let comparison = lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }

        return lhs.relativePath < rhs.relativePath
    }
}
