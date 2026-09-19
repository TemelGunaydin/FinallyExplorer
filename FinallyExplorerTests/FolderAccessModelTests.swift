import Foundation
import Testing
@testable import FinallyExplorer

@MainActor
struct FolderAccessModelTests {
    private let folder = URL(filePath: "/Volumes/Fixture/Projects", directoryHint: .isDirectory)

    @Test("A selected folder is persisted, restored before use, and balanced on exit")
    func restoresAccess() throws {
        let store = MemoryFolderAccessBookmarkStore()
        let authorizer = FolderAccessAuthorizerSpy()
        var first: FolderAccessModel? = FolderAccessModel(store: store, authorizer: authorizer)
        #expect(first?.folders.isEmpty == true)
        #expect(try first?.rememberAuthorizedFolder(folder) == folder)
        #expect(store.bookmarks.count == 1)
        #expect(first?.folders.first?.isAvailable == true)
        #expect(authorizer.starts == [folder])
        #expect(authorizer.stops.isEmpty)
        first = nil
        #expect(authorizer.stops == [folder])

        var second: FolderAccessModel? = FolderAccessModel(store: store, authorizer: authorizer)
        #expect(second?.folders.first?.url == folder)
        #expect(second?.folders.first?.isAvailable == true)
        #expect(authorizer.starts == [folder, folder])
        second = nil
        #expect(authorizer.stops == [folder, folder])
    }

    @Test("Selecting the same folder shares one explicit scope without duplicate records")
    func deduplicatesAccess() throws {
        let store = MemoryFolderAccessBookmarkStore()
        let authorizer = FolderAccessAuthorizerSpy()
        let model = FolderAccessModel(store: store, authorizer: authorizer)
        try model.rememberAuthorizedFolder(folder)
        let id = try #require(model.folders.first?.id)
        try model.rememberAuthorizedFolder(folder)
        model.restoreUnavailableFolders()
        #expect(model.folders.map(\.id) == [id])
        #expect(store.bookmarks.count == 1)
        #expect(authorizer.starts == [folder])
        #expect(authorizer.stops.isEmpty)
    }

    @Test("Panel access is released only after the explicit scope is acquired")
    func transfersPanelAccess() throws {
        let authorizer = FolderAccessAuthorizerSpy()
        var model: FolderAccessModel? = FolderAccessModel(store: MemoryFolderAccessBookmarkStore(), authorizer: authorizer)
        #expect(try model?.acceptPanelSelection(folder) == folder)
        #expect(authorizer.events.suffix(2) == ["start", "stop"])
        #expect(authorizer.stops == [folder], "The panel's implicit scope is released, not retained indefinitely.")
        model = nil
        #expect(authorizer.stops == [folder, folder], "The explicit scope is released at session end.")
    }

    @Test("Panel access is also released if bookmarking fails")
    func panelFailure() throws {
        let store = MemoryFolderAccessBookmarkStore()
        let authorizer = FolderAccessAuthorizerSpy()
        authorizer.failMake = true
        let model = FolderAccessModel(store: store, authorizer: authorizer)
        #expect(throws: (any Error).self) { try model.acceptPanelSelection(folder) }
        #expect(model.folders.isEmpty)
        #expect(store.bookmarks.isEmpty)
        #expect(authorizer.starts.isEmpty)
        #expect(authorizer.stops == [folder])
    }

    @Test("A disconnected or invalid bookmark is retained and can be retried")
    func disconnectedDisk() throws {
        let store = MemoryFolderAccessBookmarkStore()
        let bookmark = FolderAccessBookmark(id: UUID(), originalURL: folder, data: Data("offline".utf8))
        store.bookmarks = [bookmark]
        let authorizer = FolderAccessAuthorizerSpy()
        let model = FolderAccessModel(store: store, authorizer: authorizer)
        #expect(model.folders == [RememberedFolderAccess(id: bookmark.id, url: folder, isAvailable: false)])
        #expect(store.bookmarks == [bookmark])
        #expect(authorizer.starts.isEmpty)
        authorizer.resolutions[bookmark.data] = ResolvedFolderAccessBookmark(url: folder, isStale: false)
        model.restoreUnavailableFolders()
        #expect(model.folders.first?.isAvailable == true)
        #expect(model.revision == 1)
        #expect(store.bookmarks == [bookmark])
    }

