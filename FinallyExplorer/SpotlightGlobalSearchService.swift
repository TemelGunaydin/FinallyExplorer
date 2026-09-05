//
//  SpotlightGlobalSearchService.swift
//  FinallyExplorer
//

import Foundation
import UniformTypeIdentifiers

nonisolated protocol SpotlightGlobalSearchServicing: Sendable {
    func search(
        rootURL: URL,
        query: String,
        maximumCandidateCount: Int
    ) async throws -> SpotlightGlobalSearchService.Page
}

nonisolated enum SpotlightNamePredicateBuilder {
    static func predicate(for queryText: String) -> NSPredicate {
        let trimmedQuery = queryText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let tokens = trimmedQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        let compactQuery = tokens.joined()

        if trimmedQuery.count < 3 {
            return namePrefixPredicate(trimmedQuery)
        }

        var alternatives: [NSPredicate] = [
            nameLikePredicate(trimmedQuery)
        ]

        if tokens.count > 1 {
            alternatives.append(
                NSCompoundPredicate(
                    andPredicateWithSubpredicates: tokens.map(nameLikePredicate)
                )
            )
        }

        if compactQuery != trimmedQuery {
            alternatives.append(nameLikePredicate(compactQuery))
        }

        // NSMetadataQuery rejects an OR compound predicate containing only one
        // child with an Objective-C exception. Single-token queries therefore
        // need to use their leaf predicate directly.
        guard alternatives.count > 1 else {
            return alternatives[0]
        }

        // Character-by-character wildcards can make Spotlight gather a
        // huge whole-disk candidate set. Hybrid search keeps broad fuzzy
        // matching in its bounded FFF fallback instead.
        return NSCompoundPredicate(orPredicateWithSubpredicates: alternatives)
    }

    private static func nameLikePredicate(_ value: String) -> NSPredicate {
        NSPredicate(
            format: "%K LIKE[cd] %@",
            NSMetadataItemFSNameKey,
            "*\(escapedLikeValue(value))*"
        )
    }

    private static func namePrefixPredicate(_ value: String) -> NSPredicate {
        NSPredicate(
            format: "%K LIKE[cd] %@",
            NSMetadataItemFSNameKey,
            "\(escapedLikeValue(value))*"
        )
    }

    private static func escapedLikeValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "?", with: "\\?")
    }
}

