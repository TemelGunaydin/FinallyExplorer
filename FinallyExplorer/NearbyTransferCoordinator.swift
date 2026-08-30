//
//  NearbyTransferCoordinator.swift
//  FinallyExplorer
//

import Foundation
import Observation

@MainActor
@Observable
final class NearbyTransferCoordinator {
    private(set) var peers: [NearbyTransferPeer] = []
    private(set) var isActive = false
    private(set) var statusMessage: String?
    private(set) var pendingSourceURLs: [URL] = []
    private(set) var progress: NearbyTransferProgress?
    private(set) var isPreparingTransfer = false
    private(set) var confirmedPairingSessionIDs: Set<UUID> = []
    private(set) var lastCompletion: NearbyTransferCompletion?
    var presentation: NearbyTransferPresentation?
    var isErrorPresented = false
    private(set) var errorMessage = ""

    @ObservationIgnored private let service: any NearbyTransferServicing
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var lifecycleTask: Task<Void, Never>?
    @ObservationIgnored private var outgoingPreparationTask: Task<Void, Never>?
    @ObservationIgnored private var outgoingPreparationID: UUID?
    @ObservationIgnored private var locallyCancelledSessionIDs: Set<UUID> = []
    @ObservationIgnored private var hasStarted = false

    init(service: any NearbyTransferServicing = NetworkNearbyTransferService()) {
        self.service = service
    }

    deinit {
        eventTask?.cancel()
        outgoingPreparationTask?.cancel()
        lifecycleTask?.cancel()
        let lifecycleTask = lifecycleTask
        let service = service
        Task {
            if let lifecycleTask {
                await lifecycleTask.value
            }
            await service.stop()
        }
    }

    func prepareToSend(_ urls: [URL]) {
        pendingSourceURLs = uniqueURLs(urls)
        startIfNeeded()
        presentation = .devicePicker
    }

    func select(_ peer: NearbyTransferPeer) {
        guard pendingSourceURLs.isEmpty == false, isPreparingTransfer == false else {
            return
        }
        let sources = pendingSourceURLs
        let preparationID = UUID()
        outgoingPreparationID = preparationID
        isPreparingTransfer = true
        statusMessage = "Preparing items securely…"
        outgoingPreparationTask = Task { [weak self, service] in
            await service.send(sources, to: peer.id)
            guard Task.isCancelled == false else { return }
            self?.finishPreparationTask(id: preparationID)
        }
    }

    func confirmPairing(_ prompt: NearbyPairingPrompt) {
        confirmedPairingSessionIDs.insert(prompt.id)
        Task { await service.resolvePairing(sessionID: prompt.id, accepted: true) }
    }

    func declinePairing(_ prompt: NearbyPairingPrompt) {
        presentation = nil
        confirmedPairingSessionIDs.remove(prompt.id)
        pendingSourceURLs = []
        isPreparingTransfer = false
        statusMessage = nil
        Task { await service.resolvePairing(sessionID: prompt.id, accepted: false) }
    }

    func accept(
        _ offer: NearbyIncomingOffer,
        into destinationDirectoryURL: URL
    ) {
        presentation = nil
        Task {
            await service.resolveOffer(
                sessionID: offer.id,
                decision: .accept(
                    destinationDirectoryURL: destinationDirectoryURL.standardizedFileURL
                )
            )
        }
    }

    func decline(_ offer: NearbyIncomingOffer) {
        presentation = nil
        confirmedPairingSessionIDs.remove(offer.id)
        Task {
            await service.resolveOffer(sessionID: offer.id, decision: .reject)
        }
    }

    func cancelActiveTransfer() {
        guard let sessionID = progress?.id else { return }
        locallyCancelledSessionIDs.insert(sessionID)
        confirmedPairingSessionIDs.remove(sessionID)
        progress = nil
        pendingSourceURLs = []
        isPreparingTransfer = false
        statusMessage = nil
        Task { await service.cancel(sessionID: sessionID) }
    }

