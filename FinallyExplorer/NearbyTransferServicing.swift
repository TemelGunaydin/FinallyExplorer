//
//  NearbyTransferServicing.swift
//  FinallyExplorer
//

import Foundation

nonisolated protocol NearbyTransferServicing: Sendable {
    var events: AsyncStream<NearbyTransferEvent> { get }

    func start() async
    func stop() async
    func send(_ sourceURLs: [URL], to peerID: UUID) async
    func resolvePairing(sessionID: UUID, accepted: Bool) async
    func resolveOffer(
        sessionID: UUID,
        decision: NearbyTransferOfferDecision
    ) async
    func cancel(sessionID: UUID) async
}