/// Reads macOS's persistent, incrementally maintained Spotlight catalog for
/// global name searches. FinallyExplorer therefore does not need to rescan the
/// entire startup disk every time it launches.
nonisolated struct SpotlightGlobalSearchService:
    SpotlightGlobalSearchServicing,
    Sendable {
    nonisolated struct Hit: Hashable, Sendable {
        let url: URL
        let isDirectory: Bool
        let isImage: Bool
        let byteSize: UInt64?
        let modificationDate: Date?
    }

    nonisolated struct Page: Sendable {
        let hits: [Hit]
        let isTruncated: Bool
    }

    nonisolated enum SearchError: LocalizedError, Sendable {
        case unableToStart

        var errorDescription: String? {
            switch self {
            case .unableToStart:
                "Unable to query the Mac search index."
            }
        }
    }

    func search(
        rootURL: URL,
        query: String,
        maximumCandidateCount: Int = 800
    ) async throws -> Page {
        try await QuerySession.run(
            rootURL: rootURL,
            queryText: query,
            maximumCandidateCount: maximumCandidateCount
        )
    }

    func search(
        rootURL: URL,
        plan: SmartSearchPlan,
        maximumCandidateCount: Int = 800
    ) async throws -> Page {
        try await QuerySession.run(
            rootURL: rootURL,
            plan: plan,
            maximumCandidateCount: maximumCandidateCount
        )
    }

    private actor QuerySession {
        /// `NSMetadataQuery` is not `Sendable`, but after initialization its
        /// lifecycle and result APIs run only on `resultQueue`. The unchecked
        /// conformance describes that queue confinement rather than allowing
        /// unsynchronized calls from arbitrary executors.
        private nonisolated final class QueueBoundMetadataQuery:
            @unchecked Sendable {
            let value = NSMetadataQuery()
        }

        private nonisolated final class CancellationState:
            @unchecked Sendable {
            private let lock = NSLock()
            private var isCancelledStorage = false

            var isCancelled: Bool {
                lock.withLock { isCancelledStorage }
            }

            func cancel() {
                lock.withLock {
                    isCancelledStorage = true
                }
            }
        }

        private let queryHandle = QueueBoundMetadataQuery()
        private let cancellationState = CancellationState()
        private let resultQueue = OperationQueue()
        private let rootURL: URL
        private let maximumCandidateCount: Int
        private var gatheringContinuation: CheckedContinuation<Page, any Error>?
        private var gatheringObserver: NSObjectProtocol?
        private var isCancellationPending = false

        private init(
            rootURL: URL,
            queryText: String,
            maximumCandidateCount: Int,
            plan: SmartSearchPlan? = nil
        ) {
            self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
            self.maximumCandidateCount = max(1, maximumCandidateCount)

            resultQueue.name = "FinallyExplorer.SpotlightResults"
            resultQueue.maxConcurrentOperationCount = 1
            resultQueue.qualityOfService = .userInitiated

            let metadataQuery = queryHandle.value
            if let plan {
                metadataQuery.predicate = SmartSearchPredicateBuilder.predicate(for: plan)
            } else {
                metadataQuery.predicate = SpotlightNamePredicateBuilder.predicate(for: queryText)
            }
            metadataQuery.searchScopes = Self.searchScopes(for: self.rootURL)
            metadataQuery.sortDescriptors = [
                NSSortDescriptor(
                    key: NSMetadataQueryResultContentRelevanceAttribute,
                    ascending: false
                ),
                NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)
            ]
            metadataQuery.operationQueue = resultQueue
            metadataQuery.notificationBatchingInterval = 0
        }

        static func run(
            rootURL: URL,
            queryText: String,
            maximumCandidateCount: Int
        ) async throws -> Page {
            try FFFSearchInputValidator.validate(query: queryText)
            let normalizedQuery = queryText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard normalizedQuery.isEmpty == false else {
                throw FFFSearchError.invalidQuery(reason: "query is empty")
            }
            let session = QuerySession(
                rootURL: rootURL,
                queryText: normalizedQuery,
                maximumCandidateCount: maximumCandidateCount
            )
            return try await session.collect()
        }

        static func run(
            rootURL: URL,
            plan: SmartSearchPlan,
            maximumCandidateCount: Int
        ) async throws -> Page {
            try Task.checkCancellation()
            // Metadata conditions are applied by Spotlight BEFORE the candidate
            // limit, so a date match cannot be lost behind unrelated name hits.
            let session = QuerySession(
                rootURL: rootURL,
                queryText: "",
                maximumCandidateCount: maximumCandidateCount,
                plan: plan
            )
            return try await session.collect()
        }

        private func collect() async throws -> Page {
            try Task.checkCancellation()
            let page = try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Page, any Error>) in
                    guard Task.isCancelled == false else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    gatheringContinuation = continuation
                    let resultRootURL = rootURL
                    let resultLimit = maximumCandidateCount
                    let cancellationState = cancellationState
                    gatheringObserver = NotificationCenter.default.addObserver(
                        forName: .NSMetadataQueryDidFinishGathering,
                        object: queryHandle.value,
                        queue: resultQueue
                    ) { [weak self] notification in
                        guard let query = notification.object as? NSMetadataQuery else {
                            return
                        }
                        guard let page = Self.page(
                            from: query,
                            rootURL: resultRootURL,
                            maximumCandidateCount: resultLimit,
                            cancellationState: cancellationState
                        ) else { return }
                        Task {
                            await self?.finishGathering(with: page)
                        }
                    }

                    let queryHandle = queryHandle
                    resultQueue.addOperation { [weak self] in
                        guard queryHandle.value.start() == false else { return }
                        Task {
                            await self?.failToStart()
                        }
                    }
                }
            }, onCancel: { [weak self] in
                Task {
                    await self?.cancelGathering()
                }
            })
            try Task.checkCancellation()
            return page
        }

        private func finishGathering(with page: Page) {
            guard isCancellationPending == false,
                  let continuation = gatheringContinuation else {
                return
            }
            gatheringContinuation = nil
            isCancellationPending = false
            removeGatheringObserver()
            continuation.resume(returning: page)
        }

        private func failToStart() {
            guard isCancellationPending == false,
                  let continuation = gatheringContinuation else {
                return
            }
            gatheringContinuation = nil
            isCancellationPending = false
            removeGatheringObserver()
            continuation.resume(throwing: SearchError.unableToStart)
        }

        private func cancelGathering() {
            guard gatheringContinuation != nil,
                  isCancellationPending == false else {
                return
            }
            isCancellationPending = true
            cancellationState.cancel()
            removeGatheringObserver()
            let queryHandle = queryHandle
            resultQueue.addOperation { [weak self] in
                queryHandle.value.stop()
                Task {
                    await self?.finishCancellation()
                }
            }
        }

        private func finishCancellation() {
            guard let continuation = gatheringContinuation else { return }
            gatheringContinuation = nil
            isCancellationPending = false
            continuation.resume(throwing: CancellationError())
        }

        private func removeGatheringObserver() {
            guard let gatheringObserver else { return }
            NotificationCenter.default.removeObserver(gatheringObserver)
            self.gatheringObserver = nil
        }

        /// The SDK requires `start()` to run on `operationQueue`. Keeping all
        /// result access and teardown in the same callback also prevents the
        /// query from being read concurrently while it is still gathering.
        private nonisolated static func page(
            from query: NSMetadataQuery,
            rootURL: URL,
            maximumCandidateCount: Int,
            cancellationState: CancellationState
        ) -> Page? {
            query.disableUpdates()
            defer {
                query.enableUpdates()
                query.stop()
            }

            var hits: [Hit] = []
            let totalResultCount = query.resultCount
            let resultCount = min(totalResultCount, maximumCandidateCount)
            hits.reserveCapacity(resultCount)

            for index in 0..<resultCount {
                guard cancellationState.isCancelled == false else {
                    return nil
                }
                guard let item = query.result(at: index) as? NSMetadataItem,
                      let values = item.values(forAttributes: [
                          NSMetadataItemURLKey,
                          NSMetadataItemContentTypeTreeKey,
                          NSMetadataItemFSSizeKey,
                          NSMetadataItemContentModificationDateKey,
                      ]),
                      let url = values[NSMetadataItemURLKey] as? URL,
                      isInsideSearchRoot(url, rootURL: rootURL) else {
                    continue
                }

                let contentTypeTree = values[
                    NSMetadataItemContentTypeTreeKey
                ] as? [String] ?? []
                let isDirectory = contentTypeTree.contains(UTType.directory.identifier)
                let isImage = contentTypeTree.contains(UTType.image.identifier)
                let byteSize = (values[NSMetadataItemFSSizeKey] as? NSNumber)?
                    .uint64Value
                let modificationDate = values[
                    NSMetadataItemContentModificationDateKey
                ] as? Date

                hits.append(
                    Hit(
                        url: url.standardizedFileURL,
                        isDirectory: isDirectory,
                        isImage: isImage,
                        byteSize: isDirectory ? nil : byteSize,
                        modificationDate: modificationDate
                    )
                )
            }

            guard cancellationState.isCancelled == false else {
                return nil
            }

            return Page(
                hits: hits,
                isTruncated: resultCount < totalResultCount
            )
        }

        private static func searchScopes(for rootURL: URL) -> [Any] {
            if rootURL.path(percentEncoded: false) == "/" {
                return [NSMetadataQueryIndexedLocalComputerScope]
            }
            return [rootURL]
        }

        private static func isInsideSearchRoot(
            _ candidateURL: URL,
            rootURL: URL
        ) -> Bool {
            let rawRootPath = rootURL.standardizedFileURL.path(percentEncoded: false)
            let rootPath = rawRootPath != "/" && rawRootPath.hasSuffix("/")
                ? String(rawRootPath.dropLast()) : rawRootPath
            guard rootPath != "/" else { return true }

            let candidatePath = candidateURL.standardizedFileURL.path(
                percentEncoded: false
            )
            return candidatePath == rootPath
                || candidatePath.hasPrefix(rootPath + "/")
        }
    }
}
