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

/// Complements FFF's file index with an exhaustive list of accessible folders.
///
/// FileManager discovers empty folders and folders that only contain other
/// folders. Hidden entries are skipped with the same option used by the main
/// directory listing service.
nonisolated struct DirectorySearchService: Sendable {
    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
    ]

    /// Searches every visible folder below `root`.
    ///
    /// An empty query returns every folder. A non-empty query is matched against
    /// both the folder name and its relative path. Lower `matchScore` values are
    /// better. The root itself is not included in the results.
    @concurrent
    func search(
        in root: URL,
        matching query: String,
        limit: Int? = nil
    ) async throws -> [DirectorySearchResult] {
        try Task.checkCancellation()

        guard limit.map({ $0 > 0 }) ?? true else { return [] }

        guard Self.isLocalFileURL(root) else {
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

        guard let enumerator = FileManager.default.enumerator(
            at: resolvedRoot,
            includingPropertiesForKeys: Array(Self.resourceKeys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            throw DirectorySearchError.unableToEnumerate(path: resolvedRoot.path)
        }

        let normalizedQuery = Self.normalized(
            query.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        var results: [DirectorySearchResult] = []

        while let childURL = enumerator.nextObject() as? URL {
            try Task.checkCancellation()

            guard let values = try? childURL.resourceValues(forKeys: Self.resourceKeys),
                  values.isDirectory == true else {
                continue
            }

            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
            }

            let relativePath = Self.relativePath(of: childURL, below: resolvedRoot)
            guard let matchScore = Self.matchScore(
                query: normalizedQuery,
                name: childURL.lastPathComponent,
                relativePath: relativePath
            ) else {
                continue
            }

            results.append(
                DirectorySearchResult(
                    url: childURL,
                    relativePath: relativePath,
                    matchScore: matchScore
                )
            )
        }

        try Task.checkCancellation()
        results.sort(by: Self.displayOrder)

        if let limit, results.count > limit {
            return Array(results.prefix(limit))
        }

        return results
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
        name: String,
        relativePath: String
    ) -> Int? {
        guard query.isEmpty == false else { return 0 }

        let normalizedName = normalized(name)
        let normalizedPath = normalized(relativePath)
        let nameScore = fuzzyScore(query: query, candidate: normalizedName)
        let pathScore = fuzzyScore(query: query, candidate: normalizedPath).map { $0 + 80 }

        switch (nameScore, pathScore) {
        case let (nameScore?, pathScore?):
            return min(nameScore, pathScore)
        case let (nameScore?, nil):
            return nameScore
        case let (nil, pathScore?):
            return pathScore
        case (nil, nil):
            return nil
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
