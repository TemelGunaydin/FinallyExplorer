import Foundation

/// The original location is retained even after a bookmark follows a renamed folder.
/// This lets older sidebar favorites be rebased on every launch, including after a crash.
nonisolated struct FolderAccessBookmark: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let originalURL: URL
    var data: Data
    var knownURLs: [URL]? = nil

    var knownLocations: [URL] { [originalURL] + (knownURLs ?? []) }

    mutating func rememberLocation(_ url: URL) {
        guard knownLocations.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) == false else { return }
        knownURLs = (knownURLs ?? []) + [url]
    }
}

@MainActor
protocol FolderAccessBookmarkStoring {
    func load() throws -> [FolderAccessBookmark]
    func save(_ bookmarks: [FolderAccessBookmark]) throws
}

@MainActor
struct UserDefaultsFolderAccessBookmarkStore: FolderAccessBookmarkStoring {
    static let key = "folder-access-bookmarks-v1"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() throws -> [FolderAccessBookmark] {
        guard let storedValue = defaults.object(forKey: Self.key) else { return [] }
        guard let data = storedValue as? Data else { throw FolderAccessError.invalidStore }
        let bookmarks = try JSONDecoder().decode([FolderAccessBookmark].self, from: data)
        guard Set(bookmarks.map(\.id)).count == bookmarks.count,
              bookmarks.allSatisfy({ $0.knownLocations.allSatisfy(FolderAccessBookmark.isLocalURL) && $0.data.isEmpty == false }) else {
            throw FolderAccessError.invalidStore
        }
        return bookmarks
    }

    func save(_ bookmarks: [FolderAccessBookmark]) throws {
        defaults.set(try JSONEncoder().encode(bookmarks), forKey: Self.key)
    }
}

extension FolderAccessBookmark {
    nonisolated static func isLocalURL(_ url: URL) -> Bool {
        url.isFileURL && (url.host == nil || url.host == "" || url.host == "localhost")
    }
}

/// Used by previews and dependency-injected views, never as the app's production store.
@MainActor
final class MemoryFolderAccessBookmarkStore: FolderAccessBookmarkStoring {
    var bookmarks: [FolderAccessBookmark] = []
    func load() throws -> [FolderAccessBookmark] { bookmarks }
    func save(_ bookmarks: [FolderAccessBookmark]) throws { self.bookmarks = bookmarks }
}

nonisolated enum FolderAccessError: LocalizedError {
    case invalidFolder
    case unavailable
    case invalidStore

    var errorDescription: String? {
        switch self {
        case .invalidFolder: "Choose a local folder, not a file."
        case .unavailable: "This folder is unavailable. Reconnect its disk or choose the folder again. macOS privacy and file permissions still apply."
        case .invalidStore: "Saved folder access could not be read. Existing records have not been replaced."
        }
    }
}
