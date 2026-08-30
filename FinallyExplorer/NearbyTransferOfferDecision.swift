//
//  NearbyTransferOfferDecision.swift
//  FinallyExplorer
//

import Foundation

nonisolated enum NearbyTransferOfferDecision: Sendable {
    case accept(destinationDirectoryURL: URL)
    case reject
}
