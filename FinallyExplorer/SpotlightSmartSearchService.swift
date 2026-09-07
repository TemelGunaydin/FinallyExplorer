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
    private let captureDateReader: @Sendable (URL) -> PhotoCaptureDate?

    init(
        timeout: Duration = .seconds(5),
        captureDateReader: @escaping @Sendable (URL) -> PhotoCaptureDate? = { PhotoCaptureDate.read(from: $0) },
        query: @escaping Query = { root, plan in
            try await SpotlightGlobalSearchService().search(rootURL: root, plan: plan)
        }
    ) {
        self.timeout = timeout
        self.query = query
        self.captureDateReader = captureDateReader
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
        var skippedCaptureDates = 0
        let results = try page.hits.compactMap { hit -> ExplorerSearchResult? in
            try Task.checkCancellation()
            let url = hit.url.standardizedFileURL
            let path = SmartSearchPlan.normalizedPath(url)
            let resolvedURL = url.deletingLastPathComponent().resolvingSymlinksInPath()
                .appending(path: url.lastPathComponent).resolvingSymlinksInPath()
            let resolvedPath = SmartSearchPlan.normalizedPath(resolvedURL)
            let rootPath = SmartSearchPlan.normalizedPath(root)
            guard FFFSearchValueMapper.isLocalFileURL(url),
                  rootPath == "/" || path.hasPrefix(rootPath + "/"),
                  rootPath == "/" || resolvedPath.hasPrefix(rootPath + "/"),
                  url.pathComponents.contains(where: { $0.hasPrefix(".") }) == false,
                  resolvedURL.pathComponents.contains(where: { $0.hasPrefix(".") }) == false,
                  seen.insert(url).inserted else { return nil }
            var captureDate: PhotoCaptureDate?
            if plan.dateField == .captured, let interval = plan.dateInterval {
                guard hit.isImage, let captured = captureDateReader(resolvedURL) else {
                    skippedCaptureDates += 1
                    return nil
                }
                guard captured.date >= interval.start, captured.date < interval.end else { return nil }
                captureDate = captured
            }
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
                contentMatch: nil,
                captureDate: captureDate
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
        var notices: [String] = []
        if page.isTruncated || results.count > 120 {
            notices.append("Results are limited to indexed candidates and up to 120 matches. Refine your description to narrow the results.")
        }
        if plan.dateField == .captured, plan.dateInterval != nil {
            notices.append("Capture dates are verified from original EXIF metadata in local images. Candidates depend on Spotlight’s recorded content date. Photos-library items and unindexed images are not included.")
            if skippedCaptureDates > 0 {
                notices.append(skippedCaptureDates == 1
                    ? "1 candidate could not be verified and was skipped."
                    : "\(skippedCaptureDates) candidates could not be verified and were skipped.")
            }
            if results.contains(where: { $0.captureDate?.assumedLocalTimeZone == true }) {
                notices.append("Your Mac’s time zone is used when the camera recorded no offset.")
            }
        }
        return GlobalSearchPage(results: Array(sorted.prefix(120)), message: notices.isEmpty ? nil : .notice(notices.joined(separator: " ")))
    }
}