    @Test("Stale moved bookmarks refresh without losing the original favorite mapping")
    func staleMovedFolder() throws {
        let store = MemoryFolderAccessBookmarkStore()
        let moved = URL(filePath: "/Volumes/Fixture/Renamed", directoryHint: .isDirectory)
        let bookmark = FolderAccessBookmark(id: UUID(), originalURL: folder, data: Data("stale".utf8))
        store.bookmarks = [bookmark]
        let authorizer = FolderAccessAuthorizerSpy()
        authorizer.resolutions[bookmark.data] = ResolvedFolderAccessBookmark(url: moved, isStale: true)
        let model = FolderAccessModel(store: store, authorizer: authorizer)
        #expect(model.folders.first?.url == moved)
        #expect(model.folders.first?.id == bookmark.id)
        #expect(store.bookmarks.first?.originalURL == folder)
        #expect(store.bookmarks.first?.data != bookmark.data)
        #expect(model.relocations.first?.sourceURL == folder)
        #expect(model.relocations.first?.destinationURL == moved)

        let next = FolderAccessModel(store: store, authorizer: authorizer)
        #expect(next.relocations.first?.sourceURL == folder, "Retain mapping even if the sidebar was not saved before exit.")
        let child = folder.appending(path: "Sources/main.swift")
        #expect(FileURLRelocation.rebase(child, from: folder, to: moved) == moved.appending(path: "Sources/main.swift"))
    }

    @Test("A stale refresh failure retains both the old record and current access")
    func staleRefreshFailure() {
        let store = MemoryFolderAccessBookmarkStore()
        let bookmark = FolderAccessBookmark(id: UUID(), originalURL: folder, data: Data("stale".utf8))
        store.bookmarks = [bookmark]
        let authorizer = FolderAccessAuthorizerSpy()
        authorizer.resolutions[bookmark.data] = ResolvedFolderAccessBookmark(url: folder, isStale: true)
        authorizer.failMake = true
        let model = FolderAccessModel(store: store, authorizer: authorizer)
        #expect(model.folders.first?.isAvailable == true)
        #expect(model.storageError != nil)
        #expect(store.bookmarks == [bookmark])
        #expect(authorizer.stops.isEmpty)
    }

    @Test("Repeated moves retain both original and previously saved sidebar locations")
    func repeatedMoves() throws {
        let store = MemoryFolderAccessBookmarkStore()
        let authorizer = FolderAccessAuthorizerSpy()
        let bookmark = FolderAccessBookmark(id: UUID(), originalURL: folder, data: Data("first-move".utf8))
        store.bookmarks = [bookmark]
        let firstMove = URL(filePath: "/Volumes/Fixture/First Move")
        let secondMove = URL(filePath: "/Volumes/Fixture/Second Move")
        authorizer.resolutions[bookmark.data] = ResolvedFolderAccessBookmark(url: firstMove, isStale: true)
        let first = FolderAccessModel(store: store, authorizer: authorizer)
        #expect(first.folders.first?.url == firstMove)
        let saved = try #require(store.bookmarks.first)
        authorizer.resolutions[saved.data] = ResolvedFolderAccessBookmark(url: secondMove, isStale: true)
        let next = FolderAccessModel(store: store, authorizer: authorizer)
        #expect(next.relocations.contains { $0.sourceURL == folder && $0.destinationURL == secondMove })
        #expect(next.relocations.contains { $0.sourceURL == firstMove && $0.destinationURL == secondMove })
        #expect(store.bookmarks.first?.knownLocations.contains(firstMove) == true)
        #expect(store.bookmarks.first?.knownLocations.contains(secondMove) == true)
    }

