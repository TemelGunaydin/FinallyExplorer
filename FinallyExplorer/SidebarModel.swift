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
    let isDirectory: Bool

    init(id: UUID = UUID(), directoryURL: URL, title: String? = nil) {
        self.init(
            id: id,
            itemURL: directoryURL,
            isDirectory: true,
            title: title
        )
    }

    init(
        id: UUID = UUID(),
        itemURL: URL,
        isDirectory: Bool,
        title: String? = nil
    ) {
        self.id = id
        directoryURL = itemURL.standardizedFileURL
        self.title = title ?? Self.defaultTitle(for: itemURL)
        self.isDirectory = isDirectory
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case directoryURL
        case title
        case isDirectory
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        directoryURL = try container.decode(URL.self, forKey: .directoryURL)
            .standardizedFileURL
        title = try container.decode(String.self, forKey: .title)

        // Favorites created before file pinning was introduced were folders.
        isDirectory = try container.decodeIfPresent(
            Bool.self,
            forKey: .isDirectory
        ) ?? true
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(directoryURL, forKey: .directoryURL)
        try container.encode(title, forKey: .title)
        try container.encode(isDirectory, forKey: .isDirectory)
    }

    private static func defaultTitle(for url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path(percentEncoded: false) : name
    }
}

nonisolated enum SidebarPlaceID: Hashable, Sendable {
    case builtIn(SidebarBuiltInPlace)
    case favorite(UUID)
    case location(URL)
}

