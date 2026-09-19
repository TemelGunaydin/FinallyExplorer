import Foundation
import Observation

nonisolated struct RememberedFolderAccess: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let isAvailable: Bool
}

@MainActor @Observable
final class FolderAccessModel {
    private(set) var folders: [RememberedFolderAccess] = []
    private(set) var revision = 0
    private(set) var storageError: String?
    private(set) var forgottenForNextLaunch = false
    @ObservationIgnored private(set) var relocations: [FileRenameResult] = []
    @ObservationIgnored private let store: any FolderAccessBookmarkStoring
    @ObservationIgnored private let authorizer: any FolderAccessAuthorizing
    @ObservationIgnored private var bookmarks: [FolderAccessBookmark] = []
    @ObservationIgnored private var scopes: [URL: FolderAccessScope] = [:]
    @ObservationIgnored private var storeIsReadable = true

    var recoverableRelocations: [FileRenameResult] {
        relocations.filter { relocation in
            folders.contains(where: { $0.url.standardizedFileURL == relocation.sourceURL }) == false
                && authorizer.isLocationDefinitelyMissing(relocation.sourceURL)
        }
    }

    init(store: (any FolderAccessBookmarkStoring)? = nil,
         authorizer: (any FolderAccessAuthorizing)? = nil) {
        let store = store ?? UserDefaultsFolderAccessBookmarkStore()
        self.store = store
        self.authorizer = authorizer ?? LocalFolderAccessAuthorizer()
        do {
            bookmarks = try store.load()
            restoreUnavailableFolders()
        } catch {
            storeIsReadable = false
            storageError = FolderAccessError.invalidStore.localizedDescription
        }
    }

    /// Called before the workspace starts. Resolution never prompts or mounts a disk.
    /// Unavailable records stay in storage; unplugging a disk must not erase access.
    func restoreUnavailableFolders() {
        guard storeIsReadable else { return }
        let availableIDs = Set(folders.filter(\.isAvailable).map(\.id))
        var updated = bookmarks
        var restored = folders
        var didRestore = false

        for (index, bookmark) in bookmarks.enumerated() where availableIDs.contains(bookmark.id) == false {
            do {
                let resolution = try authorizer.resolve(bookmark.data)
                let scope = try acquire(resolution.url)
                scopes[scope.url.standardizedFileURL] = scope
                updated[index].rememberLocation(scope.url)
                if resolution.isStale {
                    // Keep the working session even if refreshing a stale bookmark fails.
                    do { updated[index].data = try authorizer.makeBookmark(for: scope.url) }
                    catch { storageError = "Folder access works for this session, but could not be updated for the next launch. Choose the folder again." }
                }
                recordRelocations(for: bookmark, to: scope.url)
                restored.removeAll { $0.id == bookmark.id }
                restored.append(RememberedFolderAccess(id: bookmark.id, url: scope.url, isAvailable: true))
                didRestore = true
            } catch {
                if restored.contains(where: { $0.id == bookmark.id }) == false {
                    restored.append(RememberedFolderAccess(id: bookmark.id, url: bookmark.knownLocations.last ?? bookmark.originalURL, isAvailable: false))
                }
            }
        }
        folders = bookmarks.compactMap { bookmark in restored.first { $0.id == bookmark.id } }
        if updated != bookmarks {
            do { try store.save(updated); bookmarks = updated }
            catch { storageError = "Folder access works for this session, but its updated bookmark could not be saved." }
        }
        if didRestore { revision += 1 }
    }

    /// Only call for an explicit user-approved selection, never for an inferred parent.
    /// The caller owns any implicit NSOpenPanel access and must balance that separately.
    @discardableResult
    func rememberAuthorizedFolder(_ url: URL) throws -> URL {
        guard storeIsReadable else { throw FolderAccessError.invalidStore }
        guard FolderAccessBookmark.isLocalURL(url) else { throw FolderAccessError.invalidFolder }
        try authorizer.validateFolder(url)
        let data = try authorizer.makeBookmark(for: url)
        let resolution = try authorizer.resolve(data)
        let scope = try acquire(resolution.url)
        let existingID = folders.first { $0.url.standardizedFileURL == scope.url.standardizedFileURL }?.id
        let id = existingID ?? UUID()
        let originalURL = bookmarks.first { $0.id == id }?.originalURL ?? url
        var bookmark = bookmarks.first { $0.id == id } ?? FolderAccessBookmark(id: id, originalURL: originalURL, data: data)
        bookmark.data = data
        bookmark.rememberLocation(scope.url)
        var updated = bookmarks.filter { $0.id != id }
        updated.append(bookmark)
        // Commit storage before publishing success or keeping a newly acquired scope.
        try store.save(updated)
        bookmarks = updated
        scopes[scope.url.standardizedFileURL] = scope
        folders.removeAll { $0.id == id }
        folders.append(RememberedFolderAccess(id: id, url: scope.url, isAvailable: true))
        recordRelocations(for: bookmark, to: scope.url)
        storageError = nil
        revision += 1
        return scope.url
    }

    @discardableResult
    func acceptPanelSelection(_ url: URL) throws -> URL {
        // AppKit starts the scope for URLs returned by NSOpenPanel. Transfer access
        // to an explicit bookmark scope before releasing the panel's implicit scope.
        defer { authorizer.stopAccessing(url) }
        return try rememberAuthorizedFolder(url)
    }

    func forget(_ id: UUID) throws {
        guard storeIsReadable else { throw FolderAccessError.invalidStore }
        guard bookmarks.contains(where: { $0.id == id }) else { return }
        let updated = bookmarks.filter { $0.id != id }
        try store.save(updated)
        bookmarks = updated
        folders.removeAll { $0.id == id }
        forgottenForNextLaunch = true
        revision += 1
        // Keep this process's scope until exit: forgetting a record must not cut off
        // an in-flight copy, scan, or preview. This is not a macOS permission revoke.
    }

    private func acquire(_ url: URL) throws -> FolderAccessScope {
        guard FolderAccessBookmark.isLocalURL(url) else { throw FolderAccessError.invalidFolder }
        if let scope = scopes[url.standardizedFileURL] {
            try authorizer.validateFolder(scope.url)
            return scope
        }
        let scope = FolderAccessScope(url: url, authorizer: authorizer)
        try authorizer.validateFolder(url)
        return scope
    }

    private func recordRelocations(for bookmark: FolderAccessBookmark, to url: URL) {
        for original in bookmark.knownLocations where original.standardizedFileURL != url.standardizedFileURL {
            // Replace an old destination when the same folder moves more than once.
            relocations.removeAll { $0.sourceURL == original.standardizedFileURL }
            relocations.append(FileRenameResult(sourceURL: original, destinationURL: url))
        }
        // A separately bookmarked child may move somewhere unrelated to its parent.
        // Rebase the most specific paths first so a parent move cannot swallow it.
        relocations.sort { $0.sourceURL.pathComponents.count > $1.sourceURL.pathComponents.count }
    }
}
