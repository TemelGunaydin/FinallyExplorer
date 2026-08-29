//
//  DirectorySearchServiceTests.swift
//  FinallyExplorerTests
//

import Foundation
import Testing
@testable import FinallyExplorer

struct DirectorySearchServiceTests {
    @Test("Empty folders and pure ancestor folders are returned")
    func returnsEveryVisibleDirectory() async throws {
        let root = try makeDirectorySearchTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let ancestor = root.appending(path: "ancestor", directoryHint: .isDirectory)
        let leaf = ancestor.appending(path: "leaf", directoryHint: .isDirectory)
        let empty = root.appending(path: "empty", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: leaf, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: false)
        try Data("content".utf8).write(to: leaf.appending(path: "file.txt"))

        let results = try await DirectorySearchService().search(in: root, matching: "")
        let paths = Set(results.map(\.relativePath))

        #expect(paths == ["ancestor", "ancestor/leaf", "empty"])
    }

    @Test("Hidden folders and their descendants are skipped")
    func skipsHiddenDirectories() async throws {
        let root = try makeDirectorySearchTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let hiddenChild = root.appending(
            path: ".hidden/inside",
            directoryHint: .isDirectory
        )
        let visible = root.appending(path: "visible", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: hiddenChild, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: visible, withIntermediateDirectories: false)

        let results = try await DirectorySearchService().search(in: root, matching: "")

        #expect(results.map(\.relativePath) == ["visible"])
    }

    @Test("Matching handles fuzzy and canonically equivalent Unicode input")
    func usesFriendlyFolderMatching() async throws {
        let root = try makeDirectorySearchTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let resume = root.appending(path: "Résumé Archive", directoryHint: .isDirectory)
        let unrelated = root.appending(path: "Invoices", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: resume, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: false)

        let equivalentQueries = [
            "RESUME",
            "Re\u{301}sume\u{301}",
            "ＲＥＳＵＭＥ",
        ]

        for query in equivalentQueries {
            let results = try await DirectorySearchService().search(
                in: root,
                matching: query
            )
            #expect(results.map(\.name) == ["Résumé Archive"])
        }

        let fuzzyResults = try await DirectorySearchService().search(
            in: root,
            matching: "rsm"
        )
        #expect(fuzzyResults.map(\.name) == ["Résumé Archive"])
    }

    @Test("The limit is applied after ranking and handles integer boundaries")
    func respectsResultLimit() async throws {
        let root = try makeDirectorySearchTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        for name in ["needle", "needle-long", "archive-needle", "n-e-e-d-l-e"] {
            try FileManager.default.createDirectory(
                at: root.appending(path: name, directoryHint: .isDirectory),
                withIntermediateDirectories: false
            )
        }

        let best = try await DirectorySearchService().search(
            in: root,
            matching: "needle",
            limit: 2
        )
        let unlimitedBoundary = try await DirectorySearchService().search(
            in: root,
            matching: "needle",
            limit: .max
        )
        let zero = try await DirectorySearchService().search(
            in: root,
            matching: "needle",
            limit: 0
        )
        let negative = try await DirectorySearchService().search(
            in: root,
            matching: "needle",
            limit: .min
        )

        #expect(best.map(\.name) == ["needle", "needle-long"])
        #expect(unlimitedBoundary.count == 4)
        #expect(zero.isEmpty)
        #expect(negative.isEmpty)
    }

    @Test("Directory symlinks are returned but never traversed")
    func doesNotTraverseDirectorySymlinks() async throws {
        let root = try makeDirectorySearchTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let target = root.appending(path: "target", directoryHint: .isDirectory)
        let leaf = target.appending(path: "leaf", directoryHint: .isDirectory)
        let link = root.appending(path: "linked-target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: leaf, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let results = try await DirectorySearchService().search(in: root, matching: "")
        let paths = Set(results.map(\.relativePath))

        #expect(paths.contains("target/leaf"))
        #expect(paths.contains("linked-target/leaf") == false)
    }

    @Test(
        "Remote URLs, remote file hosts, missing paths, and files are rejected",
        arguments: InvalidDirectorySearchRoot.allCases
    )
    func rejectsInvalidRoots(kind: InvalidDirectorySearchRoot) async throws {
        let temporaryRoot = try makeDirectorySearchTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let root: URL
        switch kind {
        case .nonLocal:
            root = try #require(URL(string: "https://example.invalid/folder"))
        case .remoteFileHost:
            var components = try #require(
                URLComponents(url: temporaryRoot, resolvingAgainstBaseURL: false)
            )
            components.host = "remote.example.invalid"
            root = try #require(components.url)
        case .missing:
            root = temporaryRoot.appending(path: "missing", directoryHint: .isDirectory)
        case .regularFile:
            root = temporaryRoot.appending(path: "file.txt")
            try Data().write(to: root)
        }

        do {
            _ = try await DirectorySearchService().search(in: root, matching: "")
            Issue.record("Expected an invalid search root to be rejected.")
        } catch DirectorySearchError.rootIsNotDirectory {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("The explicit localhost file host remains a valid local root")
    func acceptsLocalhostFileRoot() async throws {
        let root = try makeDirectorySearchTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: root.appending(path: "visible", directoryHint: .isDirectory),
            withIntermediateDirectories: false
        )
        var components = try #require(
            URLComponents(url: root, resolvingAgainstBaseURL: false)
        )
        components.host = "LOCALHOST"
        let localhostRoot = try #require(components.url)

        let results = try await DirectorySearchService().search(
            in: localhostRoot,
            matching: ""
        )

        #expect(results.map(\.relativePath) == ["visible"])
    }