    @Test("A more specific child relocation is applied before its parent relocation")
    func nestedMoves() throws {
        let store = MemoryFolderAccessBookmarkStore()
        let child = folder.appending(path: "Child")
        let parentBookmark = FolderAccessBookmark(id: UUID(), originalURL: folder, data: Data("parent".utf8))
        let childBookmark = FolderAccessBookmark(id: UUID(), originalURL: child, data: Data("child".utf8))
        store.bookmarks = [parentBookmark, childBookmark]
        let authorizer = FolderAccessAuthorizerSpy()
        let parentDestination = URL(filePath: "/Volumes/Fixture/MovedParent")
        let childDestination = URL(filePath: "/Volumes/Fixture/Elsewhere")
        authorizer.resolutions[parentBookmark.data] = ResolvedFolderAccessBookmark(url: parentDestination, isStale: true)
        authorizer.resolutions[childBookmark.data] = ResolvedFolderAccessBookmark(url: childDestination, isStale: true)
        let model = FolderAccessModel(store: store, authorizer: authorizer)
        var favorite = child.appending(path: "Nested/note.txt")
        for relocation in model.relocations {
            favorite = FileURLRelocation.rebase(favorite, from: relocation.sourceURL, to: relocation.destinationURL) ?? favorite
        }
        #expect(favorite == childDestination.appending(path: "Nested/note.txt"))
    }

    @Test("An old path reused by another folder is not redirected or substituted for a moved grant")
    func reusedOldLocation() throws {
        let store = MemoryFolderAccessBookmarkStore()
        let authorizer = FolderAccessAuthorizerSpy()
        let moved = URL(filePath: "/Volumes/Fixture/Moved")
        let bookmark = FolderAccessBookmark(id: UUID(), originalURL: folder, data: Data("moved".utf8))
        store.bookmarks = [bookmark]
        authorizer.resolutions[bookmark.data] = ResolvedFolderAccessBookmark(url: moved, isStale: true)
        authorizer.existingLocations.insert(folder)
        let model = FolderAccessModel(store: store, authorizer: authorizer)
        #expect(model.recoverableRelocations.isEmpty)
        try model.rememberAuthorizedFolder(folder)
        #expect(model.folders.count == 2)
        #expect(Set(model.folders.map(\.url)) == [folder, moved])
        #expect(store.bookmarks.count == 2)
        #expect(model.recoverableRelocations.isEmpty)
    }

    @Test("A denied resolved folder is not reported as available and its scope is released")
    func permissionDenied() {
        let store = MemoryFolderAccessBookmarkStore()
        let bookmark = FolderAccessBookmark(id: UUID(), originalURL: folder, data: Data("denied".utf8))
        store.bookmarks = [bookmark]
        let authorizer = FolderAccessAuthorizerSpy()
        authorizer.resolutions[bookmark.data] = ResolvedFolderAccessBookmark(url: folder, isStale: false)
        authorizer.denied.insert(folder)
        let model = FolderAccessModel(store: store, authorizer: authorizer)
        #expect(model.folders.first?.isAvailable == false)
        #expect(authorizer.starts == authorizer.stops)
        #expect(store.bookmarks == [bookmark])
    }

    @Test("Already-readable URLs do not require a successful scope start or a matching stop")
    func alreadyReadableURL() throws {
        let authorizer = FolderAccessAuthorizerSpy()
        authorizer.startResult = false
        var model: FolderAccessModel? = FolderAccessModel(store: MemoryFolderAccessBookmarkStore(), authorizer: authorizer)
        try model?.rememberAuthorizedFolder(folder)
        #expect(model?.folders.first?.isAvailable == true)
        model = nil
        #expect(authorizer.starts == [folder])
        #expect(authorizer.stops.isEmpty)
    }

    @Test("Failed persistence rolls back a newly started scope and visible state")
    func saveFailure() {
        let store = FailingFolderAccessStore()
        let authorizer = FolderAccessAuthorizerSpy()
        let model = FolderAccessModel(store: store, authorizer: authorizer)
        #expect(throws: (any Error).self) { try model.rememberAuthorizedFolder(folder) }
        #expect(model.folders.isEmpty)
        #expect(model.revision == 0)
        #expect(authorizer.starts == [folder])
        #expect(authorizer.stops == [folder])
    }

