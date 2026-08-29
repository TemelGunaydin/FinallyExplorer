//
//  FolderSizeCache.swift
//  FinallyExplorer
//

import Foundation

actor FolderSizeCache {
    static let shared = FolderSizeCache()

    private struct CacheEntry: Sendable {
        let size: Int64
        let recordedAt: Date
    }

    private struct InFlightRequest: Sendable {
        let id: UUID
        let task: Task<Int64, Error>
        var consumerCount: Int
    }

    private let maximumCachedAge: TimeInterval
    private let maximumCachedEntryCount: Int
    private let limiter: FolderSizeWorkLimiter
    private let loader: @Sendable (URL) async throws -> Int64

    private var cache: [URL: CacheEntry] = [:]
    private var inFlightRequests: [URL: InFlightRequest] = [:]

    init(
        maximumCachedAge: TimeInterval = 60,
        maximumCachedEntryCount: Int = 256,
        maximumConcurrentRequests: Int = 2,
        loader: @escaping @Sendable (URL) async throws -> Int64 = { url in
            try await FileSystemService().size(of: url)
        }
    ) {
        self.maximumCachedAge = maximumCachedAge
        self.maximumCachedEntryCount = max(1, maximumCachedEntryCount)
        self.limiter = FolderSizeWorkLimiter(
            maximumConcurrentRequests: maximumConcurrentRequests
        )
        self.loader = loader
    }

    func size(of directoryURL: URL) async throws -> Int64 {
        let directoryURL = directoryURL.resolvingSymlinksInPath().standardizedFileURL

        if let cached = cache[directoryURL],
           Date.now.timeIntervalSince(cached.recordedAt) < maximumCachedAge {
            return cached.size
        }

        let request: InFlightRequest
        if var existingRequest = inFlightRequests[directoryURL] {
            existingRequest.consumerCount += 1
            inFlightRequests[directoryURL] = existingRequest
            request = existingRequest
        } else {
            request = InFlightRequest(
                id: UUID(),
                task: Task { [limiter, loader] in
                    try await limiter.perform {
                        try await loader(directoryURL)
                    }
                },
                consumerCount: 1
            )
            inFlightRequests[directoryURL] = request
        }

        do {
            let size = try await awaitResult(
                of: request,
                for: directoryURL
            )

            if inFlightRequests[directoryURL]?.id == request.id {
                store(size: size, for: directoryURL)
                inFlightRequests[directoryURL] = nil
            }

            return size
        } catch {
            // A cancelled view must not tear down work that another visible
            // row is still awaiting. Shared-task failures, on the other hand,
            // must be removed so a later request can retry.
            if Task.isCancelled == false,
               inFlightRequests[directoryURL]?.id == request.id {
                inFlightRequests[directoryURL] = nil
            }
            throw error
        }
    }

    func invalidate(_ directoryURL: URL) {
        let directoryURL = directoryURL.resolvingSymlinksInPath().standardizedFileURL
        cache[directoryURL] = nil

        if let inFlightRequest = inFlightRequests.removeValue(forKey: directoryURL) {
            inFlightRequest.task.cancel()
        }
    }

    func invalidate(_ directoryURLs: Set<URL>) {
        for directoryURL in directoryURLs {
            invalidate(directoryURL)
        }
    }

    /// Invalidates cached recursive sizes for folders that contain a changed
    /// directory. A folder's total includes every descendant, so clearing only
    /// the direct source and destination would leave cached parent sizes stale.
    func invalidateRecursively(affectedBy directoryURLs: Set<URL>) {
        let changedDirectories = directoryURLs.map {
            $0.resolvingSymlinksInPath().standardizedFileURL
        }
        guard changedDirectories.isEmpty == false else { return }

        let candidateURLs = Set(cache.keys).union(inFlightRequests.keys)
        let invalidatedURLs = candidateURLs.filter { candidateURL in
            changedDirectories.contains {
                Self.isSameOrAncestor(candidateURL, of: $0)
            }
        }

        for directoryURL in invalidatedURLs {
            invalidate(directoryURL)
        }
    }

    private func awaitResult(
        of request: InFlightRequest,
        for directoryURL: URL
    ) async throws -> Int64 {
        let size = try await withTaskCancellationHandler {
            try await request.task.value
        } onCancel: {
            Task {
                await self.cancelConsumer(
                    for: directoryURL,
                    requestID: request.id
                )
            }
        }

        try Task.checkCancellation()
        return size
    }

    private func cancelConsumer(for directoryURL: URL, requestID: UUID) {
        guard var request = inFlightRequests[directoryURL],
              request.id == requestID else {
            return
        }

        if request.consumerCount > 1 {
            request.consumerCount -= 1
            inFlightRequests[directoryURL] = request
        } else {
            inFlightRequests[directoryURL] = nil
            request.task.cancel()
        }
    }

    private func store(size: Int64, for directoryURL: URL) {
        let now = Date.now
        cache = cache.filter {
            now.timeIntervalSince($0.value.recordedAt) < maximumCachedAge
        }

        if cache[directoryURL] == nil,
           cache.count >= maximumCachedEntryCount,
           let oldestURL = cache.min(by: {
               $0.value.recordedAt < $1.value.recordedAt
           })?.key {
            cache[oldestURL] = nil
        }

        cache[directoryURL] = CacheEntry(size: size, recordedAt: now)
    }

    private nonisolated static func isSameOrAncestor(
        _ ancestor: URL,
        of descendant: URL
    ) -> Bool {
        let ancestorPath = normalizedPath(of: ancestor)
        let descendantPath = normalizedPath(of: descendant)

        if ancestorPath == "/" {
            return descendantPath.hasPrefix("/")
        }

        return descendantPath == ancestorPath
            || descendantPath.hasPrefix(ancestorPath + "/")
    }

    private nonisolated static func normalizedPath(of url: URL) -> String {
        var path = url.path(percentEncoded: false)

        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }

        return path
    }
}

private actor FolderSizeWorkLimiter {
    private let maximumConcurrentRequests: Int
    private var availablePermits: Int

    init(maximumConcurrentRequests: Int) {
        let maximumConcurrentRequests = max(1, maximumConcurrentRequests)
        self.maximumConcurrentRequests = maximumConcurrentRequests
        availablePermits = maximumConcurrentRequests
    }

    func perform(
        _ operation: @escaping @Sendable () async throws -> Int64
    ) async throws -> Int64 {
        try await acquirePermit()
        defer { releasePermit() }

        try Task.checkCancellation()
        let result = try await operation()
        try Task.checkCancellation()
        return result
    }

    private func acquirePermit() async throws {
        while availablePermits == 0 {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(20))
        }

        try Task.checkCancellation()
        availablePermits -= 1
    }

    private func releasePermit() {
        availablePermits = min(
            availablePermits + 1,
            maximumConcurrentRequests
        )
    }
}
