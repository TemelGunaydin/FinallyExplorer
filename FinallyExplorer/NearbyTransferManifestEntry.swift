//
//  NearbyTransferManifestEntry.swift
//  FinallyExplorer
//

import Foundation

nonisolated struct NearbyTransferManifestEntry: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case directory
        case file
    }

    let id: UUID
    let relativePathComponents: [String]
    let kind: Kind
    let byteCount: UInt64
    let sha256: Data?
    let modificationDate: Date?

    var displayName: String {
        relativePathComponents.last ?? "Item"
    }
}
