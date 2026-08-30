//
//  NearbyTransferManifest.swift
//  FinallyExplorer
//

import Foundation

nonisolated struct NearbyTransferManifest: Codable, Hashable, Sendable {
    static let maximumEntryCount = 20_000
    static let maximumDepth = 64
    static let maximumTotalByteCount: UInt64 = 4 * 1_024 * 1_024 * 1_024 * 1_024
    static let maximumEncodedByteCount = 768 * 1_024

    let transferID: UUID
    let entries: [NearbyTransferManifestEntry]
    let totalByteCount: UInt64

    var topLevelNames: [String] {
        entries
            .filter { $0.relativePathComponents.count == 1 }
            .map(\.displayName)
    }

    var itemCount: Int {
        topLevelNames.count
    }
}
