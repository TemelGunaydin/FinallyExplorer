//
//  ExplorerSearchModelTests.swift
//  FinallyExplorerTests
//

import Foundation
import Testing
@testable import FinallyExplorer

struct ExplorerSearchModelTests {
    @MainActor
    @Test("Hybrid search includes empty folders, FFF files, and content matches")
    func hybridSearchCombinesBothIndexes() async throws {
        let root = try makeExplorerSearchTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let emptyFolder = root.appending(
            path: "Empty Reports Archive",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: emptyFolder,
            withIntermediateDirectories: false
        )

        let reportURL = root.appending(path: "AnnualSummary.txt")
        try Data("revenueSearchMarker: 42\n".utf8).write(to: reportURL)
        let expectedFolderPath = normalizedTestPath(emptyFolder)
        let expectedReportPath = normalizedTestPath(reportURL)

        let model = ExplorerSearchModel(debounce: {})

        model.query = "Empty Reports"
        await model.search(in: root)
        #expect(model.errorMessage == nil)
        #expect(
            model.results.contains {
                normalizedTestPath($0.item.url) == expectedFolderPath && $0.item.isDirectory
            }
        )

        model.query = "AnnualSummary"
        await model.search(in: root)
        #expect(
            model.results.contains {
                normalizedTestPath($0.item.url) == expectedReportPath && !$0.item.isDirectory
            }
        )

        model.scope = .contents
        model.contentMode = .plain
        model.query = "revenueSearchMarker"
        await model.search(in: root)
        #expect(
            model.results.contains {
                normalizedTestPath($0.item.url) == expectedReportPath
                    && $0.contentMatch?.lineNumber == 1
            }
        )

        await model.shutdown()
    }

    @MainActor
    @Test("A stale request cannot replace a newer query's results")
    func staleCompletionCannotOverwriteNewResults() async throws {
        let root = try makeExplorerSearchTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let oldURL = root.appending(path: "OldSearchResult.txt")
        let newURL = root.appending(path: "NewSearchResult.txt")
        try Data("old".utf8).write(to: oldURL)
        try Data("new".utf8).write(to: newURL)

        let gate = SearchDebounceGate()
        let model = ExplorerSearchModel {
            await gate.suspend()
        }

        model.query = "OldSearchResult"
        let oldRequest = Task { await model.search(in: root) }
        await gate.waitUntilBlockedRequestCount(1)

        model.query = "NewSearchResult"
        let newRequest = Task { await model.search(in: root) }
        await gate.waitUntilBlockedRequestCount(2)

        await gate.resumeRequest(at: 1)
        await newRequest.value
        #expect(model.results.contains { normalizedTestPath($0.item.url) == normalizedTestPath(newURL) })
        let completedNewResults = model.results

        await gate.resumeRequest(at: 0)
        await oldRequest.value
        #expect(model.results.contains { normalizedTestPath($0.item.url) == normalizedTestPath(newURL) })
        #expect(model.results == completedNewResults)
        #expect(model.isSearching == false)
        #expect(model.errorMessage == nil)

        await model.shutdown()
    }

    @MainActor
    @Test("Cancelling a replacement query never exposes results from the old query")
    func cancellationClearsStaleResults() async throws {
        let root = try makeExplorerSearchTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("first".utf8).write(to: root.appending(path: "FirstResult.txt"))
        try Data("second".utf8).write(to: root.appending(path: "SecondResult.txt"))

        let model = ExplorerSearchModel(debounce: { try Task.checkCancellation() })
        model.query = "FirstResult"
        await model.search(in: root)
        try #require(model.results.isEmpty == false)

        let startGate = SearchStartGate()
        model.query = "SecondResult"
        let replacement = Task {
            await startGate.wait()
            await model.search(in: root)
        }

        await startGate.waitUntilBlocked()
        replacement.cancel()
        await startGate.open()
        await replacement.value

        #expect(model.results.isEmpty)
        #expect(model.isSearching == false)
        #expect(model.errorMessage == nil)

        await model.shutdown()
    }

    @MainActor
    @Test("Invalidating an in-flight search without a root restores a coherent state")
    func missingRootInvalidationEndsSearch() async throws {
        let root = try makeExplorerSearchTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("marker".utf8).write(to: root.appending(path: "Marker.txt"))
        let gate = SearchDebounceGate()
        let model = ExplorerSearchModel {
            await gate.suspend()
        }

        model.query = "Marker"
        let pendingSearch = Task { await model.search(in: root) }
        await gate.waitUntilBlockedRequestCount(1)
        #expect(model.isSearching)

        await model.filesDidChange(in: nil)

        #expect(model.results.isEmpty)
        #expect(model.isSearching == false)
        #expect(model.errorMessage == DirectoryAccessError.invalidURL.localizedDescription)

        await gate.resumeRequest(at: 0)
        await pendingSearch.value
        #expect(model.results.isEmpty)
        #expect(model.isSearching == false)
        #expect(model.errorMessage == DirectoryAccessError.invalidURL.localizedDescription)

        await model.shutdown()
    }

    @MainActor
    @Test("A file-system change rescans the existing index before repeating the active query")
    func fileChangeRescansPreparedEngine() async throws {
        let root = try makeExplorerSearchTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let initialURL = root.appending(path: "InitialIndexedFile.txt")
        let addedURL = root.appending(path: "AddedAfterInitialScan.txt")
        try Data("initial".utf8).write(to: initialURL)
        let model = ExplorerSearchModel(debounce: {})

        model.query = "InitialIndexedFile"
        await model.search(in: root)
        try #require(
            model.results.contains {
                normalizedTestPath($0.item.url) == normalizedTestPath(initialURL)
            }
        )

        try Data("added".utf8).write(to: addedURL)
        model.query = "AddedAfterInitialScan"
        await model.filesDidChange(in: root)

        #expect(
            model.results.contains {
                normalizedTestPath($0.item.url) == normalizedTestPath(addedURL)
            }
        )
        #expect(model.isSearching == false)
        #expect(model.errorMessage == nil)

        await model.shutdown()
    }

    @MainActor
    @Test("Whitespace is an inactive query even when the root is missing")
    func whitespaceQueryClearsStateWithoutAnError() async {
        let model = ExplorerSearchModel(debounce: {})
        model.query = " \n\t "

        await model.search(in: nil)

        #expect(model.isSearchActive == false)
        #expect(model.results.isEmpty)
        #expect(model.isSearching == false)
        #expect(model.errorMessage == nil)
    }

    @MainActor
    @Test("A remote-host file URL cannot alias an existing local search root")
    func rejectsRemoteFileHostBeforeIndexing() async throws {
        let root = try makeExplorerSearchTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("marker".utf8).write(to: root.appending(path: "Marker.txt"))
        var components = try #require(
            URLComponents(url: root, resolvingAgainstBaseURL: false)
        )
        components.host = "remote.example.invalid"
        let remoteAlias = try #require(components.url)
        let model = ExplorerSearchModel(debounce: {})
        model.query = "Marker"

        await model.search(in: remoteAlias)

        #expect(model.results.isEmpty)
        #expect(model.isSearching == false)
        #expect(
            model.errorMessage
                == FFFSearchError.invalidRootURL(remoteAlias).localizedDescription
        )

        await model.shutdown()
    }
}

private actor SearchDebounceGate {
    private var nextRequestIndex = 0
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]

    func suspend() async {
        let requestIndex = nextRequestIndex
        nextRequestIndex += 1

        await withCheckedContinuation { continuation in
            continuations[requestIndex] = continuation
        }
    }

    func waitUntilBlockedRequestCount(_ expectedCount: Int) async {
        while continuations.count < expectedCount {
            await Task.yield()
        }
    }

    func resumeRequest(at index: Int) {
        continuations.removeValue(forKey: index)?.resume()
    }
}

private actor SearchStartGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilBlocked() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

private func makeExplorerSearchTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "FinallyExplorerSearchModelTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    return root
}

private func normalizedTestPath(_ url: URL) -> String {
    let path = url.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
    return path.hasSuffix("/") ? String(path.dropLast()) : path
}
