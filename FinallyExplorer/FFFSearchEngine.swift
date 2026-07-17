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
    case invalidTimeBudget(Int)
    case operationFailed(operation: String, message: String)
    case invalidPayload(operation: String, field: String)

    var errorDescription: String? {
        switch self {
        case .libraryUnavailable:
            "The FFF search library is not linked to the application."
        case let .invalidRootURL(url):
            "FFF requires an existing local folder.\n\nPath: \(url.path(percentEncoded: false))"
        case .notPrepared:
            "The FFF search engine has not been prepared yet."
        case let .invalidQuery(reason):
            "Search query is invalid: \(reason)"
        case let .invalidLimit(limit):
            "Search result limit must be between 1 and \(FFFSearchInputValidator.maximumResultLimit) (received \(limit))."
        case let .invalidTimeBudget(milliseconds):
            "Search time budget must be between 0 and \(FFFSearchInputValidator.maximumTimeBudgetMilliseconds) ms (received \(milliseconds) ms)."
        case let .operationFailed(operation, message):
            "FFF could not \(operation): \(message)"
        case let .invalidPayload(operation, field):
            "FFF returned an invalid \(field) while attempting to \(operation)."
        }
    }
}

/// Bounds values before they cross the C boundary. Apart from preventing
/// integer truncation, these limits keep a malformed caller from asking the
/// native engine to retain billions of hits or monopolize its serial executor.
nonisolated enum FFFSearchInputValidator {
    static let maximumQueryUTF8ByteCount = 4_096
    static let maximumResultLimit = 10_000
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

    /// Creates the FFF instance and waits for its automatically-started initial scan.
    /// Repeated calls are idempotent.
    func prepare() async throws {
        if handleOwner != nil { return }

        try Task.checkCancellation()
        try validateRootURL()

        let owner = try createHandle()
        handleOwner = owner

        do {
            try waitUntilScanFinishes(handle: owner.rawValue)
            try Task.checkCancellation()
        } catch {
            // A cancelled or failed prepare is transactional: the partially
            // prepared instance and its background scan are torn down.
            handleOwner = nil
            throw error
        }
    }

    func searchFiles(query: String, limit: Int = 100) async throws -> [FFFFileSearchHit] {
        try FFFSearchInputValidator.validate(query: query)
        let pageSize = try FFFSearchInputValidator.checkedLimit(limit)
        let handle = try preparedHandle()
        try Task.checkCancellation()

        let envelope = query.withCString { queryPointer in
            fff_search(
                handle,
                queryPointer,
                nil,
                0,
                0,
                pageSize,
                0,
                0
            )
        }

        let hits = try consumePayload(
            envelope,
            operation: "search files",
            as: FffSearchResult.self,
            freePayload: fff_free_search_result
        ) { result in
            try copyFileHits(from: result)
        }

        try Task.checkCancellation()
        return hits
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
        try FFFSearchInputValidator.validate(query: query)
        let pageSize = try FFFSearchInputValidator.checkedLimit(limit)
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
                0,
                pageSize,
                timeBudget,
                1,
                1,
                true
            )
        }

        let hits = try consumePayload(
            envelope,
            operation: "search file contents",
            as: FffGrepResult.self,
            freePayload: fff_free_grep_result
        ) { result in
            try copyContentHits(from: result)
        }

        try Task.checkCancellation()
        return hits
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
        let handle = try preparedHandle()
        try Task.checkCancellation()

        try consumeEmptyResult(
            fff_scan_files(handle),
            operation: "start a rescan"
        )
        try waitUntilScanFinishes(handle: handle)
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
        options.enable_fs_root_scanning = false
        options.enable_home_dir_scanning = false
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
        guard let handleOwner else {
            throw FFFSearchError.notPrepared
        }
        return handleOwner.rawValue
    }

    private func waitUntilScanFinishes(handle: UnsafeMutableRawPointer) throws {
        while true {
            try Task.checkCancellation()

            let completed = try consumeIntegerResult(
                fff_wait_for_scan(handle, 100),
                operation: "wait for the file index"
            ) != 0

            if completed { return }
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

    func searchFiles(query: String, limit: Int = 100) async throws -> [FFFFileSearchHit] {
        try FFFSearchInputValidator.validate(query: query)
        _ = try FFFSearchInputValidator.checkedLimit(limit)
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

    func scanProgress() async throws -> FFFScanProgress {
        throw FFFSearchError.libraryUnavailable
    }

    func rescan() async throws {
        throw FFFSearchError.libraryUnavailable
    }

    func shutdown() async {}
}

#endif
