//
//  SidebarModelTests.swift
//  FinallyExplorerTests
//

import Foundation
import Testing
@testable import FinallyExplorer

@MainActor
struct SidebarModelTests {
    @Test("A chosen folder is persisted and restored as a sidebar favorite")
    func customFolderPersistsAcrossModelInstances() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = SidebarFavoriteStoreSpy()
        let firstModel = SidebarModel(store: store)
        #expect(firstModel.canAdd(directoryURL: directoryURL))

        let favorite = try #require(firstModel.add(directoryURL: directoryURL))

        #expect(firstModel.favorites == [favorite])
        #expect(firstModel.canAdd(directoryURL: directoryURL) == false)
        #expect(store.saveCount == 1)

        let restoredModel = SidebarModel(store: store)
        #expect(restoredModel.favorites == [favorite])
        #expect(restoredModel.favorite(for: directoryURL) == favorite)
        #expect(restoredModel.allPlaces.contains(.favorite(favorite)))
    }

    @Test("The sidebar prevents duplicates, standard locations, and files")
    func onlyUniqueCustomDirectoriesCanBeAdded() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appending(path: "note.txt")
        try Data("note".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let model = SidebarModel(store: SidebarFavoriteStoreSpy())
        let favorite = try #require(model.add(directoryURL: directoryURL))

        #expect(model.add(directoryURL: directoryURL) == favorite)
        #expect(model.favorites == [favorite])
        #expect(model.canAdd(directoryURL: fileURL) == false)
        #expect(model.add(directoryURL: fileURL) == nil)

        let downloadsURL = try #require(SidebarBuiltInPlace.downloads.url)
        #expect(model.canAdd(directoryURL: downloadsURL) == false)
        #expect(model.add(directoryURL: downloadsURL) == nil)
    }

    @Test("Removing a favorite updates the sidebar and persisted storage")
    func removingFavoritePersistsTheChange() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = SidebarFavoriteStoreSpy()
        let model = SidebarModel(store: store)
        let favorite = try #require(model.add(directoryURL: directoryURL))

        model.remove(favorite)

        #expect(model.favorites.isEmpty)
        #expect(model.favorite(for: directoryURL) == nil)
        #expect(store.savedFavorites.isEmpty)
        #expect(store.saveCount == 2)

        model.remove(favorite)
        #expect(store.saveCount == 2)
    }

    @Test("Files can be pinned, restored, and removed as favorites")
    func fileFavoritesRoundTrip() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appending(path: "favorite.swift")
        try Data("struct Favorite {}".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = SidebarFavoriteStoreSpy()
        let model = SidebarModel(store: store)

        #expect(model.canAdd(itemURL: fileURL, isDirectory: false))
        let favorite = try #require(
            model.add(itemURL: fileURL, isDirectory: false)
        )
        #expect(favorite.isDirectory == false)
        #expect(model.isFavorite(fileURL))
        #expect(model.favoriteStatus(for: fileURL) == .custom(favorite))
        #expect(model.canAdd(itemURL: fileURL, isDirectory: false) == false)

        let restoredModel = SidebarModel(store: store)
        #expect(restoredModel.favorite(for: fileURL) == favorite)
        #expect(restoredModel.allPlaces.contains(.favorite(favorite)))

        restoredModel.remove(favorite)
        #expect(restoredModel.isFavorite(fileURL) == false)
        #expect(restoredModel.favoriteStatus(for: fileURL) == .available)
    }

    @Test("UserDefaults storage survives an encoded round trip")
    func userDefaultsStoreRoundTripsFavorites() throws {
        let suiteName = "FinallyExplorer.SidebarTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = UserDefaultsSidebarFavoriteStore(defaults: defaults)
        let favoriteID = try #require(
            UUID(uuidString: "10000000-0000-0000-0000-000000000011")
        )
        let favorite = SidebarFavorite(
            id: favoriteID,
            directoryURL: directoryURL,
            title: "Projects"
        )

        store.saveFavorites([favorite])

        #expect(store.loadFavorites() == [favorite])
    }

    @Test("Favorites saved before file pinning still decode as folders")
    func legacyFavoriteDecodingDefaultsToFolder() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let legacyFavorite = LegacySidebarFavorite(
            id: UUID(),
            directoryURL: directoryURL,
            title: "Legacy"
        )
        let data = try JSONEncoder().encode(legacyFavorite)
        let decoded = try JSONDecoder().decode(SidebarFavorite.self, from: data)

        #expect(decoded.directoryURL == directoryURL.standardizedFileURL)
        #expect(decoded.isDirectory)
    }

    @Test("Restoring favorites removes malformed and duplicate records")
    func malformedSavedFavoritesAreSanitized() throws {
        let firstDirectoryURL = try makeTemporaryDirectory()
        let secondDirectoryURL = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstDirectoryURL)
            try? FileManager.default.removeItem(at: secondDirectoryURL)
        }

        let identifier = try #require(
            UUID(uuidString: "10000000-0000-0000-0000-000000000012")
        )
        let valid = SidebarFavorite(
            id: identifier,
            directoryURL: firstDirectoryURL,
            title: "First"
        )
        let duplicateIdentifier = SidebarFavorite(
            id: identifier,
            directoryURL: secondDirectoryURL,
            title: "Second"
        )
        let blankTitle = SidebarFavorite(
            directoryURL: secondDirectoryURL,
            title: "   "
        )
        let store = SidebarFavoriteStoreSpy(
            favorites: [valid, duplicateIdentifier, blankTitle]
        )

        let model = SidebarModel(store: store)

        #expect(model.favorites == [valid])
        #expect(store.savedFavorites == [valid])
    }
}

private struct LegacySidebarFavorite: Codable {
    let id: UUID
    let directoryURL: URL
    let title: String
}

@MainActor
private final class SidebarFavoriteStoreSpy: SidebarFavoriteStoring {
    private(set) var savedFavorites: [SidebarFavorite]
    private(set) var saveCount = 0

    init(favorites: [SidebarFavorite] = []) {
        savedFavorites = favorites
    }

    func loadFavorites() -> [SidebarFavorite] {
        savedFavorites
    }

    func saveFavorites(_ favorites: [SidebarFavorite]) {
        savedFavorites = favorites
        saveCount += 1
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory.appending(
        path: "FinallyExplorer-Sidebar-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true
    )
    return directoryURL
}