    @Test("Forgetting applies on next launch without interrupting a current operation")
    func forgettingKeepsSessionScope() throws {
        let store = MemoryFolderAccessBookmarkStore()
        let authorizer = FolderAccessAuthorizerSpy()
        var model: FolderAccessModel? = FolderAccessModel(store: store, authorizer: authorizer)
        try model?.rememberAuthorizedFolder(folder)
        let id = try #require(model?.folders.first?.id)
        try model?.forget(id)
        #expect(model?.revision == 2, "Global search must reconcile its direct roots when a saved grant is forgotten.")
        #expect(store.bookmarks.isEmpty)
        #expect(model?.folders.isEmpty == true)
        #expect(model?.forgottenForNextLaunch == true)
        #expect(authorizer.stops.isEmpty)
        let next = FolderAccessModel(store: store, authorizer: authorizer)
        #expect(next.folders.isEmpty)
        #expect(authorizer.starts.count == 1)
        model = nil
        #expect(authorizer.stops == [folder])
    }

    @Test("Cancelling folder selection performs no bookmark or workspace-side action")
    func cancellingSelection() async throws {
        let store = MemoryFolderAccessBookmarkStore()
        let authorizer = FolderAccessAuthorizerSpy()
        let model = FolderAccessModel(store: store, authorizer: authorizer)
        let chosen = try await FolderAccessPicker.choose(using: model, startingAt: folder, chooser: CancelledFolderChooser())
        #expect(chosen == nil)
        #expect(model.folders.isEmpty)
        #expect(model.revision == 0)
        #expect(store.bookmarks.isEmpty)
        #expect(authorizer.events.isEmpty)
    }

    @Test("Remote and non-file selections cannot become grants", arguments: ["https://example.com/folder", "file://remote.example/folder"])
    func rejectsNonFileURL(_ input: String) throws {
        let authorizer = FolderAccessAuthorizerSpy()
        let model = FolderAccessModel(store: MemoryFolderAccessBookmarkStore(), authorizer: authorizer)
        let url = try #require(URL(string: input))
        #expect(throws: (any Error).self) { try model.rememberAuthorizedFolder(url) }
        #expect(authorizer.events.isEmpty)
        #expect(model.folders.isEmpty)
    }

    @Test("The bookmark store round trips data and refuses to overwrite corrupt storage")
    func defaultsStore() throws {
        let suite = "FinallyExplorer.FolderAccessTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsFolderAccessBookmarkStore(defaults: defaults)
        let bookmark = FolderAccessBookmark(id: UUID(), originalURL: folder, data: Data([1, 2, 3]))
        try store.save([bookmark])
        #expect(try store.load() == [bookmark])
        let invalidData = Data("not a bookmark store".utf8)
        defaults.set(invalidData, forKey: UserDefaultsFolderAccessBookmarkStore.key)
        let authorizer = FolderAccessAuthorizerSpy()
        let model = FolderAccessModel(store: store, authorizer: authorizer)
        #expect(model.storageError != nil)
        #expect(throws: (any Error).self) { try model.rememberAuthorizedFolder(folder) }
        #expect(defaults.data(forKey: UserDefaultsFolderAccessBookmarkStore.key) == invalidData)
        #expect(authorizer.events.isEmpty)
    }

    @Test("Duplicate IDs and an unexpected defaults value are treated as corrupt storage")
    func invalidRecords() throws {
        let suite = "FinallyExplorer.FolderAccessTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsFolderAccessBookmarkStore(defaults: defaults)
        let bookmark = FolderAccessBookmark(id: UUID(), originalURL: folder, data: Data([1]))
        try store.save([bookmark, bookmark])
        #expect(throws: (any Error).self) { try store.load() }
        defaults.set("unexpected string", forKey: UserDefaultsFolderAccessBookmarkStore.key)
        #expect(throws: (any Error).self) { try store.load() }
    }

