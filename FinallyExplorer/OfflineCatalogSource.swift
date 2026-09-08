import Foundation

nonisolated struct OfflineCatalogSource: Sendable {
    let volume: OfflineCatalogVolume
    let relativeRoot: String
    let rootInode: UInt64

    var rootURL: URL { relativeRoot.isEmpty ? volume.rootURL : volume.rootURL.appending(path: relativeRoot) }
}
