//
//  NearbyTransferCoordinatorTests.swift
//  FinallyExplorerTests
//

import Foundation
import Testing
@testable import FinallyExplorer

extension Tag {
    @Tag static var networking: Self
}

@MainActor
@Suite("Nearby Transfer Coordinator", .tags(.networking))
struct NearbyTransferCoordinatorTests {
    @Test("Opening the picker starts discovery and publishes nearby peers")
    func pickerStartsDiscoveryAndPublishesPeers() async {
        let service = FakeNearbyTransferService()
        let coordinator = NearbyTransferCoordinator(service: service)
        let sourceURL = URL(fileURLWithPath: "/tmp/nearby-source.txt")
        let peer = NearbyTransferPeer(id: UUID(), name: "Living Room Mac")

        coordinator.prepareToSend([sourceURL])

        #expect(coordinator.presentation == .devicePicker)
        let didStart = await eventually {
            await service.startCallCount == 1
        }
        #expect(didStart, "Opening the picker should start nearby discovery once.")

        await service.emit(.availabilityChanged(isActive: true, message: nil))
        await service.emit(.peersChanged([peer]))

        let didPublishPeer = await eventually {
            coordinator.isActive && coordinator.peers == [peer]
        }
        #expect(didPublishPeer, "Discovered peers should become visible in the picker.")
    }

    @Test("Rapid stop and restart serializes lifecycle operations")
    func stopAndRestartSerializesLifecycleOperations() async throws {
        let service = FakeNearbyTransferService(suspendLifecycleOperations: true)
        defer {
            Task { await service.disableLifecycleSuspension() }
        }
        let coordinator = NearbyTransferCoordinator(service: service)

        coordinator.prepareToSend([URL(fileURLWithPath: "/tmp/first.txt")])
        let firstStartBegan = await eventually {
            await service.lifecycleOperations == [.start]
        }
        try #require(firstStartBegan, "The first start operation should reach the service.")

        coordinator.stopSharing()
        coordinator.prepareToSend([URL(fileURLWithPath: "/tmp/second.txt")])

        let operationsWhileStartIsSuspended = await service.lifecycleOperations
        #expect(
            operationsWhileStartIsSuspended == [.start],
            "Stop and restart must wait while the first start is suspended."
        )
        let didReleaseFirstStart = await service.releaseNextLifecycleOperation()
        try #require(didReleaseFirstStart)

        let stopBegan = await eventually {
            await service.lifecycleOperations == [.start, .stop]
        }
        try #require(stopBegan, "Stop should execute immediately after the first start completes.")
        let didReleaseStop = await service.releaseNextLifecycleOperation()
        try #require(didReleaseStop)

