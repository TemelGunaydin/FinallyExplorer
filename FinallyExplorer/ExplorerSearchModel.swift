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

@MainActor
@Observable
final class ExplorerSearchModel {
    var query = ""
    var scope: ExplorerSearchScope = .names
    var contentMode: FFFContentSearchMode = .plain

    private(set) var results: [ExplorerSearchResult] = []
    private(set) var isSearching = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var engine: FFFSearchEngine?
    @ObservationIgnored private var engineRootURL: URL?
    @ObservationIgnored private var requestGeneration = 0
    @ObservationIgnored private let debounce: @Sendable () async throws -> Void

    init(
        debounce: @escaping @Sendable () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(150))
        }
    ) {
        self.debounce = debounce
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
            errorMessage = DirectoryAccessError.invalidURL.localizedDescription
            isSearching = false
            return
        }

        isSearching = true
        results = []
        errorMessage = nil

        do {
            try await debounce()
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
                async let fileHits = engine.searchFiles(query: searchQuery, limit: 100)
                async let directoryHits = DirectorySearchService().search(
                    in: rootURL,
                    matching: searchQuery,
                    limit: 100
                )

                let (files, directories) = try await (fileHits, directoryHits)
                try Task.checkCancellation()
                newResults = Self.makeNameResults(files: files, directories: directories)

            case .contents:
                let matches = try await engine.searchContent(
                    query: searchQuery,
                    mode: requestedContentMode,
                    limit: 100,
                    timeBudgetMilliseconds: 250
                )
                try Task.checkCancellation()
                newResults = Self.makeContentResults(matches)
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
            errorMessage = error.localizedDescription
            isSearching = false
        }
    }

    func shutdown() async {
        requestGeneration += 1
        results = []
        errorMessage = nil
        isSearching = false

        let oldEngine = engine
        engine = nil
        engineRootURL = nil
        await oldEngine?.shutdown()
    }

    /// Keeps the explicitly-scanned FFF index in sync after FinallyExplorer
    /// copies or moves an item. Watch mode is intentionally disabled, so app
    /// initiated file changes need one explicit rescan.
    func filesDidChange(in rootURL: URL?) async {
        requestGeneration += 1
        results = []
        errorMessage = nil
        isSearching = false

        guard let rootURL else {
            if isSearchActive {
                errorMessage = DirectoryAccessError.invalidURL.localizedDescription
            }
            return
        }

        guard FFFSearchValueMapper.isLocalFileURL(rootURL) else {
            if isSearchActive {
                errorMessage = FFFSearchError.invalidRootURL(rootURL).localizedDescription
            }
            return
        }

        do {
            let resolvedRootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
            if let engine, engineRootURL == resolvedRootURL {
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
                errorMessage = error.localizedDescription
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
            try await engine.prepare()
            return engine
        }

        let oldEngine = engine
        engine = nil
        engineRootURL = nil
        await oldEngine?.shutdown()

        let newEngine = FFFSearchEngine(rootURL: rootURL)
        engine = newEngine
        engineRootURL = resolvedRootURL

        do {
            try await newEngine.prepare()
            return newEngine
        } catch {
            if engine === newEngine {
                engine = nil
                engineRootURL = nil
            }
            await newEngine.shutdown()
            throw error
        }
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
