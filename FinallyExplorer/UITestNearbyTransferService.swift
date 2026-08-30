//
//  UITestNearbyTransferService.swift
//  FinallyExplorer
//

import Foundation

actor UITestNearbyTransferService: NearbyTransferServicing {
    static let peerID = UUID(uuidString: "8A1660D1-44D5-4B14-BB7B-A4C73916C671")!

    nonisolated let events: AsyncStream<NearbyTransferEvent>

    private nonisolated let continuation: AsyncStream<NearbyTransferEvent>.Continuation
    private let peerName: String
    private var activeSessionID: UUID?
    private var activeItemCount = 0

    init(peerName: String) {
        self.peerName = peerName
        let pair = AsyncStream<NearbyTransferEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(16)
        )
        events = pair.stream
        continuation = pair.continuation
    }

    deinit {
        continuation.finish()
    }

    func start() async {
        continuation.yield(.availabilityChanged(isActive: true, message: nil))
        continuation.yield(.peersChanged([
            NearbyTransferPeer(id: Self.peerID, name: peerName),
        ]))
    }

    func stop() async {
        continuation.yield(.peersChanged([]))
        continuation.yield(.availabilityChanged(isActive: false, message: nil))
    }

    func send(_ sourceURLs: [URL], to peerID: UUID) async {
        guard peerID == Self.peerID, sourceURLs.isEmpty == false else {
            continuation.yield(.failed(
                sessionID: nil,
                message: NearbyTransferError.peerUnavailable.localizedDescription
            ))
            return
        }
        let sessionID = UUID()
        activeSessionID = sessionID
        activeItemCount = sourceURLs.count
        continuation.yield(.pairingRequired(NearbyPairingPrompt(
            id: sessionID,
            peerName: peerName,
            code: "48276195",
            direction: .sending
        )))
    }

    func resolvePairing(sessionID: UUID, accepted: Bool) async {
        guard sessionID == activeSessionID else { return }
        guard accepted else {
            continuation.yield(.cancelled(sessionID: sessionID))
            activeSessionID = nil
            return
        }

        continuation.yield(.progress(NearbyTransferProgress(
            id: sessionID,
            peerName: peerName,
            direction: .sending,
            completedByteCount: 1,
            totalByteCount: 1
        )))
        await Task.yield()
        continuation.yield(.completed(NearbyTransferCompletion(
            id: sessionID,
            peerName: peerName,
            direction: .sent,
            itemCount: activeItemCount,
            destinationDirectoryURL: nil
        )))
        activeSessionID = nil
    }

    func resolveOffer(
        sessionID: UUID,
        decision: NearbyTransferOfferDecision
    ) async {}

    func cancel(sessionID: UUID) async {
        guard sessionID == activeSessionID else { return }
        continuation.yield(.cancelled(sessionID: sessionID))
        activeSessionID = nil
    }
}
