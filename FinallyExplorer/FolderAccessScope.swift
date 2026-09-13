import Foundation

nonisolated struct ResolvedFolderAccessBookmark: Sendable {
    let url: URL
    let isStale: Bool
}

@MainActor
protocol FolderAccessAuthorizing {
    func makeBookmark(for url: URL) throws -> Data
    func resolve(_ data: Data) throws -> ResolvedFolderAccessBookmark
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
    func validateFolder(_ url: URL) throws
    func isLocationDefinitelyMissing(_ url: URL) -> Bool
}

@MainActor
struct LocalFolderAccessAuthorizer: FolderAccessAuthorizing {
    func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func resolve(_ data: Data) throws -> ResolvedFolderAccessBookmark {
        var isStale = false
        let url = try URL(resolvingBookmarkData: data,
                          options: [.withSecurityScope, .withoutUI, .withoutMounting],
                          relativeTo: nil, bookmarkDataIsStale: &isStale)
        return ResolvedFolderAccessBookmark(url: url, isStale: isStale)
    }

    func startAccessing(_ url: URL) -> Bool { url.startAccessingSecurityScopedResource() }
    func stopAccessing(_ url: URL) { url.stopAccessingSecurityScopedResource() }

    func validateFolder(_ url: URL) throws {
        guard FolderAccessBookmark.isLocalURL(url) else { throw FolderAccessError.invalidFolder }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw FolderAccessError.invalidFolder }
        // A false startAccessing result also occurs for already accessible locations.
        // Never use it alone to report permission denial, or to skip a real read check.
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw FolderAccessError.unavailable }
    }

    func isLocationDefinitelyMissing(_ url: URL) -> Bool {
        do {
            _ = try url.resourceValues(forKeys: [.isDirectoryKey])
            return false
        } catch let error as CocoaError {
            return error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile
        } catch {
            // Denial or another ambiguous failure is not proof
            // that an old path is safe to redirect to a different location.
            return false
        }
    }
}

/// One balanced explicit scope, shared for the application session. Background file
/// operations in this process can keep using it even when a tool sheet is dismissed.
@MainActor
final class FolderAccessScope {
    let url: URL
    private let authorizer: any FolderAccessAuthorizing
    private let didStart: Bool

    init(url: URL, authorizer: any FolderAccessAuthorizing) {
        self.url = url
        self.authorizer = authorizer
        didStart = authorizer.startAccessing(url)
    }

    isolated deinit {
        if didStart { authorizer.stopAccessing(url) }
    }
}
