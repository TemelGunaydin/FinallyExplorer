//
//  FFFSearchEngineTests.swift
//  FinallyExplorerTests
//

import Foundation
import Testing
@testable import FinallyExplorer

struct FFFSearchEngineTests {
    @Test("The filesystem root can initialize a global search index")
    func fileSystemRootCanInitialize() async throws {
        let root = URL(filePath: "/", directoryHint: .isDirectory)
        let engine = FFFSearchEngine(rootURL: root)

        do {
            try await engine.start()
            await engine.shutdown()
        } catch {
            await engine.shutdown()
            throw error
        }
    }

    @Test("The native engine searches paths and file contents in every supported mode")
    func nativeSearchRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "FinallyExplorerFFFTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let reportsDirectory = root.appending(
            path: "Reports Archive",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: reportsDirectory,
            withIntermediateDirectories: false
        )
        let sourceURL = reportsDirectory.appending(path: "QuarterlyReport.swift")
        try Data("let uniqueSearchNeedle = 42\n".utf8).write(to: sourceURL)

        let engine = FFFSearchEngine(rootURL: root)

        do {
            try await engine.prepare()

            async let filesRequest = engine.searchFiles(query: "QuarterlyReport", limit: 20)
            async let directoriesRequest = engine.searchDirectories(
                query: "Reports Archive",
                limit: 20
            )
            async let plainRequest = engine.searchContent(
                query: "uniqueSearchNeedle",
                mode: .plain,
                limit: 20,
                timeBudgetMilliseconds: 1_000
            )
            async let regexRequest = engine.searchContent(
                query: "uniqueSearch[A-Za-z]+",
                mode: .regex,
                limit: 20,
                timeBudgetMilliseconds: 1_000
            )
            async let fuzzyRequest = engine.searchContent(
                query: "uniqueSearchNeedle",
                mode: .fuzzy,
                limit: 20,
                timeBudgetMilliseconds: 1_000
            )
            let (files, directories, plain, regex, fuzzy) = try await (
                filesRequest,
                directoriesRequest,
                plainRequest,
                regexRequest,
                fuzzyRequest
            )

            #expect(files.contains { $0.url == sourceURL })
            #expect(directories.contains { $0.relativePath == "Reports Archive" })
            #expect(plain.contains { $0.url == sourceURL && $0.lineNumber == 1 })
            #expect(regex.contains { $0.url == sourceURL })
            #expect(fuzzy.contains { $0.url == sourceURL })

            await engine.shutdown()
        } catch {
            await engine.shutdown()
            throw error
        }
    }

    @Test("FFF timestamp and byte-range sentinels map without overflow")
    func scalarValueMappingsAreStable() {
        #expect(FFFSearchValueMapper.modificationDate(unixSeconds: 0) == nil)
        #expect(
            FFFSearchValueMapper.modificationDate(unixSeconds: 1)
                == Date(timeIntervalSince1970: 1)
        )

        #expect(FFFSearchValueMapper.byteRange(start: 0, end: 0) == 0..<0)
        #expect(FFFSearchValueMapper.byteRange(start: 2, end: 5) == 2..<5)
        #expect(FFFSearchValueMapper.byteRange(start: 5, end: 2) == nil)
        #expect(
            FFFSearchValueMapper.byteRange(start: .max, end: .max)
                == Int(UInt32.max)..<Int(UInt32.max)
        )
    }

    @Test("Broad scan permissions are enabled only for the filesystem and Home roots")
    func broadScanPermissionsMatchTheSelectedRoot() {
        let fileSystemRoot = URL(filePath: "/", directoryHint: .isDirectory)
        let home = URL(
            filePath: "/Users/example",
            directoryHint: .isDirectory
        )
        let project = home.appending(path: "Projects/App", directoryHint: .isDirectory)

        #expect(
            FFFRootScanPolicy.allowsFileSystemRootScanning(for: fileSystemRoot)
        )
        #expect(
            FFFRootScanPolicy.allowsHomeDirectoryScanning(
                for: fileSystemRoot,
                homeDirectoryURL: home
            ) == false
        )
        #expect(
            FFFRootScanPolicy.allowsHomeDirectoryScanning(
                for: home,
                homeDirectoryURL: home
            )
        )
        #expect(
            FFFRootScanPolicy.allowsFileSystemRootScanning(for: project) == false
        )
        #expect(
            FFFRootScanPolicy.allowsHomeDirectoryScanning(
                for: project,
                homeDirectoryURL: home
            ) == false
        )
    }

    @Test("User-facing native failures hide the internal engine name")
    func nativeErrorsUseProductLanguage() throws {
        let error = FFFSearchError.operationFailed(
            operation: "create a search index",
            message: "Cannot run certain FFF features here."
        )
        let description = try #require(error.errorDescription)

        #expect(description.localizedCaseInsensitiveContains("FFF") == false)
        #expect(description.localizedCaseInsensitiveContains("search engine"))
    }

    @Test("FFF relative paths normalize directories and cannot escape their root")
    func itemURLRejectsMalformedRelativePaths() throws {
        let root = URL(filePath: "/tmp/fff-root", directoryHint: .isDirectory)
        let remoteRoot = try #require(URL(string: "https://example.invalid"))
        var remoteFileComponents = try #require(
            URLComponents(url: root, resolvingAgainstBaseURL: false)
        )
        remoteFileComponents.host = "remote.example.invalid"
        let remoteFileRoot = try #require(remoteFileComponents.url)
        var localhostComponents = try #require(
            URLComponents(url: root, resolvingAgainstBaseURL: false)
        )
        localhostComponents.host = "LOCALHOST"
        let localhostRoot = try #require(localhostComponents.url)

        #expect(
            FFFSearchValueMapper.itemURL(
                rootURL: root,
                relativePath: "Raporlar/özgeçmiş.txt"
            ) == root.appending(path: "Raporlar/özgeçmiş.txt").standardizedFileURL
        )
        #expect(FFFSearchValueMapper.itemURL(rootURL: root, relativePath: "../secret") == nil)
        #expect(
            FFFSearchValueMapper.itemURL(
                rootURL: root,
                relativePath: "nested/../../fff-root-evil/secret"
            ) == nil
        )
        #expect(FFFSearchValueMapper.itemURL(rootURL: root, relativePath: "/etc/passwd") == nil)
        #expect(FFFSearchValueMapper.itemURL(rootURL: root, relativePath: "") == nil)
        #expect(FFFSearchValueMapper.itemURL(rootURL: root, relativePath: ".") == nil)
        #expect(
            FFFSearchValueMapper.itemURL(
                rootURL: remoteRoot,
                relativePath: "file.txt"
            ) == nil
        )
        #expect(
            FFFSearchValueMapper.itemURL(
                rootURL: remoteFileRoot,
                relativePath: "file.txt"
            ) == nil
        )
        #expect(
            FFFSearchValueMapper.itemURL(
                rootURL: localhostRoot,
                relativePath: "file.txt"
            ) == root.appending(path: "file.txt").standardizedFileURL
        )
        #expect(
            FFFSearchValueMapper.normalizedDirectoryRelativePath("Reports Archive/")
                == "Reports Archive"
        )
        #expect(
            FFFSearchValueMapper.normalizedDirectoryRelativePath("nested/path///")
                == "nested/path"
        )
        #expect(FFFSearchValueMapper.normalizedDirectoryRelativePath("/") == nil)
        #expect(FFFSearchValueMapper.normalizedDirectoryRelativePath("") == nil)
    }

    @Test(
        "Result limits reject zero, negative, and resource-exhausting values",
        arguments: [0, -1, FFFSearchInputValidator.maximumResultLimit + 1, Int.max]
    )
    func rejectsInvalidResultLimits(limit: Int) {
        do {
            _ = try FFFSearchInputValidator.checkedLimit(limit)
            Issue.record("Expected limit \(limit) to be rejected.")
        } catch let error as FFFSearchError {
            #expect(error == .invalidLimit(limit))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Result-limit boundaries convert without truncation")
    func acceptsResultLimitBoundaries() throws {
        #expect(try FFFSearchInputValidator.checkedLimit(1) == 1)
        #expect(
            try FFFSearchInputValidator.checkedLimit(
                FFFSearchInputValidator.maximumResultLimit
            ) == UInt32(FFFSearchInputValidator.maximumResultLimit)
        )
    }

    @Test(
        "Time budgets reject negative and monopolizing values",
        arguments: [
            -1,
            FFFSearchInputValidator.maximumTimeBudgetMilliseconds + 1,
            Int.max,
        ]
    )
    func rejectsInvalidTimeBudgets(milliseconds: Int) {
        do {
            _ = try FFFSearchInputValidator.checkedTimeBudget(milliseconds)
            Issue.record("Expected time budget \(milliseconds) to be rejected.")
        } catch let error as FFFSearchError {
            #expect(error == .invalidTimeBudget(milliseconds))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Time-budget boundaries convert without overflow")
    func acceptsTimeBudgetBoundaries() throws {
        #expect(try FFFSearchInputValidator.checkedTimeBudget(0) == 0)
        #expect(
            try FFFSearchInputValidator.checkedTimeBudget(
                FFFSearchInputValidator.maximumTimeBudgetMilliseconds
            ) == UInt64(FFFSearchInputValidator.maximumTimeBudgetMilliseconds)
        )
    }

    @Test("Corrupt native collection counts are rejected before allocation")
    func rejectsOversizedPayloadCounts() throws {
        #expect(
            try FFFSearchInputValidator.checkedPayloadCount(
                UInt32(FFFSearchInputValidator.maximumResultLimit),
                operation: "test operation",
                field: "item count"
            ) == FFFSearchInputValidator.maximumResultLimit
        )

        do {
            _ = try FFFSearchInputValidator.checkedPayloadCount(
                UInt32(FFFSearchInputValidator.maximumResultLimit + 1),
                operation: "test operation",
                field: "item count"
            )
            Issue.record("Expected a corrupt native count to be rejected.")
        } catch let error as FFFSearchError {
            #expect(
                error == .invalidPayload(
                    operation: "test operation",
                    field: "item count"
                )
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Queries are bounded by UTF-8 bytes and reject embedded C terminators")
    func validatesQueryBoundary() throws {
        let largestValidUnicodeQuery = String(repeating: "é", count: 2_048)
        let oversizedUnicodeQuery = largestValidUnicodeQuery + "é"

        #expect(throws: Never.self) {
            try FFFSearchInputValidator.validate(query: largestValidUnicodeQuery)
        }

        do {
            try FFFSearchInputValidator.validate(query: oversizedUnicodeQuery)
            Issue.record("Expected an oversized UTF-8 query to be rejected.")
        } catch let FFFSearchError.invalidQuery(reason) {
            #expect(reason.contains("4,096") || reason.contains("4096"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        do {
            try FFFSearchInputValidator.validate(query: "visible\0discarded")
            Issue.record("Expected an embedded null character to be rejected.")
        } catch let FFFSearchError.invalidQuery(reason) {
            #expect(reason.contains("null"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Prepare is idempotent and shutdown leaves no usable stale handle")
    func lifecycleIsTransactional() async throws {
        let root = try makeFFFTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appending(path: "Lifecycle.txt")
        try Data("lifecycle marker".utf8).write(to: sourceURL)
        let engine = FFFSearchEngine(rootURL: root)

        do {
            do {
                _ = try await engine.searchFiles(query: "Lifecycle")
                Issue.record("Expected an unprepared engine to reject search.")
            } catch let error as FFFSearchError {
                #expect(error == .notPrepared)
            }

            async let firstPreparation: Void = engine.prepare()
            async let secondPreparation: Void = engine.prepare()
            _ = try await (firstPreparation, secondPreparation)

            let initialHits = try await engine.searchFiles(query: "Lifecycle")
            #expect(initialHits.contains { $0.url == sourceURL })

            await engine.shutdown()

            do {
                _ = try await engine.searchFiles(query: "Lifecycle")
                Issue.record("Expected shutdown to invalidate the native handle.")
            } catch let error as FFFSearchError {
                #expect(error == .notPrepared)
            }

            try await engine.prepare()
            let rebuiltHits = try await engine.searchFiles(query: "Lifecycle")
            #expect(rebuiltHits.contains { $0.url == sourceURL })

            await engine.shutdown()
        } catch {
            await engine.shutdown()
            throw error
        }
    }

    @Test("File-result pages preserve total-match metadata when the UI cap is reached")
    func fileSearchPageExposesTruncation() async throws {
        let root = try makeFFFTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        for index in 0..<4 {
            try Data("marker".utf8).write(
                to: root.appending(path: "PagedNeedle-\(index).txt")
            )
        }

        let engine = FFFSearchEngine(rootURL: root)
        do {
            try await engine.prepare()
            let page = try await engine.searchFilesPage(
                query: "PagedNeedle",
                limit: 2
            )

            #expect(page.hits.count == 2)
            #expect(page.totalMatched == 4)
            #expect(page.isTruncated)

            await engine.shutdown()
        } catch {
            await engine.shutdown()
            throw error
        }
    }

    @Test("A per-root pool shares one index until its final lease is released")
    func sharedEnginePoolReferenceCountsLeases() async throws {
        let root = try makeFFFTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appending(path: "SharedIndexMarker.txt")
        try Data("shared index marker".utf8).write(to: sourceURL)

        let pool = FFFSearchEnginePool()
        let first = try await pool.acquire(rootURL: root)
        let second = try await pool.acquire(rootURL: root.standardizedFileURL)

        do {
            #expect(first === second)
            let initialIndexCount = await pool.activeIndexCount()
            let initialLeaseCount = await pool.leaseCount(for: root)
            #expect(initialIndexCount == 1)
            #expect(initialLeaseCount == 2)

            await pool.release(first, rootURL: root)
            let remainingLeaseCount = await pool.leaseCount(for: root)
            #expect(remainingLeaseCount == 1)

            try await second.waitForInitialScan()
            let hits = try await second.searchFiles(query: "SharedIndexMarker")
            #expect(hits.contains { $0.url == sourceURL })

            await pool.release(second, rootURL: root)
            let finalIndexCount = await pool.activeIndexCount()
            #expect(finalIndexCount == 0)

            do {
                _ = try await second.searchFiles(query: "SharedIndexMarker")
                Issue.record("Expected final lease release to invalidate the native handle.")
            } catch let error as FFFSearchError {
                #expect(error == .notPrepared)
            }
        } catch {
            await pool.release(first, rootURL: root)
            await pool.release(second, rootURL: root)
            throw error
        }
    }

    @Test(
        "Page offsets reject negative and resource-exhausting values",
        arguments: [-1, FFFSearchInputValidator.maximumPageIndex + 1, Int.max]
    )
    func rejectsInvalidPageOffsets(offset: Int) {
        do {
            _ = try FFFSearchInputValidator.checkedPageIndex(offset)
            Issue.record("Expected page offset \(offset) to be rejected.")
        } catch let error as FFFSearchError {
            #expect(error == .invalidPageIndex(offset))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Content continuation metadata distinguishes a complete and capped page")
    func contentPageContinuationStateIsExplicit() {
        let complete = FFFContentSearchPage(
            hits: [],
            totalMatched: 0,
            totalFilesSearched: 12,
            totalFiles: 12,
            filteredFileCount: 10,
            nextFileOffset: 0,
            regexFallbackError: nil
        )
        let capped = FFFContentSearchPage(
            hits: [],
            totalMatched: 0,
            totalFilesSearched: 3,
            totalFiles: 12,
            filteredFileCount: 10,
            nextFileOffset: 3,
            regexFallbackError: nil
        )

        #expect(complete.isTruncated == false)
        #expect(capped.isTruncated)
    }

    @Test("Prepare rejects remote URLs, remote file hosts, and regular files")
    func rejectsInvalidRoots() async throws {
        let temporaryRoot = try makeFFFTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let fileURL = temporaryRoot.appending(path: "not-a-folder.txt")
        try Data().write(to: fileURL)
        let remoteURL = try #require(URL(string: "https://example.invalid/search"))
        var remoteFileComponents = try #require(
            URLComponents(url: temporaryRoot, resolvingAgainstBaseURL: false)
        )
        remoteFileComponents.host = "remote.example.invalid"
        let remoteFileURL = try #require(remoteFileComponents.url)

        for root in [fileURL, remoteURL, remoteFileURL] {
            let engine = FFFSearchEngine(rootURL: root)

            do {
                try await engine.prepare()
                Issue.record("Expected \(root) to be rejected as an FFF root.")
            } catch let FFFSearchError.invalidRootURL(rejectedURL) {
                #expect(rejectedURL == root)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }

            await engine.shutdown()
        }
    }

    @Test("A cancelled file search exits before invoking the native operation")
    func searchObservesCancellation() async throws {
        let root = try makeFFFTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("marker".utf8).write(to: root.appending(path: "Marker.txt"))
        let engine = FFFSearchEngine(rootURL: root)
        try await engine.prepare()

        let gate = FFFSearchStartGate()
        let task = Task {
            await gate.wait()
            return try await engine.searchFiles(query: "Marker")
        }

        await gate.waitUntilBlocked()
        task.cancel()
        await gate.open()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        await engine.shutdown()
    }
}

private actor FFFSearchStartGate {
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

private func makeFFFTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
        path: "FinallyExplorerFFFTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}
