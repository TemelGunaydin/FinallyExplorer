import Foundation

nonisolated protocol SmartSearchExecuting: Sendable {
    func search(rootURL: URL, plan: SmartSearchPlan) async throws -> GlobalSearchPage
}

/// Smart Search uses the existing persistent Mac catalog. It never starts a new
/// disk scan, and never passes an AI-generated expression to FFF/grep or a shell.
nonisolated struct SpotlightSmartSearchService: SmartSearchExecuting {
    typealias Query = @Sendable (URL, SmartSearchPlan) async throws -> SpotlightGlobalSearchService.Page
    private let query: Query
    private let timeout: Duration

    init(
        timeout: Duration = .seconds(5),
        query: @escaping Query = { root, plan in
            try await SpotlightGlobalSearchService().search(rootURL: root, plan: plan)
        }
    ) {
        self.timeout = timeout
        self.query = query
    }

    @concurrent
    func search(rootURL: URL, plan: SmartSearchPlan) async throws -> GlobalSearchPage {
        let root = try plan.searchRoot(in: rootURL)
        try Task.checkCancellation()
        let page = try await withThrowingTaskGroup(of: SpotlightGlobalSearchService.Page.self) { group in
            group.addTask { try await query(root, plan) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw SmartSearchError.timedOut
            }
            defer { group.cancelAll() }
            guard let page = try await group.next() else { throw CancellationError() }
            return page
        }
        try Task.checkCancellation()

        var seen = Set<URL>()
        let results = page.hits.compactMap { hit -> ExplorerSearchResult? in
            let url = hit.url.standardizedFileURL
            let path = SmartSearchPlan.normalizedPath(url)
            let rootPath = SmartSearchPlan.normalizedPath(root)
            guard FFFSearchValueMapper.isLocalFileURL(url),
                  rootPath == "/" || path.hasPrefix(rootPath + "/"),
                  url.pathComponents.contains(where: { $0.hasPrefix(".") }) == false,
                  seen.insert(url).inserted else { return nil }
            return ExplorerSearchResult(
                id: "global-smart:\(path)",
                item: FileItem(
                    url: url,
                    isDirectory: hit.isDirectory,
                    isImage: hit.isImage,
                    fileSize: hit.byteSize.map { Int64(clamping: $0) },
                    modificationDate: hit.modificationDate
                ),
                relativePath: rootPath == "/" ? String(path.dropFirst()) : String(path.dropFirst(rootPath.count + 1)),
                contentMatch: nil
            )
        }
        // Do not require a filename match: a relevant document may have matched
        // only its indexed content (e.g. an accounting report named scan.pdf).
        let sorted = results.sorted { lhs, rhs in
            let leftNameMatch = plan.keywords.allSatisfy { lhs.item.name.localizedStandardContains($0) }
            let rightNameMatch = plan.keywords.allSatisfy { rhs.item.name.localizedStandardContains($0) }
            if leftNameMatch != rightNameMatch { return leftNameMatch }
            if lhs.item.modificationDate != rhs.item.modificationDate {
                return (lhs.item.modificationDate ?? .distantPast) > (rhs.item.modificationDate ?? .distantPast)
            }
            return lhs.item.name.localizedStandardCompare(rhs.item.name) == .orderedAscending
        }
        return GlobalSearchPage(
            results: Array(sorted.prefix(120)),
            message: page.isTruncated || results.count > 120
                ? .notice("Showing up to 120 matches. Refine your description to narrow the results.")
                : nil
        )
    }
}