    func stopSharing() {
        outgoingPreparationTask?.cancel()
        outgoingPreparationTask = nil
        outgoingPreparationID = nil
        presentation = nil
        progress = nil
        pendingSourceURLs = []
        isPreparingTransfer = false
        confirmedPairingSessionIDs = []
        locallyCancelledSessionIDs = []
        peers = []
        isActive = false
        statusMessage = nil
        hasStarted = false
        enqueueLifecycle(.stop)
    }

    private func startIfNeeded() {
        guard hasStarted == false else { return }
        hasStarted = true
        startEventConsumerIfNeeded()
        enqueueLifecycle(.start)
    }

    private func startEventConsumerIfNeeded() {
        guard eventTask == nil else { return }
        eventTask = Task { [weak self, service] in
            for await event in service.events {
                guard Task.isCancelled == false else { return }
                self?.handle(event)
            }
        }
    }

    private func enqueueLifecycle(_ command: ServiceLifecycleCommand) {
        let predecessor = lifecycleTask
        let service = service
        lifecycleTask = Task {
            if let predecessor {
                await predecessor.value
            }
            guard Task.isCancelled == false else { return }
            switch command {
            case .start:
                await service.start()
            case .stop:
                await service.stop()
            }
        }
    }

    private func handle(_ event: NearbyTransferEvent) {
        guard hasStarted else {
            if case let .availabilityChanged(isActive, _) = event, isActive == false {
                self.isActive = false
            }
            return
        }

        switch event {
        case let .peersChanged(peers):
            self.peers = peers

        case let .availabilityChanged(isActive, message):
            self.isActive = isActive
            statusMessage = message

        case let .pairingRequired(prompt):
            guard locallyCancelledSessionIDs.contains(prompt.id) == false else { return }
            statusMessage = nil
            isPreparingTransfer = false
            presentation = .pairing(prompt)

        case let .offerReceived(offer):
            guard locallyCancelledSessionIDs.contains(offer.id) == false else { return }
            statusMessage = nil
            presentation = .incomingOffer(offer)

        case let .progress(progress):
            guard locallyCancelledSessionIDs.contains(progress.id) == false else { return }
            presentation = nil
            self.progress = progress

        case let .completed(completion):
            presentation = nil
            cleanSessionState(completion.id)
            lastCompletion = completion

        case let .cancelled(sessionID):
            cleanSessionState(sessionID)

        case let .failed(sessionID, message):
            if let sessionID {
                if locallyCancelledSessionIDs.contains(sessionID) {
                    cleanSessionState(sessionID)
                    return
                }
                cleanSessionState(sessionID)
            } else {
                presentation = nil
                pendingSourceURLs = []
            }
            statusMessage = nil
            isPreparingTransfer = false
            errorMessage = message
            isErrorPresented = true
        }
    }

    private func finishPreparationTask(id: UUID) {
        guard outgoingPreparationID == id else { return }
        outgoingPreparationTask = nil
        outgoingPreparationID = nil
    }

    private func cleanSessionState(_ sessionID: UUID) {
        locallyCancelledSessionIDs.remove(sessionID)
        confirmedPairingSessionIDs.remove(sessionID)
        pendingSourceURLs = []
        isPreparingTransfer = false
        statusMessage = nil

        if progress?.id == sessionID {
            progress = nil
        }
        switch presentation {
        case let .pairing(prompt) where prompt.id == sessionID:
            presentation = nil
        case let .incomingOffer(offer) where offer.id == sessionID:
            presentation = nil
        default:
            break
        }
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<URL> = []
        return urls.compactMap { url in
            let standardized = url.standardizedFileURL
            return seen.insert(standardized).inserted ? standardized : nil
        }
    }

    private enum ServiceLifecycleCommand: Sendable {
        case start
        case stop
    }
}