    @Test("A cancelled search exits with CancellationError")
    func respondsToCancellation() async throws {
        let root = try makeDirectorySearchTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let gate = DirectorySearchStartGate()
        let task = Task {
            await gate.wait()
            return try await DirectorySearchService().search(in: root, matching: "")
        }

        await gate.waitUntilBlocked()
        task.cancel()
        await gate.open()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test("A root catalog is reused across queries and rebuilt only after invalidation")
    func cachesCatalogUntilExplicitInvalidation() async throws {
        let root = try makeDirectorySearchTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: root.appending(path: "Initial Folder", directoryHint: .isDirectory),
            withIntermediateDirectories: false
        )

        let recorder = DirectoryCatalogBuildRecorder()
        let service = DirectorySearchService(onCatalogBuild: {
            await recorder.recordBuild()
        })

        _ = try await service.search(in: root, matching: "Initial")
        _ = try await service.search(in: root, matching: "Folder")
        let initialBuildCount = await recorder.buildCount()
        #expect(initialBuildCount == 1)

        let laterFolder = root.appending(path: "Later Folder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: laterFolder,
            withIntermediateDirectories: false
        )
        let cachedResults = try await service.search(in: root, matching: "Later")
        #expect(cachedResults.isEmpty)

        await service.invalidate(root: root)
        let refreshedResults = try await service.search(in: root, matching: "Later")
        #expect(refreshedResults.map(\.relativePath) == ["Later Folder"])
        let rebuiltCount = await recorder.buildCount()
        #expect(rebuiltCount == 2)

        await service.shutdown()
    }

    @Test("Cancelling one query does not abandon the shared catalog build")
    func cancellationDoesNotDiscardSharedCatalogBuild() async throws {
        let root = try makeDirectorySearchTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: root.appending(path: "Shared Folder", directoryHint: .isDirectory),
            withIntermediateDirectories: false
        )

        let gate = DirectoryCatalogBuildGate()
        let recorder = DirectoryCatalogBuildRecorder()
        let service = DirectorySearchService(onCatalogBuild: {
            await recorder.recordBuild()
            await gate.wait()
        })

        let cancelledQuery = Task {
            try await service.search(in: root, matching: "Shared")
        }
        await gate.waitUntilBlocked()
        cancelledQuery.cancel()
        await gate.open()

        await #expect(throws: CancellationError.self) {
            _ = try await cancelledQuery.value
        }

        let survivingQuery = try await service.search(in: root, matching: "Shared")
        #expect(survivingQuery.map(\.name) == ["Shared Folder"])
        let buildCount = await recorder.buildCount()
        #expect(buildCount == 1)

        await service.shutdown()
    }

    @Test("Switching roots cancels the superseded request without restarting its scan")
    func rootSwitchDoesNotPingPongCatalogBuilds() async throws {
        let firstRoot = try makeDirectorySearchTemporaryDirectory()
        let secondRoot = try makeDirectorySearchTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }

        try FileManager.default.createDirectory(
            at: firstRoot.appending(path: "First Root Folder", directoryHint: .isDirectory),
            withIntermediateDirectories: false
        )
        try FileManager.default.createDirectory(
            at: secondRoot.appending(path: "Second Root Folder", directoryHint: .isDirectory),
            withIntermediateDirectories: false
        )

        let gate = DirectoryCatalogBuildGate()
        let recorder = DirectoryCatalogBuildRecorder()
        let service = DirectorySearchService(onCatalogBuild: {
            await recorder.recordBuild()
            await gate.wait()
        })

        let supersededRequest = Task {
            try await service.search(in: firstRoot, matching: "First")
        }
        await gate.waitUntilBlocked(count: 1)

        let currentRequest = Task {
            try await service.search(in: secondRoot, matching: "Second")
        }
        await gate.waitUntilBlocked(count: 2)
        await gate.openAll()

        await #expect(throws: CancellationError.self) {
            _ = try await supersededRequest.value
        }

        let currentResults = try await currentRequest.value
        #expect(currentResults.map(\.name) == ["Second Root Folder"])
        #expect(await recorder.buildCount() == 2)

        await service.shutdown()
    }
}

enum InvalidDirectorySearchRoot: CaseIterable, Sendable {
    case nonLocal
    case remoteFileHost
    case missing
    case regularFile
}

private actor DirectorySearchStartGate {
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

private actor DirectoryCatalogBuildRecorder {
    private var count = 0

    func recordBuild() {
        count += 1
    }

    func buildCount() -> Int {
        count
    }
}

private actor DirectoryCatalogBuildGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitUntilBlocked(count: Int = 1) async {
        while continuations.count < count {
            await Task.yield()
        }
    }

    func open() {
        guard continuations.isEmpty == false else { return }
        continuations.removeFirst().resume()
    }

    func openAll() {
        let pendingContinuations = continuations
        continuations.removeAll()
        pendingContinuations.forEach { $0.resume() }
    }
}

private func makeDirectorySearchTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
        path: "FinallyExplorerDirectorySearchTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}
