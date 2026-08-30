//
//  FFFSearchEngine.swift
//  FinallyExplorer
//
//  Swift ownership and concurrency boundary for the FFF C API.
//
//  Integration assumptions:
//  - The Clang module exports the fff.h API from upstream commit 42f38ff.
//  - The linked binary and header both use FFF_CREATE_OPTIONS_VERSION 2.
//  - The Clang module is named CFFF.
//  - Every FffResult envelope is owned by the caller. Payloads have separate
//    destructors and must be copied before either allocation is released.
//

import Dispatch
import Foundation

#if canImport(CFFF)
import CFFF
#endif

/// Shares one FFF index per canonical root between explorer panes. A lease is
/// held only while a model is using that root; when the last lease is released
/// the native handle is torn down rather than leaving a watcher/index alive in
/// the background.
actor FFFSearchEnginePool {
    static let shared = FFFSearchEnginePool()

    private struct StartingEntry {
        let token: UUID
        let engine: FFFSearchEngine
        let startTask: Task<FFFSearchEngine, Error>
    }

    private enum Entry {
        case starting(StartingEntry)
        case ready(engine: FFFSearchEngine, leaseCount: Int)
    }

    private var entries: [URL: Entry] = [:]

    /// Returns a retained shared engine. Concurrent callers for an uncached
    /// root await one start task, so a split created during warm-up cannot
    /// create a second native index.
    func acquire(rootURL: URL) async throws -> FFFSearchEngine {
        let key = Self.canonicalRootURL(rootURL)

        while true {
            switch entries[key] {
            case let .ready(engine, leaseCount):
                if Task.isCancelled {
                    // A completed start with no leases can only occur when
                    // every caller was cancelled during initialization.
                    if leaseCount == 0 {
                        entries.removeValue(forKey: key)
                        await engine.shutdown()
                    }
                    throw CancellationError()
                }

                entries[key] = .ready(engine: engine, leaseCount: leaseCount + 1)
                return engine

            case let .starting(starting):
                do {
                    _ = try await starting.startTask.value
                } catch {
                    if case let .starting(current)? = entries[key],
                       current.token == starting.token {
                        entries.removeValue(forKey: key)
                        await starting.engine.shutdown()
                    }
                    throw error
                }

                // Exactly one waiter promotes the completed start. Any other
                // waiter loops and acquires a normal lease from the ready
                // entry, preserving a single ref-count source of truth.
                if case let .starting(current)? = entries[key],
                   current.token == starting.token {
                    entries[key] = .ready(engine: starting.engine, leaseCount: 0)
                }

            case nil:
                let engine = FFFSearchEngine(rootURL: rootURL)
                let starting = StartingEntry(
                    token: UUID(),
                    engine: engine,
                    startTask: Task {
                        try await engine.start()
                        return engine
                    }
                )
                entries[key] = .starting(starting)
            }
        }
    }

    /// Releases one model's lease. A mismatched root/engine is ignored so a
    /// stale task from a previous pane root can never shut down a newer index.
    func release(_ engine: FFFSearchEngine, rootURL: URL) async {
        let key = Self.canonicalRootURL(rootURL)
        guard case let .ready(current, leaseCount)? = entries[key],
              current === engine else {
            return
        }

        if leaseCount > 1 {
            entries[key] = .ready(engine: current, leaseCount: leaseCount - 1)
        } else {
            entries.removeValue(forKey: key)
            await current.shutdown()
        }
    }

    // Internal observability for deterministic lifecycle tests. It is also a
    // useful diagnostic when investigating an unexpectedly retained index.
    func activeIndexCount() -> Int {
        entries.values.reduce(into: 0) { count, entry in
            if case .ready = entry {
                count += 1
            }
        }
    }

    func leaseCount(for rootURL: URL) -> Int {
        switch entries[Self.canonicalRootURL(rootURL)] {
        case let .ready(_, leaseCount):
            leaseCount
        case .starting, .none:
            0
        }
    }

    private nonisolated static func canonicalRootURL(_ rootURL: URL) -> URL {
        rootURL.standardizedFileURL.resolvingSymlinksInPath()
    }
}

nonisolated enum FFFContentSearchMode: UInt8, CaseIterable, Identifiable, Hashable, Sendable {
    case plain = 0
    case regex = 1
    case fuzzy = 2

    var id: Self { self }

    var title: String {
        switch self {
        case .plain:
            "Plain"
        case .regex:
            "Regex"
        case .fuzzy:
            "Fuzzy"
        }
    }
}