        let secondStartBegan = await eventually {
            await service.lifecycleOperations == [.start, .stop, .start]
        }
        try #require(
            secondStartBegan,
            "The replacement start should execute only after stop completes."
        )
        let didReleaseSecondStart = await service.releaseNextLifecycleOperation()
        try #require(didReleaseSecondStart)
        await service.disableLifecycleSuspension()

        let finalOperations = await service.lifecycleOperations
        #expect(finalOperations == [.start, .stop, .start])
    }

    @Test("Selecting a peer sends the normalized unique sources to that peer")
    func selectingPeerUsesPreparedURLsAndPeerID() async throws {
        let service = FakeNearbyTransferService()
        let coordinator = NearbyTransferCoordinator(service: service)
        let peer = NearbyTransferPeer(id: UUID(), name: "Studio Mac")
        let sourceURL = URL(fileURLWithPath: "/tmp/nearby-folder/item.txt")
        let equivalentURL = URL(fileURLWithPath: "/tmp/nearby-folder/../nearby-folder/item.txt")

        coordinator.prepareToSend([sourceURL, equivalentURL])
        coordinator.select(peer)

        let recordedCall = await eventuallyValue {
            await service.sendCalls.first
        }
        let call = try #require(recordedCall)
        #expect(call.peerID == peer.id)
        #expect(call.sourceURLs == [sourceURL.standardizedFileURL])
        #expect(coordinator.statusMessage == "Preparing items securely…")
    }

    @Test("Pairing confirmation is forwarded to the service")
    func pairingConfirmationIsForwarded() async {
        let service = FakeNearbyTransferService()
        let coordinator = NearbyTransferCoordinator(service: service)
        let prompt = NearbyPairingPrompt(
            id: UUID(),
            peerName: "Kitchen Mac",
            code: "482193",
            direction: .sending
        )
        coordinator.prepareToSend([URL(fileURLWithPath: "/tmp/photo.jpg")])
        await service.emit(.pairingRequired(prompt))
        _ = await eventually {
            coordinator.presentation == .pairing(prompt)
        }

        coordinator.confirmPairing(prompt)

        let wasForwarded = await eventually {
            await service.pairingResolutions.contains(
                PairingResolution(sessionID: prompt.id, accepted: true)
            )
        }
        #expect(wasForwarded)
        #expect(coordinator.confirmedPairingSessionIDs.contains(prompt.id))
    }

    @Test("Pairing rejection dismisses the prompt and is forwarded to the service")
    func pairingRejectionIsForwarded() async {
        let service = FakeNearbyTransferService()
        let coordinator = NearbyTransferCoordinator(service: service)
        let prompt = NearbyPairingPrompt(
            id: UUID(),
            peerName: "Office Mac",
            code: "917304",
            direction: .receiving
        )
        coordinator.prepareToSend([URL(fileURLWithPath: "/tmp/document.pdf")])
        await service.emit(.pairingRequired(prompt))
        _ = await eventually {
            coordinator.presentation == .pairing(prompt)
        }

        coordinator.declinePairing(prompt)

        let wasForwarded = await eventually {
            await service.pairingResolutions.contains(
                PairingResolution(sessionID: prompt.id, accepted: false)
            )
        }
        #expect(wasForwarded)
        #expect(coordinator.presentation == nil)
        #expect(coordinator.confirmedPairingSessionIDs.contains(prompt.id) == false)
    }

    @Test("Accepting an offer forwards a normalized destination snapshot")
    func acceptingOfferForwardsDestinationSnapshot() async throws {
        let service = FakeNearbyTransferService()
        let coordinator = NearbyTransferCoordinator(service: service)
        let offer = NearbyIncomingOffer(
            id: UUID(),
            peerName: "Bedroom Mac",
            itemNames: ["Archive"],
            itemCount: 1,
            totalByteCount: 512
        )
        let destinationURL = URL(
            fileURLWithPath: "/tmp/nearby-destination/../nearby-destination"
        )
        coordinator.prepareToSend([URL(fileURLWithPath: "/tmp/bootstrap")])
        await service.emit(.offerReceived(offer))
        _ = await eventually {
            coordinator.presentation == .incomingOffer(offer)
        }

        coordinator.accept(offer, into: destinationURL)

        let recordedResolution = await eventuallyValue {
            await service.offerResolutions.first
        }
        let resolution = try #require(recordedResolution)
        #expect(resolution.sessionID == offer.id)
        #expect(resolution.accepted)
        #expect(resolution.destinationDirectoryURL == destinationURL.standardizedFileURL)
        #expect(coordinator.presentation == nil)
    }

    @Test("Canceling progress clears the activity and cancels the matching session")
    func progressCancellationUsesActiveSessionID() async {
        let service = FakeNearbyTransferService()
        let coordinator = NearbyTransferCoordinator(service: service)
        let progress = NearbyTransferProgress(
            id: UUID(),
            peerName: "Laptop",
            direction: .sending,
            completedByteCount: 128,
            totalByteCount: 1_024
        )
        coordinator.prepareToSend([URL(fileURLWithPath: "/tmp/video.mkv")])
        await service.emit(.progress(progress))
        _ = await eventually {
            coordinator.progress == progress
        }

        coordinator.cancelActiveTransfer()

        let wasCancelled = await eventually {
            await service.cancelledSessionIDs.contains(progress.id)
        }
        #expect(wasCancelled)
        #expect(coordinator.progress == nil)
    }

    @Test("Local cancellation ignores late progress and completes without an error")
    func localCancellationIgnoresLateProgressAndCleansState() async {
        let service = FakeNearbyTransferService()
        let coordinator = NearbyTransferCoordinator(service: service)
        let sessionID = UUID()
        let prompt = NearbyPairingPrompt(
            id: sessionID,
            peerName: "Portable Mac",
            code: "481516",
            direction: .sending
        )
        let initialProgress = NearbyTransferProgress(
            id: sessionID,
            peerName: prompt.peerName,
            direction: .sending,
            completedByteCount: 64,
            totalByteCount: 1_024
        )
        let lateProgress = NearbyTransferProgress(
            id: sessionID,
            peerName: prompt.peerName,
            direction: .sending,
            completedByteCount: 128,
            totalByteCount: 1_024
        )
        coordinator.prepareToSend([URL(fileURLWithPath: "/tmp/cancel-me.bin")])
        await service.emit(.pairingRequired(prompt))
        _ = await eventually { coordinator.presentation == .pairing(prompt) }
        coordinator.confirmPairing(prompt)
        await service.emit(.progress(initialProgress))
        _ = await eventually { coordinator.progress == initialProgress }

        coordinator.cancelActiveTransfer()
        _ = await eventually {
            await service.cancelledSessionIDs.contains(sessionID)
        }
        await service.emit(.progress(lateProgress))
        await service.emit(.availabilityChanged(isActive: true, message: "late-progress-barrier"))
        _ = await eventually {
            coordinator.statusMessage == "late-progress-barrier"
        }

        #expect(coordinator.progress == nil, "Late progress must not resurrect a cancelled transfer.")

        let sentinelPeer = NearbyTransferPeer(id: UUID(), name: "Event Barrier")
        await service.emit(.cancelled(sessionID: sessionID))
        await service.emit(.peersChanged([sentinelPeer]))
        _ = await eventually { coordinator.peers == [sentinelPeer] }

        #expect(coordinator.presentation == nil)
        #expect(coordinator.progress == nil)
        #expect(coordinator.pendingSourceURLs.isEmpty)
        #expect(coordinator.confirmedPairingSessionIDs.contains(sessionID) == false)
        #expect(coordinator.isPreparingTransfer == false)
        #expect(coordinator.isErrorPresented == false)
        #expect(coordinator.errorMessage.isEmpty)
    }

    @Test("Completion clears transient state and retains the completion summary")
    func completionCleansTransientState() async {
        let service = FakeNearbyTransferService()
        let coordinator = NearbyTransferCoordinator(service: service)
        let sessionID = UUID()
        let prompt = NearbyPairingPrompt(
            id: sessionID,
            peerName: "Work Mac",
            code: "203844",
            direction: .sending
        )
        let progress = NearbyTransferProgress(
            id: sessionID,
            peerName: prompt.peerName,
            direction: .sending,
            completedByteCount: 100,
            totalByteCount: 100
        )
        let completion = NearbyTransferCompletion(
            id: sessionID,
            peerName: prompt.peerName,
            direction: .sent,
            itemCount: 2,
            destinationDirectoryURL: nil
        )
        coordinator.prepareToSend([URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/b")])
        await service.emit(.pairingRequired(prompt))
        _ = await eventually { coordinator.presentation == .pairing(prompt) }
        coordinator.confirmPairing(prompt)
        await service.emit(.progress(progress))
        _ = await eventually { coordinator.progress == progress }

        await service.emit(.completed(completion))

        let wasCleaned = await eventually {
            coordinator.lastCompletion == completion
                && coordinator.presentation == nil
                && coordinator.progress == nil
                && coordinator.pendingSourceURLs.isEmpty
                && coordinator.confirmedPairingSessionIDs.contains(sessionID) == false
        }
        #expect(wasCleaned)
    }

    @Test("A session failure clears its UI state and presents the error")
    func failureCleansSessionStateAndPresentsError() async {
        let service = FakeNearbyTransferService()
        let coordinator = NearbyTransferCoordinator(service: service)
        let sessionID = UUID()
        let prompt = NearbyPairingPrompt(
            id: sessionID,
            peerName: "Travel Mac",
            code: "558102",
            direction: .sending
        )
        let progress = NearbyTransferProgress(
            id: sessionID,
            peerName: prompt.peerName,
            direction: .sending,
            completedByteCount: 32,
            totalByteCount: 64
        )
        coordinator.prepareToSend([URL(fileURLWithPath: "/tmp/archive.zip")])
        await service.emit(.pairingRequired(prompt))
        _ = await eventually { coordinator.presentation == .pairing(prompt) }
        coordinator.confirmPairing(prompt)
        await service.emit(.progress(progress))
        _ = await eventually { coordinator.progress == progress }

        await service.emit(.failed(sessionID: sessionID, message: "Connection interrupted"))

        let wasCleaned = await eventually {
            coordinator.presentation == nil
                && coordinator.progress == nil
                && coordinator.statusMessage == nil
                && coordinator.confirmedPairingSessionIDs.contains(sessionID) == false
                && coordinator.isErrorPresented
                && coordinator.errorMessage == "Connection interrupted"
        }
        #expect(wasCleaned)
    }

    private func eventually(
        _ condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))

        repeat {
            if await condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        } while clock.now < deadline

        return await condition()
    }

    private func eventuallyValue<Value: Sendable>(
        _ value: @escaping @MainActor () async -> Value?
    ) async -> Value? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))

        repeat {
            if let value = await value() {
                return value
            }
            try? await Task.sleep(for: .milliseconds(10))
        } while clock.now < deadline

        return await value()
    }
}

