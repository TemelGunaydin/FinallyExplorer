//
//  NetworkNearbyTransferService.swift
//  FinallyExplorer
//

import Foundation
import Network

actor NetworkNearbyTransferService: NearbyTransferServicing {
    static let serviceType = "_finallyxfer._tcp"

    nonisolated let events: AsyncStream<NearbyTransferEvent>

    private nonisolated let eventContinuation: AsyncStream<NearbyTransferEvent>.Continuation
    private let identity: NearbyTransferIdentity
    private let manifestBuilder: NearbyTransferManifestBuilder
    private var browserTask: Task<Void, Never>?
    private var listenerTask: Task<Void, Never>?
    private var peers: [UUID: NearbyTransferPeer] = [:]
    private var endpoints: [UUID: Bonjour.Endpoint] = [:]
    private var sessions: [UUID: ActiveSession] = [:]
    private var lifecycleCleanup: LifecycleCleanup?
    private var isStarted = false
    private var outgoingPreparationToken: UUID?
    private var generation: UInt64 = 0

    init(
        identity: NearbyTransferIdentity = .current(),
        manifestBuilder: NearbyTransferManifestBuilder = NearbyTransferManifestBuilder()
    ) {
        self.identity = identity
        self.manifestBuilder = manifestBuilder
        let pair = AsyncStream<NearbyTransferEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        events = pair.stream
        eventContinuation = pair.continuation
    }

    deinit {
        browserTask?.cancel()
        listenerTask?.cancel()
        lifecycleCleanup?.task.cancel()
        for activeSession in sessions.values {
            activeSession.task.cancel()
        }
        eventContinuation.finish()
    }

    func start() async {
        while let cleanup = lifecycleCleanup {
            await cleanup.task.value
            if lifecycleCleanup?.id == cleanup.id {
                lifecycleCleanup = nil
            }
        }
        guard isStarted == false else { return }
        isStarted = true
        generation &+= 1
        let runGeneration = generation
        eventContinuation.yield(.availabilityChanged(isActive: true, message: nil))

        browserTask = Task { [weak self] in
            await self?.runBrowser(generation: runGeneration)
        }
        listenerTask = Task { [weak self] in
            await self?.runListener(generation: runGeneration)
        }
    }

    func stop() async {
        guard isStarted else {
            if let cleanup = lifecycleCleanup {
                await cleanup.task.value
                if lifecycleCleanup?.id == cleanup.id {
                    lifecycleCleanup = nil
                }
            }
            return
        }

        // Publish the stopped state before suspension so reentrant calls can never
        // observe the previous generation as active while teardown is in flight.
        isStarted = false
        generation &+= 1
        outgoingPreparationToken = nil

        let browserToStop = browserTask
        let listenerToStop = listenerTask
        let activeSessions = Array(sessions.values)
        browserTask = nil
        listenerTask = nil
        sessions.removeAll()
        peers.removeAll()
        endpoints.removeAll()
        eventContinuation.yield(.peersChanged([]))
        eventContinuation.yield(.availabilityChanged(isActive: false, message: nil))

        let cleanupID = UUID()
        let cleanupTask = Task {
            await withTaskGroup(of: Void.self) { group in
                for activeSession in activeSessions {
                    group.addTask {
                        await activeSession.session.requestCancellation()
                    }
                }
            }

            // Give every session a chance to send its authenticated cancellation
            // before cancelling the tasks that own the Network connections.
            for activeSession in activeSessions {
                activeSession.task.cancel()
            }
            browserToStop?.cancel()
            listenerToStop?.cancel()

            await browserToStop?.value
            await listenerToStop?.value
            for activeSession in activeSessions {
                await activeSession.task.value
            }
        }
        lifecycleCleanup = LifecycleCleanup(id: cleanupID, task: cleanupTask)
        await cleanupTask.value
        if lifecycleCleanup?.id == cleanupID {
            lifecycleCleanup = nil
        }
    }

    func send(_ sourceURLs: [URL], to peerID: UUID) async {
        guard isStarted,
              outgoingPreparationToken == nil,
              sessions.isEmpty else {
            eventContinuation.yield(.failed(
                sessionID: nil,
                message: NearbyTransferError.alreadyBusy.localizedDescription
            ))
            return
        }
        guard let endpoint = endpoints[peerID] else {
            eventContinuation.yield(.failed(
                sessionID: nil,
                message: NearbyTransferError.peerUnavailable.localizedDescription
            ))
            return
        }

        let preparationToken = UUID()
        outgoingPreparationToken = preparationToken
        let requestedGeneration = generation
        defer {
            if outgoingPreparationToken == preparationToken {
                outgoingPreparationToken = nil
            }
        }
        do {
            let package = try await manifestBuilder.build(from: sourceURLs)
            try Task.checkCancellation()
            guard isCurrentGeneration(requestedGeneration),
                  outgoingPreparationToken == preparationToken,
                  sessions.isEmpty else {
                throw NearbyTransferError.cancelled
            }
            let connection = NetworkConnection(to: endpoint) {
                TCP()
                    .noDelay(true)
                    .keepalive(idleTimeInSeconds: 15, count: 3, intervalInSeconds: 5)
            }
            let localSessionID = UUID()
            let session = NearbyTransferSession(
                id: localSessionID,
                role: .initiator(package: package),
                identity: identity,
                connection: NearbyTransferFramedConnection(connection: connection),
                eventSink: { [weak self] event in
                    await self?.publish(event, generation: requestedGeneration)
                }
            )
            let task = Task { [weak self, session] in
                await session.run()
                await self?.removeSession(
                    localSessionID,
                    generation: requestedGeneration
                )
            }
            sessions[localSessionID] = ActiveSession(
                session: session,
                task: task
            )
        } catch is CancellationError {
            return
        } catch NearbyTransferError.cancelled {
            return
        } catch {
            guard isCurrentGeneration(requestedGeneration),
                  outgoingPreparationToken == preparationToken else {
                return
            }
            eventContinuation.yield(.failed(sessionID: nil, message: error.localizedDescription))
        }
    }

    func resolvePairing(sessionID: UUID, accepted: Bool) async {
        guard let session = sessions[sessionID]?.session else { return }
        await session.resolvePairing(accepted: accepted)
    }

    func resolveOffer(
        sessionID: UUID,
        decision: NearbyTransferOfferDecision
    ) async {
        guard let session = sessions[sessionID]?.session else { return }
        await session.resolveOffer(decision)
    }

    func cancel(sessionID: UUID) async {
        guard let activeSession = sessions[sessionID] else { return }
        await activeSession.session.requestCancellation()
        activeSession.task.cancel()
    }

    private func runBrowser(generation runGeneration: UInt64) async {
        let browser = NetworkBrowser(
            for: .bonjour(Self.serviceType, includeTxtRecord: true)
        )
        browser.onStateUpdate { [weak self] _, state in
            Task { [weak self] in
                await self?.handleBrowserState(state, generation: runGeneration)
            }
        }

        do {
            try await browser.run { [weak self] discoveredEndpoints in
                guard let self else { return }
                await self.updatePeers(
                    from: discoveredEndpoints,
                    generation: runGeneration
                )
            }
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentGeneration(runGeneration) else { return }
            eventContinuation.yield(.availabilityChanged(
                isActive: false,
                message: error.localizedDescription
            ))
        }
    }

    private func runListener(generation runGeneration: UInt64) async {
        let txtRecord = NWTXTRecord([
            "id": identity.deviceID.uuidString.lowercased(),
            "v": String(NearbyTransferWire.protocolVersion),
        ])

        do {
            let listener = try NetworkListener(
                for: .bonjour(
                    name: identity.name,
                    type: Self.serviceType,
                    txtRecord: txtRecord
                )
            ) {
                TCP()
                    .noDelay(true)
                    .keepalive(idleTimeInSeconds: 15, count: 3, intervalInSeconds: 5)
            }
            _ = listener.newConnectionLimit(4)
            listener.onStateUpdate { [weak self] _, state in
                Task { [weak self] in
                    await self?.handleListenerState(state, generation: runGeneration)
                }
            }

            try await listener.run { [weak self] connection in
                guard let self else { return }
                await self.handleIncomingConnection(
                    connection,
                    generation: runGeneration
                )
            }
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentGeneration(runGeneration) else { return }
            eventContinuation.yield(.availabilityChanged(
                isActive: false,
                message: error.localizedDescription
            ))
        }
    }

    private func handleIncomingConnection(
        _ connection: NetworkConnection<TCP>,
        generation runGeneration: UInt64
    ) async {
        guard isCurrentGeneration(runGeneration),
              outgoingPreparationToken == nil,
              sessions.isEmpty else {
            return
        }

        let localSessionID = UUID()
        let session = NearbyTransferSession(
            id: localSessionID,
            role: .receiver,
            identity: identity,
            connection: NearbyTransferFramedConnection(connection: connection),
            eventSink: { [weak self] event in
                await self?.publish(event, generation: runGeneration)
            }
        )
        let task = Task { [session] in
            await session.run()
        }
        sessions[localSessionID] = ActiveSession(
            session: session,
            task: task
        )
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        sessions[localSessionID] = nil
    }

    private func handleBrowserState(
        _ state: NetworkBrowser<Bonjour>.State,
        generation runGeneration: UInt64
    ) {
        guard isCurrentGeneration(runGeneration) else { return }
        switch state {
        case let .waiting(error):
            eventContinuation.yield(.availabilityChanged(
                isActive: true,
                message: Self.friendlyNetworkMessage(for: error)
            ))
        case let .failed(error):
            eventContinuation.yield(.availabilityChanged(
                isActive: false,
                message: Self.friendlyNetworkMessage(for: error)
            ))
        case .ready:
            eventContinuation.yield(.availabilityChanged(
                isActive: true,
                message: nil
            ))
        case .setup, .cancelled:
            break
        @unknown default:
            break
        }
    }

    private func handleListenerState(
        _ state: NetworkListener<TCP>.State,
        generation runGeneration: UInt64
    ) {
        guard isCurrentGeneration(runGeneration) else { return }
        switch state {
        case let .waiting(error), let .failed(error):
            eventContinuation.yield(.availabilityChanged(
                isActive: false,
                message: Self.friendlyNetworkMessage(for: error)
            ))
        case .ready:
            eventContinuation.yield(.availabilityChanged(
                isActive: true,
                message: nil
            ))
        case .setup, .cancelled:
            break
        @unknown default:
            break
        }
    }

    private func updatePeers(
        from discoveredEndpoints: [Bonjour.Endpoint],
        generation runGeneration: UInt64
    ) {
        guard isCurrentGeneration(runGeneration) else { return }
        var updatedPeers: [UUID: NearbyTransferPeer] = [:]
        var updatedEndpoints: [UUID: Bonjour.Endpoint] = [:]

        for endpoint in discoveredEndpoints {
            let values = endpoint.txtRecord.dictionary
            guard values["v"] == String(NearbyTransferWire.protocolVersion),
                  let rawID = values["id"],
                  let peerID = UUID(uuidString: rawID),
                  peerID != identity.deviceID else {
                continue
            }
            updatedPeers[peerID] = NearbyTransferPeer(
                id: peerID,
                name: String(endpoint.name.prefix(80))
            )
            updatedEndpoints[peerID] = endpoint
        }

        peers = updatedPeers
        endpoints = updatedEndpoints
        eventContinuation.yield(.peersChanged(
            updatedPeers.values.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        ))
    }

    private func removeSession(_ id: UUID, generation runGeneration: UInt64) {
        guard isCurrentGeneration(runGeneration) else { return }
        sessions[id] = nil
    }

    private func publish(
        _ event: NearbyTransferEvent,
        generation runGeneration: UInt64
    ) {
        guard isCurrentGeneration(runGeneration) else { return }
        eventContinuation.yield(event)
    }

    private func isCurrentGeneration(_ runGeneration: UInt64) -> Bool {
        isStarted && generation == runGeneration
    }

    private static func friendlyNetworkMessage(for error: NWError) -> String {
        if case let .posix(code) = error, code == .EACCES {
            return "Allow Local Network access in System Settings to find nearby devices."
        }
        return "Nearby sharing is waiting for the local network."
    }

    private struct ActiveSession {
        let session: NearbyTransferSession
        let task: Task<Void, Never>
    }

    private struct LifecycleCleanup {
        let id: UUID
        let task: Task<Void, Never>
    }
}
