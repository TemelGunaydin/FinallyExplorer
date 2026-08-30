//
//  NearbyTransferEvent.swift
//  FinallyExplorer
//

import Foundation

nonisolated enum NearbyTransferEvent: Sendable {
    case peersChanged([NearbyTransferPeer])
    case availabilityChanged(isActive: Bool, message: String?)
    case pairingRequired(NearbyPairingPrompt)
    case offerReceived(NearbyIncomingOffer)
    case progress(NearbyTransferProgress)
    case completed(NearbyTransferCompletion)
    case cancelled(sessionID: UUID)
    case failed(sessionID: UUID?, message: String)
}

nonisolated struct NearbyPairingPrompt: Identifiable, Hashable, Sendable {
    enum Direction: Hashable, Sendable {
        case sending
        case receiving
    }

    let id: UUID
    let peerName: String
    let code: String
    let direction: Direction
}

nonisolated struct NearbyIncomingOffer: Identifiable, Hashable, Sendable {
    let id: UUID
    let peerName: String
    let itemNames: [String]
    let itemCount: Int
    let totalByteCount: UInt64
}

nonisolated struct NearbyTransferProgress: Identifiable, Hashable, Sendable {
    enum Direction: Hashable, Sendable {
        case sending
        case receiving
    }

    let id: UUID
    let peerName: String
    let direction: Direction
    let completedByteCount: UInt64
    let totalByteCount: UInt64

    var fractionCompleted: Double {
        guard totalByteCount > 0 else { return completedByteCount > 0 ? 1 : 0 }
        return min(1, Double(completedByteCount) / Double(totalByteCount))
    }
}

nonisolated struct NearbyTransferCompletion: Identifiable, Hashable, Sendable {
    enum Direction: Hashable, Sendable {
        case sent
        case received
    }

    let id: UUID
    let peerName: String
    let direction: Direction
    let itemCount: Int
    let destinationDirectoryURL: URL?
}
