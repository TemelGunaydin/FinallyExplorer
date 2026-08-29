//
//  SidebarModel.swift
//  FinallyExplorer
//

import Foundation
import Observation

nonisolated enum SidebarBuiltInPlace: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home
    case applications
    case desktop
    case documents
    case downloads
    case pictures
    case music
    case movies
    case systemDrive

    var id: String { rawValue }

    static var primaryPlaces: [Self] {
        [.home, .applications, .desktop, .documents, .downloads]
    }

    static var mediaPlaces: [Self] {
        [.pictures, .music, .movies]
    }

    static var locationPlaces: [Self] {
        [.systemDrive]
    }

    var title: String {
        switch self {
        case .home:
            "Home"
        case .applications:
            "Applications"
        case .desktop:
            "Desktop"
        case .documents:
            "Documents"
        case .downloads:
            "Downloads"
        case .pictures:
            "Pictures"
        case .music:
            "Music"
        case .movies:
            "Movies"
        case .systemDrive:
            "Macintosh HD"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            "house"
        case .applications:
            "app.dashed"
        case .desktop:
            "desktopcomputer"
        case .documents:
            "doc"
        case .downloads:
            "arrow.down.circle"
        case .pictures:
            "photo.on.rectangle"
        case .music:
            "music.note"
        case .movies:
            "film"
        case .systemDrive:
            "internaldrive"
        }
    }

    var url: URL? {
        switch self {
        case .home:
            FileManager.default.homeDirectoryForCurrentUser
        case .applications:
            FileManager.default.urls(
                for: .applicationDirectory,
                in: .localDomainMask
            ).first
        case .desktop:
            FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        case .documents:
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        case .downloads:
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        case .pictures:
            FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        case .music:
            FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
        case .movies:
            FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        case .systemDrive:
            URL(filePath: "/", directoryHint: .isDirectory)
        }
    }
}

nonisolated struct SidebarFavorite: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let directoryURL: URL
    let title: String

    init(id: UUID = UUID(), directoryURL: URL, title: String? = nil) {
        self.id = id
        self.directoryURL = directoryURL.standardizedFileURL
        self.title = title ?? Self.defaultTitle(for: directoryURL)
    }

    private static func defaultTitle(for url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path(percentEncoded: false) : name
    }
}

nonisolated enum SidebarPlaceID: Hashable, Sendable {
    case builtIn(SidebarBuiltInPlace)
    case favorite(UUID)
}

nonisolated struct SidebarPlace: Identifiable, Hashable, Sendable {
    private enum Storage: Hashable, Sendable {
        case builtIn(SidebarBuiltInPlace)
        case favorite(SidebarFavorite)
    }

    private let storage: Storage

    static let home = Self.builtIn(.home)
    static let applications = Self.builtIn(.applications)
    static let desktop = Self.builtIn(.desktop)
    static let documents = Self.builtIn(.documents)
    static let downloads = Self.builtIn(.downloads)
    static let pictures = Self.builtIn(.pictures)
    static let music = Self.builtIn(.music)
    static let movies = Self.builtIn(.movies)
    static let systemDrive = Self.builtIn(.systemDrive)

    static var standardPlaces: [Self] {
        SidebarBuiltInPlace.allCases.map(Self.builtIn)
    }

    static func builtIn(_ place: SidebarBuiltInPlace) -> Self {
        Self(storage: .builtIn(place))
    }

    static func favorite(_ favorite: SidebarFavorite) -> Self {
        Self(storage: .favorite(favorite))
    }

    var id: SidebarPlaceID {
        switch storage {
        case let .builtIn(place):
            .builtIn(place)
        case let .favorite(favorite):
            .favorite(favorite.id)
        }
    }

    var title: String {
        switch storage {
        case let .builtIn(place):
            place.title
        case let .favorite(favorite):
            favorite.title
        }
    }

    var systemImage: String {
        switch storage {
        case let .builtIn(place):
            place.systemImage
        case .favorite:
            "folder"
        }
    }

    var url: URL? {
        switch storage {
        case let .builtIn(place):
            place.url
        case let .favorite(favorite):
            favorite.directoryURL
        }
    }

    var favorite: SidebarFavorite? {
        guard case let .favorite(favorite) = storage else { return nil }
        return favorite
    }
}

