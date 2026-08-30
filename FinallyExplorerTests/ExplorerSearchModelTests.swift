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
        try await waitUntilExplorerSearchResult(in: model) {
            $0.results.contains {
                normalizedTestPath($0.item.url) == expectedFolderPath && $0.item.isDirectory
            }
        }
        #expect(model.errorMessage?.isError != true)
        #expect(
            model.results.contains {
                normalizedTestPath($0.item.url) == expectedFolderPath && $0.item.isDirectory
            }
        )

        model.query = "AnnualSummary"
        await model.search(in: root)
        try await waitUntilExplorerSearchResult(in: model) {
            $0.results.contains {
                normalizedTestPath($0.item.url) == expectedReportPath && !$0.item.isDirectory
            }
        }
        #expect(
            model.results.contains {
                normalizedTestPath($0.item.url) == expectedReportPath && !$0.item.isDirectory
            }
        )

        model.scope = .contents
        model.contentMode = .plain
        model.query = "revenueSearchMarker"
        await model.search(in: root)
        try await waitUntilExplorerSearchResult(in: model) {
            $0.results.contains {
                normalizedTestPath($0.item.url) == expectedReportPath
                    && $0.contentMatch?.lineNumber == 1
            }
        }
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
        try await waitUntilExplorerSearchResult(in: model) {
            $0.results.contains {
                normalizedTestPath($0.item.url) == normalizedTestPath(newURL)
            } && !$0.isSearching
        }
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
        try await waitUntilExplorerSearchResult(in: model) {
            $0.results.contains {
                $0.item.url.lastPathComponent == "FirstResult.txt"
            }
        }
        try #require(
            model.results.contains {
                $0.item.url.lastPathComponent == "FirstResult.txt"
            }
        )

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
        #expect(
            model.errorMessage
                == .error(DirectoryAccessError.invalidURL.localizedDescription)
        )

        await gate.resumeRequest(at: 0)
        await pendingSearch.value
        #expect(model.results.isEmpty)
        #expect(model.isSearching == false)
        #expect(
            model.errorMessage
                == .error(DirectoryAccessError.invalidURL.localizedDescription)
        )

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
        try await waitUntilExplorerSearchResult(in: model) {
            $0.results.contains {
                normalizedTestPath($0.item.url) == normalizedTestPath(initialURL)
            }
        }
        try #require(
            model.results.contains {
                normalizedTestPath($0.item.url) == normalizedTestPath(initialURL)
            }
        )

        try Data("added".utf8).write(to: addedURL)
        model.query = "AddedAfterInitialScan"
        await model.filesDidChange(in: root)
        try await waitUntilExplorerSearchResult(in: model) {
            $0.results.contains {
                normalizedTestPath($0.item.url) == normalizedTestPath(addedURL)
            } && !$0.isSearching
        }

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
    @Test("Clearing a pane search invalidates an in-flight request immediately")
    func clearInvalidatesPendingSearch() async throws {
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

        model.clear()
        #expect(model.query.isEmpty)
        #expect(model.results.isEmpty)
        #expect(model.isSearching == false)
        #expect(model.errorMessage == nil)

        await gate.resumeRequest(at: 0)
        await pendingSearch.value
        #expect(model.query.isEmpty)
        #expect(model.results.isEmpty)
        #expect(model.isSearching == false)
        #expect(model.errorMessage == nil)

        await model.shutdown()
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
                == .error(FFFSearchError.invalidRootURL(remoteAlias).localizedDescription)
        )

        await model.shutdown()
    }

    @MainActor
    @Test("Two explorer panes lease one FFF index for the same folder")
    func panesShareOneRootIndexUntilBothClose() async throws {
        let root = try makeExplorerSearchTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appending(path: "SharedPaneSearch.txt")
        try Data("shared pane search".utf8).write(to: sourceURL)

        let pool = FFFSearchEnginePool()
        let first = ExplorerSearchModel(debounce: {}, enginePool: pool)
        let second = ExplorerSearchModel(debounce: {}, enginePool: pool)

        first.query = "SharedPaneSearch"
        second.query = "SharedPaneSearch"
        await first.search(in: root)
        await second.search(in: root)

        try await waitUntilExplorerSearchResult(in: first) {
            $0.results.contains { normalizedTestPath($0.item.url) == normalizedTestPath(sourceURL) }
        }
        try await waitUntilExplorerSearchResult(in: second) {
            $0.results.contains { normalizedTestPath($0.item.url) == normalizedTestPath(sourceURL) }
        }

        let activeIndexCount = await pool.activeIndexCount()
        let initialLeaseCount = await pool.leaseCount(for: root)
        #expect(activeIndexCount == 1)
        #expect(initialLeaseCount == 2)

        await first.shutdown()
        let remainingLeaseCount = await pool.leaseCount(for: root)
        #expect(remainingLeaseCount == 1)

        second.query = "SharedPaneSearch"
        await second.search(in: root)
        try await waitUntilExplorerSearchResult(in: second) {
            $0.results.contains { normalizedTestPath($0.item.url) == normalizedTestPath(sourceURL) }
        }

        await second.shutdown()
        let finalIndexCount = await pool.activeIndexCount()
        #expect(finalIndexCount == 0)
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

private enum ExplorerSearchTestError: Error {
    case timedOut
}

@MainActor
private func waitUntilExplorerSearchResult(
    in model: ExplorerSearchModel,
    timeout: Duration = .seconds(5),
    condition: @escaping (ExplorerSearchModel) -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while condition(model) == false {
        guard clock.now < deadline else {
            throw ExplorerSearchTestError.timedOut
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
