//
//  NearbyTransferPeer.swift
//  FinallyExplorer
//

import Foundation

nonisolated struct NearbyTransferPeer: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
}
