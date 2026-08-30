//
//  NearbyTransferPresentation.swift
//  FinallyExplorer
//

import Foundation

nonisolated enum NearbyTransferPresentation: Identifiable, Hashable, Sendable {
    case devicePicker
    case pairing(NearbyPairingPrompt)
    case incomingOffer(NearbyIncomingOffer)

    var id: String {
        switch self {
        case .devicePicker:
            "device-picker"
        case let .pairing(prompt):
            "pairing-\(prompt.id.uuidString)"
        case let .incomingOffer(offer):
            "offer-\(offer.id.uuidString)"
        }
    }
}