@MainActor
protocol SidebarFavoriteStoring {
    func loadFavorites() -> [SidebarFavorite]
    func saveFavorites(_ favorites: [SidebarFavorite])
}

@MainActor
struct UserDefaultsSidebarFavoriteStore: SidebarFavoriteStoring {
    private static let storageKey = "sidebar-favorites-v1"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadFavorites() -> [SidebarFavorite] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        return (try? JSONDecoder().decode([SidebarFavorite].self, from: data)) ?? []
    }

    func saveFavorites(_ favorites: [SidebarFavorite]) {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

@MainActor
@Observable
final class SidebarModel {
    private(set) var favorites: [SidebarFavorite]

    @ObservationIgnored private let store: any SidebarFavoriteStoring

    init(store: (any SidebarFavoriteStoring)? = nil) {
        let store = store ?? UserDefaultsSidebarFavoriteStore()
        self.store = store

        let loadedFavorites = store.loadFavorites()
        let sanitizedFavorites = Self.sanitizedFavorites(loadedFavorites)
        favorites = sanitizedFavorites

        if sanitizedFavorites != loadedFavorites {
            store.saveFavorites(sanitizedFavorites)
        }
    }

    var allPlaces: [SidebarPlace] {
        SidebarPlace.standardPlaces + favorites.map(SidebarPlace.favorite)
    }

    func favorite(for directoryURL: URL) -> SidebarFavorite? {
        let normalizedURL = Self.normalizedURL(directoryURL)
        return favorites.first { $0.directoryURL == normalizedURL }
    }

    /// Adds a local folder to the sidebar, or returns its existing favorite.
    @discardableResult
    func add(directoryURL: URL) -> SidebarFavorite? {
        guard let directoryURL = Self.existingDirectoryURL(directoryURL),
              Self.isBuiltIn(directoryURL) == false else {
            return nil
        }

        if let existingFavorite = favorite(for: directoryURL) {
            return existingFavorite
        }

        let favorite = SidebarFavorite(directoryURL: directoryURL)
        favorites.append(favorite)
        store.saveFavorites(favorites)
        return favorite
    }

    func remove(_ favorite: SidebarFavorite) {
        guard let index = favorites.firstIndex(where: { $0.id == favorite.id }) else {
            return
        }

        favorites.remove(at: index)
        store.saveFavorites(favorites)
    }

    private static func sanitizedFavorites(
        _ favorites: [SidebarFavorite]
    ) -> [SidebarFavorite] {
        var usedIDs = Set<UUID>()
        var usedURLs = Set<URL>()

        return favorites.compactMap { favorite in
            let directoryURL = normalizedURL(favorite.directoryURL)
            let title = favorite.title.trimmingCharacters(in: .whitespacesAndNewlines)

            guard directoryURL.isFileURL,
                  title.isEmpty == false,
                  isBuiltIn(directoryURL) == false,
                  usedIDs.insert(favorite.id).inserted,
                  usedURLs.insert(directoryURL).inserted else {
                return nil
            }

            return SidebarFavorite(
                id: favorite.id,
                directoryURL: directoryURL,
                title: title
            )
        }
    }

    private static func existingDirectoryURL(_ url: URL) -> URL? {
        let normalizedURL = normalizedURL(url)
        guard normalizedURL.isFileURL else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: normalizedURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            return nil
        }

        return normalizedURL
    }

    private static func normalizedURL(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func isBuiltIn(_ url: URL) -> Bool {
        SidebarBuiltInPlace.allCases.contains {
            guard let builtInURL = $0.url else { return false }
            return normalizedURL(builtInURL) == url
        }
    }
}