nonisolated struct FFFFileSearchHit: Identifiable, Hashable, Sendable {
    let url: URL
    let relativePath: String
    let fileName: String
    let byteSize: UInt64
    let modificationDate: Date?
    let gitStatus: String?
    let isBinary: Bool
    let score: Int

    var id: URL { url }
}

/// A page returned by FFF's file finder. Keeping the native totals prevents a
/// capped UI list from being presented as a complete result set.
nonisolated struct FFFFileSearchPage: Hashable, Sendable {
    let hits: [FFFFileSearchHit]
    let totalMatched: UInt32
    let totalFiles: UInt32

    var isTruncated: Bool {
        UInt64(hits.count) < UInt64(totalMatched)
    }
}

nonisolated struct FFFDirectorySearchHit: Identifiable, Hashable, Sendable {
    let url: URL
    let relativePath: String
    let directoryName: String
    let score: Int

    var id: URL { url }
}

nonisolated struct FFFContentSearchHit: Identifiable, Hashable, Sendable {
    let url: URL
    let relativePath: String
    let fileName: String
    let lineContent: String
    let lineNumber: UInt64
    let column: UInt32
    let byteOffset: UInt64
    let matchByteRanges: [Range<Int>]
    let contextBefore: [String]
    let contextAfter: [String]
    let byteSize: UInt64
    let modificationDate: Date?
    let gitStatus: String?
    let fuzzyScore: UInt16?
    let isBinary: Bool
    let isDefinition: Bool

    var id: String {
        "\(relativePath):\(lineNumber):\(column):\(byteOffset)"
    }
}

/// A content-search page together with FFF's continuation and regex-fallback
/// state. `nextFileOffset` being non-zero means more indexed files were not
/// searched within the current page/time budget.
nonisolated struct FFFContentSearchPage: Hashable, Sendable {
    let hits: [FFFContentSearchHit]
    let totalMatched: UInt32
    let totalFilesSearched: UInt32
    let totalFiles: UInt32
    let filteredFileCount: UInt32
    let nextFileOffset: UInt32
    let regexFallbackError: String?

    var isTruncated: Bool {
        nextFileOffset != 0
    }
}

nonisolated struct FFFScanProgress: Equatable, Sendable {
    let scannedFileCount: UInt64
    let isScanning: Bool
    let isWatcherReady: Bool
    let isWarmupComplete: Bool
}

nonisolated enum FFFSearchError: LocalizedError, Equatable, Sendable {
    case libraryUnavailable
    case invalidRootURL(URL)
    case notPrepared
    case invalidQuery(reason: String)
    case invalidLimit(Int)
    case invalidPageIndex(Int)
    case invalidTimeBudget(Int)
    case operationFailed(operation: String, message: String)
    case invalidPayload(operation: String, field: String)

    var errorDescription: String? {
        switch self {
        case .libraryUnavailable:
            "The search engine is not available."
        case let .invalidRootURL(url):
            "Search requires an existing local folder.\n\nPath: \(url.path(percentEncoded: false))"
        case .notPrepared:
            "The search index is not ready yet."
        case let .invalidQuery(reason):
            "Search query is invalid: \(reason)"
        case let .invalidLimit(limit):
            "Search result limit must be between 1 and \(FFFSearchInputValidator.maximumResultLimit) (received \(limit))."
        case let .invalidPageIndex(index):
            "Search page index must be between 0 and \(FFFSearchInputValidator.maximumPageIndex) (received \(index))."
        case let .invalidTimeBudget(milliseconds):
            "Search time budget must be between 0 and \(FFFSearchInputValidator.maximumTimeBudgetMilliseconds) ms (received \(milliseconds) ms)."
        case let .operationFailed(operation, message):
            "Search could not \(operation): \(Self.userFacing(message))"
        case let .invalidPayload(operation, field):
            "Search returned an invalid \(field) while attempting to \(operation)."
        }
    }

    private static func userFacing(_ message: String) -> String {
        message.replacingOccurrences(
            of: "FFF",
            with: "search engine",
            options: .caseInsensitive
        )
    }
}

