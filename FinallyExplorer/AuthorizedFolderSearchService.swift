import Foundation

/// Searches explicitly authorized roots directly. A bookmark for a descendant
/// does not authorize walking its parents from `/` to discover that descendant.
/// No new permission is requested here; FolderAccessModel owns the live scopes.
actor AuthorizedFolderSearchService: GlobalSearchServicing {
    typealias RootsProvider = @Sendable () async -> [URL]
    typealias ServiceFactory = @Sendable (URL) -> any GlobalSearchServicing

    private let rootsProvider: RootsProvider
    private let serviceFactory: ServiceFactory
    private var services: [URL: any GlobalSearchServicing] = [:]
    private var warmingRoots = Set<URL>()
    private var generation = 0
    private var searchGeneration = 0

    init(roots: @escaping RootsProvider,
         serviceFactory: @escaping ServiceFactory = { _ in HybridGlobalSearchService() }) {
        rootsProvider = roots
        self.serviceFactory = serviceFactory
    }

    func prepare(rootURL: URL) async throws {
        // Do not create native indexes or scan at app startup.
        try Task.checkCancellation()
    }

    func search(rootURL: URL, query: String, scope: ExplorerSearchScope,
                contentMode: FFFContentSearchMode) async throws -> GlobalSearchPage {
        searchGeneration += 1
        let request = searchGeneration
        let roots = try await synchronizeRoots()
        let lifetime = generation
        let jobs = roots.compactMap { root in services[root].map { (root, $0) } }
        let pages = try await Self.run(jobs) { root, service in
            try await service.search(rootURL: root, query: query, scope: scope, contentMode: contentMode)
        }
        try validate(lifetime)
        guard request == searchGeneration else { throw CancellationError() }
        warmingRoots = Set(pages.filter { $0.1.isIndexWarming }.map(\.0))
        guard roots.isEmpty == false else {
            return GlobalSearchPage(results: [], message: .notice(
                "Choose a folder in File Access settings to include it in search."
            ))
        }
        return Self.merged(pages.map(\.1), query: query, scope: scope)
    }

    func waitForInitialScan(rootURL: URL) async throws {
        let lifetime = generation
        let jobs = warmingRoots.compactMap { root in services[root].map { (root, $0) } }
        // Refresh as soon as ANY root is ready. A large Downloads folder must
        // not delay results from a small newly granted folder.
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (root, service) in jobs {
                group.addTask { try await service.waitForInitialScan(rootURL: root) }
            }
            defer { group.cancelAll() }
            _ = try await group.next()
        }
        try validate(lifetime)
    }

    func rebuildContentIndex(rootURL: URL) async throws {
        let roots = try await synchronizeRoots()
        let lifetime = generation
        let jobs = roots.compactMap { root in services[root].map { (root, $0) } }
        // Rebuild is explicit, unlike normal launch or query changes.
        _ = try await Self.run(jobs, recoversErrors: false) { root, service in
            try await service.rebuildContentIndex(rootURL: root)
            return GlobalSearchPage(results: [], message: nil)
        }
        try validate(lifetime)
    }

    func fileAccessDidChange(rootURL: URL) async throws {
        generation += 1
        searchGeneration += 1
        warmingRoots.removeAll()
        // Reconcile without creating indexes. Existing root services refresh
        // their pooled indexes; a newly authorized root starts on first query.
        let roots = try await synchronizeRoots(createServices: false)
        let lifetime = generation
        for root in roots {
            if let service = services[root] {
                try await service.fileAccessDidChange(rootURL: root)
                try validate(lifetime)
            }
        }
    }

    func shutdown() async {
        generation += 1
        searchGeneration += 1
        let oldServices = Array(services.values)
        services.removeAll()
        warmingRoots.removeAll()
        for service in oldServices { await service.shutdown() }
    }

    private func synchronizeRoots(createServices: Bool = true) async throws -> [URL] {
        let lifetime = generation
        let roots = Self.normalizedRoots(await rootsProvider())
        try validate(lifetime)
        let removed = services.keys.filter { roots.contains($0) == false }
        let retired = removed.compactMap { services.removeValue(forKey: $0) }
        if removed.isEmpty == false { generation += 1 }
        let updatedLifetime = generation
        warmingRoots.subtract(removed)
        if createServices {
            for root in roots where services[root] == nil { services[root] = serviceFactory(root) }
        }
        for service in retired { await service.shutdown() }
        try validate(updatedLifetime)
        return roots
    }

    private func validate(_ lifetime: Int) throws {
        try Task.checkCancellation()
        guard lifetime == generation else { throw CancellationError() }
    }

    nonisolated static func normalizedRoots(_ urls: [URL]) -> [URL] {
        let roots = Set(urls.filter { FFFSearchValueMapper.isLocalFileURL($0) }
            .map { $0.standardizedFileURL.resolvingSymlinksInPath() })
            .sorted { $0.path < $1.path }
        return roots.filter { candidate in
            roots.contains { parent in
                parent != candidate && candidate.pathComponents.starts(with: parent.pathComponents)
            } == false
        }
    }

    /// Bounded fan-out; cancellation never turns into a user-facing partial error.
    private nonisolated static func run(
        _ jobs: [(URL, any GlobalSearchServicing)],
        recoversErrors: Bool = true,
        operation: @escaping @Sendable (URL, any GlobalSearchServicing) async throws -> GlobalSearchPage
    ) async throws -> [(URL, GlobalSearchPage)] {
        try await withThrowingTaskGroup(of: (URL, GlobalSearchPage).self) { group in
            var iterator = jobs.makeIterator()
            func enqueue(_ job: (URL, any GlobalSearchServicing)) {
                group.addTask {
                    do { return (job.0, try await operation(job.0, job.1)) }
                    catch is CancellationError { throw CancellationError() }
                    catch {
                        try Task.checkCancellation()
                        guard recoversErrors else { throw error }
                        return (job.0, GlobalSearchPage(results: [], message: .error(
                            "Couldn’t search \(job.0.lastPathComponent). \(error.localizedDescription)"
                        )))
                    }
                }
            }
            for _ in 0..<4 { if let job = iterator.next() { enqueue(job) } }
            var pages: [(URL, GlobalSearchPage)] = []
            while let page = try await group.next() {
                try Task.checkCancellation()
                pages.append(page)
                if let job = iterator.next() { enqueue(job) }
            }
            return pages.sorted { $0.0.path < $1.0.path }
        }
    }

    nonisolated static func merged(_ pages: [GlobalSearchPage], query: String,
                                   scope: ExplorerSearchScope) -> GlobalSearchPage {
        var seen = Set<String>()
        var results: [ExplorerSearchResult] = []
        for result in pages.flatMap(\.results) {
            let path = result.item.url.standardizedFileURL.path
            let suffix = result.contentMatch.map { ":\($0.lineNumber):\($0.column)" } ?? ""
            let id = "global-\(scope.rawValue):\(path)\(suffix)"
            guard seen.insert(id).inserted else { continue }
            results.append(ExplorerSearchResult(
                id: id, item: result.item, relativePath: String(path.dropFirst()),
                contentMatch: result.contentMatch, captureDate: result.captureDate
            ))
        }
        if scope == .names {
            results.sort { lhs, rhs in
                let left = SearchTextMatch.match(in: lhs.item.name, matching: query)?.quality
                let right = SearchTextMatch.match(in: rhs.item.name, matching: query)?.quality
                if left != right {
                    if let left, let right { return left < right }
                    return left != nil
                }
                if lhs.item.isDirectory != rhs.item.isDirectory { return lhs.item.isDirectory }
                return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
            }
        }
        var notices = Array(Set(pages.compactMap { $0.message?.text })).sorted()
        if results.count > 120 { notices.append("Showing the closest matches. Refine the search to see more.") }
        let text = notices.joined(separator: " ")
        let hasError = pages.contains { $0.message?.isError == true }
        return GlobalSearchPage(
            results: Array(results.prefix(120)),
            message: notices.isEmpty ? nil : hasError ? .error(text) : .notice(text),
            isIndexWarming: pages.contains { $0.isIndexWarming }
        )
    }
}