private actor FakeNearbyTransferService: NearbyTransferServicing {
    nonisolated let events: AsyncStream<NearbyTransferEvent>

    private let continuation: AsyncStream<NearbyTransferEvent>.Continuation
    private var shouldSuspendLifecycleOperations: Bool
    private var lifecycleWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var lifecycleOperations: [RecordedLifecycleOperation] = []
    private(set) var sendCalls: [RecordedSend] = []
    private(set) var pairingResolutions: [PairingResolution] = []
    private(set) var offerResolutions: [OfferResolution] = []
    private(set) var cancelledSessionIDs: [UUID] = []

    init(suspendLifecycleOperations: Bool = false) {
        let stream = AsyncStream<NearbyTransferEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(32)
        )
        events = stream.stream
        continuation = stream.continuation
        shouldSuspendLifecycleOperations = suspendLifecycleOperations
    }

    func start() async {
        startCallCount += 1
        lifecycleOperations.append(.start)
        await suspendLifecycleOperationIfNeeded()
    }

    func stop() async {
        stopCallCount += 1
        lifecycleOperations.append(.stop)
        await suspendLifecycleOperationIfNeeded()
    }

    func send(_ sourceURLs: [URL], to peerID: UUID) async {
        sendCalls.append(RecordedSend(sourceURLs: sourceURLs, peerID: peerID))
    }

    func resolvePairing(sessionID: UUID, accepted: Bool) async {
        pairingResolutions.append(
            PairingResolution(sessionID: sessionID, accepted: accepted)
        )
    }

    func resolveOffer(
        sessionID: UUID,
        decision: NearbyTransferOfferDecision
    ) async {
        switch decision {
        case let .accept(destinationDirectoryURL):
            offerResolutions.append(
                OfferResolution(
                    sessionID: sessionID,
                    accepted: true,
                    destinationDirectoryURL: destinationDirectoryURL
                )
            )
        case .reject:
            offerResolutions.append(
                OfferResolution(
                    sessionID: sessionID,
                    accepted: false,
                    destinationDirectoryURL: nil
                )
            )
        }
    }

    func cancel(sessionID: UUID) async {
        cancelledSessionIDs.append(sessionID)
    }

    func emit(_ event: NearbyTransferEvent) {
        continuation.yield(event)
    }

    func releaseNextLifecycleOperation() -> Bool {
        guard lifecycleWaiters.isEmpty == false else { return false }
        lifecycleWaiters.removeFirst().resume()
        return true
    }

    func disableLifecycleSuspension() {
        shouldSuspendLifecycleOperations = false
        let waiters = lifecycleWaiters
        lifecycleWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func suspendLifecycleOperationIfNeeded() async {
        guard shouldSuspendLifecycleOperations else { return }
        await withCheckedContinuation { continuation in
            lifecycleWaiters.append(continuation)
        }
    }
}

private enum RecordedLifecycleOperation: Equatable, Sendable {
    case start
    case stop
}

private struct RecordedSend: Equatable, Sendable {
    let sourceURLs: [URL]
    let peerID: UUID
}

private struct PairingResolution: Equatable, Sendable {
    let sessionID: UUID
    let accepted: Bool
}

private struct OfferResolution: Equatable, Sendable {
    let sessionID: UUID
    let accepted: Bool
    let destinationDirectoryURL: URL?
}