    @Test("Home lookup names the real account, not the sandbox container")
    func realHome() throws {
        let home = UserHomeDirectory.url
        #expect(home.isFileURL)
        #expect(home.lastPathComponent.isEmpty == false)
        #expect(home.path.contains("/Library/Containers/") == false)
        #expect(SidebarBuiltInPlace.home.url == home)
    }

    @Test("The real macOS bookmark codec restores an isolated fixture folder")
    func foundationBookmarkRoundTrip() throws {
        let root = URL.temporaryDirectory.appending(path: "FolderAccess-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let authorizer = LocalFolderAccessAuthorizer()
        let data = try authorizer.makeBookmark(for: root)
        let resolved = try authorizer.resolve(data)
        #expect(resolved.url.resolvingSymlinksInPath().standardizedFileURL == root.resolvingSymlinksInPath().standardizedFileURL)
        let store = MemoryFolderAccessBookmarkStore()
        store.bookmarks = [FolderAccessBookmark(id: UUID(), originalURL: root, data: data)]
        let restored = FolderAccessModel(store: store, authorizer: authorizer)
        #expect(restored.folders.first?.isAvailable == true)
    }

    @Test("Real macOS bookmarks follow a fixture folder renamed between model instances")
    func foundationBookmarkFollowsRename() throws {
        let root = URL.temporaryDirectory.appending(path: "FolderAccessRename-\(UUID())", directoryHint: .isDirectory)
        let before = root.appending(path: "Before", directoryHint: .isDirectory)
        let after = root.appending(path: "After", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: before, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MemoryFolderAccessBookmarkStore()
        var first: FolderAccessModel? = FolderAccessModel(store: store)
        try first?.rememberAuthorizedFolder(before)
        first = nil
        try FileManager.default.moveItem(at: before, to: after)
        let second = FolderAccessModel(store: store)
        let restoredURL = try #require(second.folders.first?.url)
        #expect(restoredURL.resolvingSymlinksInPath() == after.resolvingSymlinksInPath())
        #expect(second.folders.first?.isAvailable == true)
        #expect(second.relocations.first?.sourceURL == before.standardizedFileURL)
    }
}

@MainActor
private final class FolderAccessAuthorizerSpy: FolderAccessAuthorizing {
    var resolutions: [Data: ResolvedFolderAccessBookmark] = [:]
    var starts: [URL] = []
    var stops: [URL] = []
    var events: [String] = []
    var denied: Set<URL> = []
    var existingLocations: Set<URL> = []
    var failMake = false
    var startResult = true

    func makeBookmark(for url: URL) throws -> Data {
        if failMake { throw FolderAccessError.unavailable }
        let data = Data("bookmark-\(url.path)".utf8)
        resolutions[data] = ResolvedFolderAccessBookmark(url: url, isStale: false)
        return data
    }
    func resolve(_ data: Data) throws -> ResolvedFolderAccessBookmark {
        guard let resolved = resolutions[data] else { throw FolderAccessError.unavailable }
        return resolved
    }
    func startAccessing(_ url: URL) -> Bool { starts.append(url); events.append("start"); return startResult }
    func stopAccessing(_ url: URL) { stops.append(url); events.append("stop") }
    func validateFolder(_ url: URL) throws {
        if denied.contains(url) { throw FolderAccessError.unavailable }
    }
    func isLocationDefinitelyMissing(_ url: URL) -> Bool {
        existingLocations.contains(url) == false && denied.contains(url) == false
    }
}

@MainActor
private final class FailingFolderAccessStore: FolderAccessBookmarkStoring {
    func load() throws -> [FolderAccessBookmark] { [] }
    func save(_ bookmarks: [FolderAccessBookmark]) throws { throw FolderAccessError.invalidStore }
}

@MainActor
private struct CancelledFolderChooser: FolderAccessChoosing {
    func choose(startingAt url: URL?) async -> URL? { nil }
}
