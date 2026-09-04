//
//  DisabledNearbyTransferService.swift
//  FinallyExplorer
//

import Foundation

actor DisabledNearbyTransferService: NearbyTransferServicing {
    nonisolated let events: AsyncStream<NearbyTransferEvent>

    init() {
        events = AsyncStream { continuation in
            continuation.finish()
        }
    }

    func start() async {}
    func stop() async {}
    func send(_: [URL], to _: UUID) async {}
    func resolvePairing(sessionID _: UUID, accepted _: Bool) async {}

    func resolveOffer(
        sessionID _: UUID,
        decision _: NearbyTransferOfferDecision
    ) async {}

    func cancel(sessionID _: UUID) async {}
}