/// Bounds values before they cross the C boundary. Apart from preventing
/// integer truncation, these limits keep a malformed caller from asking the
/// native engine to retain billions of hits or monopolize its serial executor.
nonisolated enum FFFSearchInputValidator {
    static let maximumQueryUTF8ByteCount = 4_096
    static let maximumResultLimit = 10_000
    static let maximumPageIndex = 10_000
    static let maximumTimeBudgetMilliseconds = 60_000

    static func validate(query: String) throws {
        guard query.utf8.contains(0) == false else {
            throw FFFSearchError.invalidQuery(
                reason: "embedded null characters are not supported"
            )
        }

        guard query.utf8.count <= maximumQueryUTF8ByteCount else {
            throw FFFSearchError.invalidQuery(
                reason: "UTF-8 representation exceeds \(maximumQueryUTF8ByteCount) bytes"
            )
        }
    }

    static func checkedLimit(_ limit: Int) throws -> UInt32 {
        guard (1...maximumResultLimit).contains(limit) else {
            throw FFFSearchError.invalidLimit(limit)
        }
        return UInt32(limit)
    }

    static func checkedPageIndex(_ index: Int) throws -> UInt32 {
        guard (0...maximumPageIndex).contains(index) else {
            throw FFFSearchError.invalidPageIndex(index)
        }
        return UInt32(index)
    }

    static func checkedTimeBudget(_ milliseconds: Int) throws -> UInt64 {
        guard (0...maximumTimeBudgetMilliseconds).contains(milliseconds) else {
            throw FFFSearchError.invalidTimeBudget(milliseconds)
        }
        return UInt64(milliseconds)
    }

    static func checkedPayloadCount(
        _ count: UInt32,
        operation: String,
        field: String
    ) throws -> Int {
        guard count <= UInt32(maximumResultLimit) else {
            throw FFFSearchError.invalidPayload(operation: operation, field: field)
        }
        return Int(count)
    }
}

/// Pure mappings intentionally kept outside the FFI actor so they can be unit tested.
nonisolated enum FFFSearchValueMapper {
    static func isLocalFileURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        guard let host = url.host, host.isEmpty == false else { return true }
        return host.caseInsensitiveCompare("localhost") == .orderedSame
    }

    static func modificationDate(unixSeconds: UInt64) -> Date? {
        guard unixSeconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(unixSeconds))
    }

    static func byteRange(start: UInt32, end: UInt32) -> Range<Int>? {
        guard start <= end else { return nil }
        return Int(start)..<Int(end)
    }

    static func normalizedDirectoryRelativePath(_ value: String) -> String? {
        let trailingSlashCount = value.reversed().prefix { $0 == "/" }.count
        let normalized = value.dropLast(trailingSlashCount)
        return normalized.isEmpty ? nil : String(normalized)
    }

    static func itemURL(rootURL: URL, relativePath: String) -> URL? {
        guard isLocalFileURL(rootURL),
              relativePath.isEmpty == false,
              relativePath.hasPrefix("/") == false,
              relativePath.utf8.contains(0) == false else {
            return nil
        }

        let standardizedRoot = rootURL.standardizedFileURL
        let candidate = standardizedRoot
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        let rootPath = standardizedRoot.path(percentEncoded: false)
        let candidatePath = candidate.path(percentEncoded: false)

        guard candidatePath != rootPath else { return nil }

        if rootPath == "/" {
            return candidatePath.hasPrefix("/") ? candidate : nil
        }

        let descendantPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard candidatePath.hasPrefix(descendantPrefix) else { return nil }
        return candidate
    }
}

#if canImport(CFFF)

/// Owns exactly one FFF instance. It deliberately does not conform to Sendable;
/// the enclosing actor is the only code allowed to retain or access it.
private nonisolated final class FFFHandleOwner {
    let rawValue: UnsafeMutableRawPointer

    init(rawValue: UnsafeMutableRawPointer) {
        self.rawValue = rawValue
    }

    deinit {
        fff_destroy(rawValue)
    }
}

