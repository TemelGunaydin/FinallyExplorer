import Foundation

nonisolated enum OfflineCatalogValidation {
    static let entryLimit = 100_000
    static let pathByteLimit = 16_000_000
    static let payloadByteLimit = 64_000_000
    static let catalogLimit = 32

    static func path(_ path: String, allowsEmpty: Bool = false) throws {
        if allowsEmpty, path.isEmpty { return }
        guard path.utf8.count <= 16_384,
              (try? ScopedFolderDescriptor.components(path)) != nil else { throw OfflineCatalogError.invalidCatalog }
    }

    static func relativePath(of url: URL, in root: URL) throws -> String {
        let base = root.pathComponents
        let components = url.pathComponents
        guard components.starts(with: base) else { throw OfflineCatalogError.invalidSource }
        let relative = components.dropFirst(base.count).joined(separator: "/")
        try path(relative, allowsEmpty: true)
        return relative
    }
}
