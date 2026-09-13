import Foundation

/// A short-lived, shareable access lease. Keep it with a selection and capture it
/// in every task using that selection, so cancellation cannot close access while
/// an underlying file read is still unwinding. No paths or bookmarks are saved.
nonisolated final class SecurityScopedResourceAccess: Sendable {
    private let urls: [URL]
    private let stop: @Sendable (URL) -> Void

    /// Open panels already start access. Adopting their result must not add an
    /// unmatched extra start; even rejected selections need a matching release.
    init(adoptingPanelURLs urls: [URL], stop: @escaping @Sendable (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }) {
        self.urls = urls.filter(FolderAccessBookmark.isLocalURL)
        self.stop = stop
    }

    /// For explicitly scoped URLs supplied by another access owner. A false
    /// start is not an authorization decision: the actual operation still checks
    /// filesystem permissions, and only successful starts are balanced here.
    init(starting urls: [URL],
         start: @Sendable (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
         stop: @escaping @Sendable (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }) {
        var seen: Set<URL> = []
        self.urls = urls.filter { url in
            FolderAccessBookmark.isLocalURL(url) && seen.insert(url.standardizedFileURL).inserted && start(url)
        }
        self.stop = stop
    }

    deinit { for url in urls { stop(url) } }
}