nonisolated struct SidebarPlace: Identifiable, Hashable, Sendable {
    private enum Storage: Hashable, Sendable {
        case builtIn(SidebarBuiltInPlace)
        case favorite(SidebarFavorite)
        case location(url: URL, title: String, systemImage: String)
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

    static func location(
        _ directoryURL: URL,
        title: String? = nil,
        systemImage: String = "folder"
    ) -> Self {
        let normalizedURL = directoryURL.standardizedFileURL
        let defaultTitle = normalizedURL.lastPathComponent.isEmpty
            ? normalizedURL.path(percentEncoded: false)
            : normalizedURL.lastPathComponent
        return Self(
            storage: .location(
                url: normalizedURL,
                title: title ?? defaultTitle,
                systemImage: systemImage
            )
        )
    }

    var id: SidebarPlaceID {
        switch storage {
        case let .builtIn(place):
            .builtIn(place)
        case let .favorite(favorite):
            .favorite(favorite.id)
        case let .location(url, _, _):
            .location(url)
        }
    }

    var title: String {
        switch storage {
        case let .builtIn(place):
            place.title
        case let .favorite(favorite):
            favorite.title
        case let .location(_, title, _):
            title
        }
    }

    var systemImage: String {
        switch storage {
        case let .builtIn(place):
            place.systemImage
        case let .favorite(favorite):
            favorite.isDirectory ? "folder" : "doc"
        case let .location(_, _, systemImage):
            systemImage
        }
    }

    var isDirectory: Bool {
        switch storage {
        case .builtIn, .location:
            true
        case let .favorite(favorite):
            favorite.isDirectory
        }
    }

    var url: URL? {
        switch storage {
        case let .builtIn(place):
            place.url
        case let .favorite(favorite):
            favorite.directoryURL
        case let .location(url, _, _):
            url
        }
    }

    var favorite: SidebarFavorite? {
        guard case let .favorite(favorite) = storage else { return nil }
        return favorite
    }
}

nonisolated enum SidebarFavoriteStatus: Equatable, Sendable {
    case custom(SidebarFavorite)
    case builtIn
    case available

    var isFavorite: Bool {
        switch self {
        case .custom, .builtIn:
            true
        case .available:
            false
        }
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
    let mountedVolumeMonitor: MountedVolumeMonitor

    @ObservationIgnored private let store: any SidebarFavoriteStoring
    private static let builtInURLs = Set(
        SidebarBuiltInPlace.allCases.compactMap(\.url).map(normalizedURL)
    )

    init(
        store: (any SidebarFavoriteStoring)? = nil,
        mountedVolumeMonitor: MountedVolumeMonitor? = nil
    ) {
        let store = store ?? UserDefaultsSidebarFavoriteStore()
        self.store = store
        self.mountedVolumeMonitor = mountedVolumeMonitor ?? MountedVolumeMonitor()

        let loadedFavorites = store.loadFavorites()
        let sanitizedFavorites = Self.sanitizedFavorites(loadedFavorites)
        favorites = sanitizedFavorites

        if sanitizedFavorites != loadedFavorites {
            store.saveFavorites(sanitizedFavorites)
        }
    }

    var allPlaces: [SidebarPlace] {
        SidebarPlace.standardPlaces
            + favorites.map(SidebarPlace.favorite)
            + mountedVolumePlaces
    }

    var mountedVolumePlaces: [SidebarPlace] {
        mountedVolumeMonitor.volumes.map(\.sidebarPlace)
    }

    func favorite(for itemURL: URL) -> SidebarFavorite? {
        let normalizedURL = Self.normalizedURL(itemURL)
        return favorites.first { $0.directoryURL == normalizedURL }
    }

    func isFavorite(_ itemURL: URL) -> Bool {
        favoriteStatus(for: itemURL).isFavorite
    }

    func favoriteStatus(for itemURL: URL) -> SidebarFavoriteStatus {
        let normalizedURL = Self.normalizedURL(itemURL)
        if let favorite = favorites.first(where: {
            $0.directoryURL == normalizedURL
        }) {
            return .custom(favorite)
        }
        return Self.isBuiltIn(normalizedURL) ? .builtIn : .available
    }

    func canAdd(directoryURL: URL) -> Bool {
        canAdd(itemURL: directoryURL, isDirectory: true)
    }

    func canAdd(itemURL: URL, isDirectory: Bool) -> Bool {
        guard let item = Self.existingItem(itemURL),
              item.isDirectory == isDirectory else {
            return false
        }

        return (isDirectory == false || Self.isBuiltIn(item.url) == false)
            && favorite(for: item.url) == nil
    }

    /// Adds a local folder to the sidebar, or returns its existing favorite.
    @discardableResult
    func add(directoryURL: URL) -> SidebarFavorite? {
        add(itemURL: directoryURL, isDirectory: true)
    }

    /// Pins a local file or folder, or returns its existing favorite.
    @discardableResult
    func add(itemURL: URL, isDirectory: Bool) -> SidebarFavorite? {
        guard let item = Self.existingItem(itemURL),
              item.isDirectory == isDirectory,
              isDirectory == false || Self.isBuiltIn(item.url) == false else {
            return nil
        }

        if let existingFavorite = favorite(for: item.url) {
            return existingFavorite
        }

        let favorite = SidebarFavorite(
            itemURL: item.url,
            isDirectory: item.isDirectory
        )
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

    func applyRename(_ result: FileRenameResult) {
        var didChange = false

        favorites = favorites.map { favorite in
            guard let relocatedURL = FileURLRelocation.rebase(
                favorite.directoryURL,
                from: result.sourceURL,
                to: result.destinationURL
            ) else {
                return favorite
            }

            didChange = true
            let usedAutomaticTitle = favorite.title
                == result.sourceURL.lastPathComponent
            return SidebarFavorite(
                id: favorite.id,
                itemURL: relocatedURL,
                isDirectory: favorite.isDirectory,
                title: usedAutomaticTitle
                    ? result.destinationURL.lastPathComponent
                    : favorite.title
            )
        }

        if didChange {
            store.saveFavorites(favorites)
        }
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
                itemURL: directoryURL,
                isDirectory: favorite.isDirectory,
                title: title
            )
        }
    }

    private static func existingItem(
        _ url: URL
    ) -> (url: URL, isDirectory: Bool)? {
        let normalizedURL = normalizedURL(url)
        guard normalizedURL.isFileURL else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: normalizedURL.path,
            isDirectory: &isDirectory
        ) else {
            return nil
        }

        return (normalizedURL, isDirectory.boolValue)
    }

    private static func normalizedURL(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func isBuiltIn(_ url: URL) -> Bool {
        builtInURLs.contains(url)
    }
}
