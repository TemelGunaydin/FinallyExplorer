import Foundation

/// A persistent volume UUID, never a display name or a transient /Volumes path.
nonisolated struct OfflineCatalogVolume: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let rootURL: URL
}
