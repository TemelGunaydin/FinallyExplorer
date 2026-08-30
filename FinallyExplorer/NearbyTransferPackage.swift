//
//  NearbyTransferPackage.swift
//  FinallyExplorer
//

import Foundation

nonisolated struct NearbyTransferPackage: Sendable {
    let manifest: NearbyTransferManifest
    let sourceURLsByEntryID: [UUID: URL]
}