/// Serializes all access to the opaque FFF handle on a dedicated executor.
/// FFF calls are synchronous and can be CPU- or disk-heavy, so this executor
/// prevents them from occupying MainActor or a cooperative-pool worker.
actor FFFSearchEngine {
    nonisolated let rootURL: URL

    private nonisolated let executor: DispatchSerialQueue
    private nonisolated let originalRootURL: URL
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }

    private var handleOwner: FFFHandleOwner?

    init(rootURL: URL) {
        originalRootURL = rootURL
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        executor = DispatchSerialQueue(
            label: "com.temelgunaydin.FinallyExplorer.fff-search.\(UUID().uuidString)",
            qos: .userInitiated
        )
    }

    /// Creates FFF's native instance and starts its background scan without
    /// waiting for the complete index. A search may therefore use the partial
    /// index immediately while a separately owned warm-up task continues.
    /// Repeated calls are idempotent.
    func start() throws {
        if handleOwner != nil { return }

        try Task.checkCancellation()
        try validateRootURL()
        handleOwner = try createHandle()
    }

    /// Waits for the initial background scan to complete. The polling sleep
    /// deliberately suspends this actor between quick native checks, letting
    /// searches and progress reads interleave with warm-up.
    func waitForInitialScan() async throws {
        // Keep ownership alive across the actor suspension in the polling
        // loop. `shutdown()` may otherwise clear `handleOwner` while this
        // task is asleep and leave a raw pointer dangling on resume.
        let owner = try preparedHandleOwner()
        try await waitUntilScanFinishes(handle: owner.rawValue)
        try requireCurrent(owner)
    }

    /// Compatibility entry point for clients that need a complete index before
    /// issuing their first query. Cancelling one waiter deliberately leaves a
    /// shared started engine alive for other callers.
    func prepare() async throws {
        try start()
        try await waitForInitialScan()
        try Task.checkCancellation()
    }

    func searchFiles(query: String, limit: Int = 100) async throws -> [FFFFileSearchHit] {
        let page = try await searchFilesPage(query: query, limit: limit)
        return page.hits
    }

    func searchFilesPage(
        query: String,
        limit: Int = 100,
        pageIndex: Int = 0
    ) async throws -> FFFFileSearchPage {
        try FFFSearchInputValidator.validate(query: query)
        let pageSize = try FFFSearchInputValidator.checkedLimit(limit)
        let pageIndex = try FFFSearchInputValidator.checkedPageIndex(pageIndex)
        let handle = try preparedHandle()
        try Task.checkCancellation()

        let envelope = query.withCString { queryPointer in
            fff_search(
                handle,
                queryPointer,
                nil,
                0,
                pageIndex,
                pageSize,
                0,
                0
            )
        }

        let page = try consumePayload(
            envelope,
            operation: "search files",
            as: FffSearchResult.self,
            freePayload: fff_free_search_result
        ) { result in
            FFFFileSearchPage(
                hits: try copyFileHits(from: result),
                totalMatched: fff_search_result_get_total_matched(result),
                totalFiles: fff_search_result_get_total_files(result)
            )
        }

        try Task.checkCancellation()
        return page
    }

    /// Exposes FFF's directory index for callers that want it. FinallyExplorer's
    /// exhaustive folder results remain FileManager-backed because FFF omits
    /// empty and pure-ancestor directories.
    func searchDirectories(
        query: String,
        limit: Int = 100
    ) async throws -> [FFFDirectorySearchHit] {
        try FFFSearchInputValidator.validate(query: query)
        let pageSize = try FFFSearchInputValidator.checkedLimit(limit)
        let handle = try preparedHandle()
        try Task.checkCancellation()

        let envelope = query.withCString { queryPointer in
            fff_search_directories(
                handle,
                queryPointer,
                nil,
                0,
                0,
                pageSize
            )
        }

        let hits = try consumePayload(
            envelope,
            operation: "search directories",
            as: FffDirSearchResult.self,
            freePayload: fff_free_dir_search_result
        ) { result in
            try copyDirectoryHits(from: result)
        }

        try Task.checkCancellation()
        return hits
    }

    func searchContent(
        query: String,
        mode: FFFContentSearchMode = .plain,
        limit: Int = 50,
        timeBudgetMilliseconds: Int = 150
    ) async throws -> [FFFContentSearchHit] {
        let page = try await searchContentPage(
            query: query,
            mode: mode,
            limit: limit,
            timeBudgetMilliseconds: timeBudgetMilliseconds
        )
        return page.hits
    }

    func searchContentPage(
        query: String,
        mode: FFFContentSearchMode = .plain,
        limit: Int = 50,
        timeBudgetMilliseconds: Int = 150,
        fileOffset: Int = 0
    ) async throws -> FFFContentSearchPage {
        try FFFSearchInputValidator.validate(query: query)
        let pageSize = try FFFSearchInputValidator.checkedLimit(limit)
        let fileOffset = try FFFSearchInputValidator.checkedPageIndex(fileOffset)
        let timeBudget = try FFFSearchInputValidator.checkedTimeBudget(
            timeBudgetMilliseconds
        )
        let handle = try preparedHandle()
        try Task.checkCancellation()

        let envelope = query.withCString { queryPointer in
            fff_live_grep(
                handle,
                queryPointer,
                mode.rawValue,
                0,
                0,
                true,
                fileOffset,
                pageSize,
                timeBudget,
                1,
                1,
                true
            )
        }

        let page = try consumePayload(
            envelope,
            operation: "search file contents",
            as: FffGrepResult.self,
            freePayload: fff_free_grep_result
        ) { result in
            FFFContentSearchPage(
                hits: try copyContentHits(from: result),
                totalMatched: fff_grep_result_get_total_matched(result),
                totalFilesSearched: fff_grep_result_get_total_files_searched(result),
                totalFiles: fff_grep_result_get_total_files(result),
                filteredFileCount: fff_grep_result_get_filtered_file_count(result),
                nextFileOffset: fff_grep_result_get_next_file_offset(result),
                regexFallbackError: copiedString(
                    fff_grep_result_get_regex_fallback_error(result)
                )
            )
        }

        try Task.checkCancellation()
        return page
    }

    func scanProgress() async throws -> FFFScanProgress {
        let handle = try preparedHandle()
        try Task.checkCancellation()

        return try consumePayload(
            fff_get_scan_progress(handle),
            operation: "read scan progress",
            as: FffScanProgress.self,
            freePayload: fff_free_scan_progress
        ) { progress in
            let value = progress.pointee
            return FFFScanProgress(
                scannedFileCount: value.scanned_files_count,
                isScanning: value.is_scanning,
                isWatcherReady: value.is_watcher_ready,
                isWarmupComplete: value.is_warmup_complete
            )
        }
    }

    func rescan() async throws {
        // See `waitForInitialScan()`: retain the owner through the async wait.
        let owner = try preparedHandleOwner()
        let handle = owner.rawValue
        try Task.checkCancellation()

        try consumeEmptyResult(
            fff_scan_files(handle),
            operation: "start a rescan"
        )
        try await waitUntilScanFinishes(handle: handle)
        try requireCurrent(owner)
        try Task.checkCancellation()
    }

    /// Idempotently destroys the native instance. Calls already executing on
    /// this actor finish first; queued calls then observe `notPrepared`.
    func shutdown() async {
        handleOwner = nil
    }

    private func validateRootURL() throws {
        guard FFFSearchValueMapper.isLocalFileURL(originalRootURL) else {
            throw FFFSearchError.invalidRootURL(originalRootURL)
        }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(
            atPath: rootURL.path(percentEncoded: false),
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw FFFSearchError.invalidRootURL(rootURL)
        }
    }

    private func createHandle() throws -> FFFHandleOwner {
        var options = FffCreateOptions()
        options.version = 2
        options.frecency_db_path = nil
        options.history_db_path = nil
        options.enable_mmap_cache = false
        options.enable_content_indexing = false
        options.watch = false
        options.ai_mode = false
        options.log_file_path = nil
        options.log_level = nil
        options.cache_budget_max_files = 0
        options.cache_budget_max_bytes = 0
        options.cache_budget_max_file_size = 0
        options.enable_fs_root_scanning = FFFRootScanPolicy
            .allowsFileSystemRootScanning(for: rootURL)
        options.enable_home_dir_scanning = FFFRootScanPolicy
            .allowsHomeDirectoryScanning(for: rootURL)
        options.follow_symlinks = false

        let envelope = rootURL.path(percentEncoded: false).withCString { rootPointer in
            options.base_path = rootPointer
            return withUnsafePointer(to: &options) { optionsPointer in
                fff_create_instance_with(optionsPointer)
            }
        }

        let rawHandle = try consumeInstanceResult(
            envelope,
            operation: "create a search index"
        )
        return FFFHandleOwner(rawValue: rawHandle)
    }

    private func preparedHandle() throws -> UnsafeMutableRawPointer {
        try preparedHandleOwner().rawValue
    }

    private func preparedHandleOwner() throws -> FFFHandleOwner {
        guard let handleOwner else {
            throw FFFSearchError.notPrepared
        }
        return handleOwner
    }

    private func requireCurrent(_ owner: FFFHandleOwner) throws {
        guard let handleOwner, handleOwner === owner else {
            throw FFFSearchError.notPrepared
        }
    }

    private func waitUntilScanFinishes(handle: UnsafeMutableRawPointer) async throws {
        while true {
            try Task.checkCancellation()

            let completed = try consumeIntegerResult(
                // Keep this native wait deliberately short. Some FFF builds
                // treat a zero timeout as an unbounded wait; ten milliseconds
                // still keeps the actor available to partial-index searches.
                fff_wait_for_scan(handle, 10),
                operation: "wait for the file index"
            ) != 0

            if completed { return }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func copyFileHits(
        from result: UnsafeMutablePointer<FffSearchResult>
    ) throws -> [FFFFileSearchHit] {
        let count = fff_search_result_get_count(result)
        let capacity = try FFFSearchInputValidator.checkedPayloadCount(
            count,
            operation: "search files",
            field: "file count"
        )
        var hits: [FFFFileSearchHit] = []
        hits.reserveCapacity(capacity)

        for index in 0..<count {
            guard let item = fff_search_result_get_item(result, index) else {
                throw FFFSearchError.invalidPayload(
                    operation: "search files",
                    field: "file item"
                )
            }

            let relativePath = try requiredString(
                fff_file_item_get_relative_path(item),
                operation: "search files",
                field: "relative path"
            )
            let fileName = copiedString(fff_file_item_get_file_name(item))
                ?? URL(fileURLWithPath: relativePath).lastPathComponent
            guard let itemURL = FFFSearchValueMapper.itemURL(
                rootURL: rootURL,
                relativePath: relativePath
            ) else {
                throw FFFSearchError.invalidPayload(
                    operation: "search files",
                    field: "relative path"
                )
            }
            let modified = fff_file_item_get_modified(item)
            let score = fff_search_result_get_score(result, index)?.pointee.total ?? 0

            hits.append(
                FFFFileSearchHit(
                    url: itemURL,
                    relativePath: relativePath,
                    fileName: fileName,
                    byteSize: fff_file_item_get_size(item),
                    modificationDate: FFFSearchValueMapper.modificationDate(
                        unixSeconds: modified
                    ),
                    gitStatus: copiedString(fff_file_item_get_git_status(item)),
                    isBinary: fff_file_item_get_is_binary(item),
                    score: Int(score)
                )
            )
        }

        return hits
    }

    private func copyDirectoryHits(
        from result: UnsafeMutablePointer<FffDirSearchResult>
    ) throws -> [FFFDirectorySearchHit] {
        let count = result.pointee.count
        let capacity = try FFFSearchInputValidator.checkedPayloadCount(
            count,
            operation: "search directories",
            field: "directory count"
        )
        var hits: [FFFDirectorySearchHit] = []
        hits.reserveCapacity(capacity)

        for index in 0..<count {
            guard let item = fff_dir_search_result_get_item(result, index) else {
                throw FFFSearchError.invalidPayload(
                    operation: "search directories",
                    field: "directory item"
                )
            }

            let rawRelativePath = try requiredString(
                item.pointee.relative_path,
                operation: "search directories",
                field: "relative path"
            )
            guard let relativePath = FFFSearchValueMapper.normalizedDirectoryRelativePath(
                rawRelativePath
            ) else {
                throw FFFSearchError.invalidPayload(
                    operation: "search directories",
                    field: "relative path"
                )
            }
            let directoryName = copiedString(item.pointee.dir_name)
                ?? URL(fileURLWithPath: relativePath).lastPathComponent
            guard let itemURL = FFFSearchValueMapper.itemURL(
                rootURL: rootURL,
                relativePath: relativePath
            ) else {
                throw FFFSearchError.invalidPayload(
                    operation: "search directories",
                    field: "relative path"
                )
            }
            let score = fff_dir_search_result_get_score(result, index)?.pointee.total ?? 0

            hits.append(
                FFFDirectorySearchHit(
                    url: itemURL,
                    relativePath: relativePath,
                    directoryName: directoryName,
                    score: Int(score)
                )
            )
        }

        return hits
    }

    private func copyContentHits(
        from result: UnsafeMutablePointer<FffGrepResult>
    ) throws -> [FFFContentSearchHit] {
        let count = fff_grep_result_get_count(result)
        let capacity = try FFFSearchInputValidator.checkedPayloadCount(
            count,
            operation: "search file contents",
            field: "content-match count"
        )
        var hits: [FFFContentSearchHit] = []
        hits.reserveCapacity(capacity)

        for index in 0..<count {
            guard let match = fff_grep_result_get_match(result, index) else {
                throw FFFSearchError.invalidPayload(
                    operation: "search file contents",
                    field: "content match"
                )
            }

            let relativePath = try requiredString(
                fff_grep_match_get_relative_path(match),
                operation: "search file contents",
                field: "relative path"
            )
            let fileName = copiedString(fff_grep_match_get_file_name(match))
                ?? URL(fileURLWithPath: relativePath).lastPathComponent
            guard let itemURL = FFFSearchValueMapper.itemURL(
                rootURL: rootURL,
                relativePath: relativePath
            ) else {
                throw FFFSearchError.invalidPayload(
                    operation: "search file contents",
                    field: "relative path"
                )
            }
            let lineContent = try requiredString(
                fff_grep_match_get_line_content(match),
                operation: "search file contents",
                field: "matched line"
            )
            let modified = fff_grep_match_get_modified(match)

            hits.append(
                FFFContentSearchHit(
                    url: itemURL,
                    relativePath: relativePath,
                    fileName: fileName,
                    lineContent: lineContent,
                    lineNumber: fff_grep_match_get_line_number(match),
                    column: fff_grep_match_get_col(match),
                    byteOffset: fff_grep_match_get_byte_offset(match),
                    matchByteRanges: try copyMatchRanges(from: match),
                    contextBefore: try copyContextBefore(from: match),
                    contextAfter: try copyContextAfter(from: match),
                    byteSize: fff_grep_match_get_size(match),
                    modificationDate: FFFSearchValueMapper.modificationDate(
                        unixSeconds: modified
                    ),
                    gitStatus: copiedString(fff_grep_match_get_git_status(match)),
                    fuzzyScore: fff_grep_match_get_has_fuzzy_score(match)
                        ? fff_grep_match_get_fuzzy_score(match)
                        : nil,
                    isBinary: fff_grep_match_get_is_binary(match),
                    isDefinition: fff_grep_match_get_is_definition(match)
                )
            )
        }

        return hits
    }

    private func copyMatchRanges(
        from match: UnsafePointer<FffGrepMatch>
    ) throws -> [Range<Int>] {
        let count = fff_grep_match_get_match_ranges_count(match)
        let capacity = try FFFSearchInputValidator.checkedPayloadCount(
            count,
            operation: "search file contents",
            field: "match byte-range count"
        )
        var ranges: [Range<Int>] = []
        ranges.reserveCapacity(capacity)

        for index in 0..<count {
            guard let range = fff_grep_match_get_match_range(match, index),
                  let swiftRange = FFFSearchValueMapper.byteRange(
                      start: range.pointee.start,
                      end: range.pointee.end
                  ) else {
                throw FFFSearchError.invalidPayload(
                    operation: "search file contents",
                    field: "match byte range"
                )
            }
            ranges.append(swiftRange)
        }

        return ranges
    }

    private func copyContextBefore(
        from match: UnsafePointer<FffGrepMatch>
    ) throws -> [String] {
        try copyContext(
            count: fff_grep_match_get_context_before_count(match),
            operation: "search file contents",
            field: "context-before line"
        ) { index in
            fff_grep_match_get_context_before(match, index)
        }
    }

    private func copyContextAfter(
        from match: UnsafePointer<FffGrepMatch>
    ) throws -> [String] {
        try copyContext(
            count: fff_grep_match_get_context_after_count(match),
            operation: "search file contents",
            field: "context-after line"
        ) { index in
            fff_grep_match_get_context_after(match, index)
        }
    }

    private func copyContext(
        count: UInt32,
        operation: String,
        field: String,
        valueAt: (UInt32) -> UnsafePointer<CChar>?
    ) throws -> [String] {
        let capacity = try FFFSearchInputValidator.checkedPayloadCount(
            count,
            operation: operation,
            field: "\(field) count"
        )
        var lines: [String] = []
        lines.reserveCapacity(capacity)

        for index in 0..<count {
            lines.append(
                try requiredString(
                    valueAt(index),
                    operation: operation,
                    field: field
                )
            )
        }

        return lines
    }

    private func requiredString(
        _ pointer: UnsafePointer<CChar>?,
        operation: String,
        field: String
    ) throws -> String {
        guard let value = copiedString(pointer) else {
            throw FFFSearchError.invalidPayload(operation: operation, field: field)
        }
        return value
    }

    private func copiedString(_ pointer: UnsafePointer<CChar>?) -> String? {
        guard let pointer else { return nil }
        return String(validatingCString: pointer)
    }

    /// Consumes a result whose successful handle becomes long-lived instance ownership.
    private func consumeInstanceResult(
        _ envelope: UnsafeMutablePointer<FffResult>?,
        operation: String
    ) throws -> UnsafeMutableRawPointer {
        guard let envelope else {
            throw FFFSearchError.operationFailed(
                operation: operation,
                message: "the native function returned no result envelope"
            )
        }
        defer { fff_free_result(envelope) }

        let rawHandle = fff_result_get_handle(envelope)
        guard fff_result_get_success(envelope) else {
            // The success contract says failures carry no handle. Cleaning a
            // defensive non-null handle here prevents an ownership leak.
            if let rawHandle {
                fff_destroy(rawHandle)
            }
            throw operationError(from: envelope, operation: operation)
        }

        guard let rawHandle else {
            throw FFFSearchError.invalidPayload(operation: operation, field: "instance handle")
        }
        return rawHandle
    }

    /// Consumes both an FffResult envelope and its typed, separately-owned payload.
    private func consumePayload<Payload, Output>(
        _ envelope: UnsafeMutablePointer<FffResult>?,
        operation: String,
        as _: Payload.Type,
        freePayload: (UnsafeMutablePointer<Payload>?) -> Void,
        transform: (UnsafeMutablePointer<Payload>) throws -> Output
    ) throws -> Output {
        guard let envelope else {
            throw FFFSearchError.operationFailed(
                operation: operation,
                message: "the native function returned no result envelope"
            )
        }
        defer { fff_free_result(envelope) }

        let rawPayload = fff_result_get_handle(envelope)
        guard fff_result_get_success(envelope) else {
            if let rawPayload {
                freePayload(rawPayload.assumingMemoryBound(to: Payload.self))
            }
            throw operationError(from: envelope, operation: operation)
        }

        guard let rawPayload else {
            throw FFFSearchError.invalidPayload(operation: operation, field: "result payload")
        }

        let payload = rawPayload.assumingMemoryBound(to: Payload.self)
        defer { freePayload(payload) }
        return try transform(payload)
    }

    private func consumeEmptyResult(
        _ envelope: UnsafeMutablePointer<FffResult>?,
        operation: String
    ) throws {
        guard let envelope else {
            throw FFFSearchError.operationFailed(
                operation: operation,
                message: "the native function returned no result envelope"
            )
        }
        defer { fff_free_result(envelope) }

        guard fff_result_get_success(envelope) else {
            throw operationError(from: envelope, operation: operation)
        }
    }

    private func consumeIntegerResult(
        _ envelope: UnsafeMutablePointer<FffResult>?,
        operation: String
    ) throws -> Int64 {
        guard let envelope else {
            throw FFFSearchError.operationFailed(
                operation: operation,
                message: "the native function returned no result envelope"
            )
        }
        defer { fff_free_result(envelope) }

        guard fff_result_get_success(envelope) else {
            throw operationError(from: envelope, operation: operation)
        }
        return fff_result_get_int_value(envelope)
    }

    private func operationError(
        from envelope: UnsafePointer<FffResult>,
        operation: String
    ) -> FFFSearchError {
        let message = copiedString(fff_result_get_error(envelope))
            ?? "an unknown native error occurred"
        return .operationFailed(operation: operation, message: message)
    }
}

#else

/// Buildable fallback used only when the CFFF XCFramework is absent. It keeps
/// app code independent of build ordering while failing every native operation
/// with a precise integration error.
actor FFFSearchEngine {
    nonisolated let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    func prepare() async throws {
        throw FFFSearchError.libraryUnavailable
    }

    func start() throws {
        throw FFFSearchError.libraryUnavailable
    }

    func waitForInitialScan() async throws {
        throw FFFSearchError.libraryUnavailable
    }

    func searchFiles(query: String, limit: Int = 100) async throws -> [FFFFileSearchHit] {
        try FFFSearchInputValidator.validate(query: query)
        _ = try FFFSearchInputValidator.checkedLimit(limit)
        throw FFFSearchError.libraryUnavailable
    }

    func searchFilesPage(
        query: String,
        limit: Int = 100,
        pageIndex: Int = 0
    ) async throws -> FFFFileSearchPage {
        try FFFSearchInputValidator.validate(query: query)
        _ = try FFFSearchInputValidator.checkedLimit(limit)
        _ = try FFFSearchInputValidator.checkedPageIndex(pageIndex)
        throw FFFSearchError.libraryUnavailable
    }

    func searchDirectories(
        query: String,
        limit: Int = 100
    ) async throws -> [FFFDirectorySearchHit] {
        try FFFSearchInputValidator.validate(query: query)
        _ = try FFFSearchInputValidator.checkedLimit(limit)
        throw FFFSearchError.libraryUnavailable
    }

    func searchContent(
        query: String,
        mode _: FFFContentSearchMode = .plain,
        limit: Int = 50,
        timeBudgetMilliseconds: Int = 150
    ) async throws -> [FFFContentSearchHit] {
        try FFFSearchInputValidator.validate(query: query)
        _ = try FFFSearchInputValidator.checkedLimit(limit)
        _ = try FFFSearchInputValidator.checkedTimeBudget(timeBudgetMilliseconds)
        throw FFFSearchError.libraryUnavailable
    }

    func searchContentPage(
        query: String,
        mode _: FFFContentSearchMode = .plain,
        limit: Int = 50,
        timeBudgetMilliseconds: Int = 150,
        fileOffset: Int = 0
    ) async throws -> FFFContentSearchPage {
        try FFFSearchInputValidator.validate(query: query)
        _ = try FFFSearchInputValidator.checkedLimit(limit)
        _ = try FFFSearchInputValidator.checkedTimeBudget(timeBudgetMilliseconds)
        _ = try FFFSearchInputValidator.checkedPageIndex(fileOffset)
        throw FFFSearchError.libraryUnavailable
    }

    func scanProgress() async throws -> FFFScanProgress {
        throw FFFSearchError.libraryUnavailable
    }

    func rescan() async throws {
        throw FFFSearchError.libraryUnavailable
    }

    func shutdown() async {}
}

#endif
