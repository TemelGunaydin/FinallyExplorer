//
//  NearbyTransferSession.swift
//  FinallyExplorer
//

import CryptoKit
import Foundation

actor NearbyTransferSession {
    enum Role: Sendable {
        case initiator(package: NearbyTransferPackage)
        case receiver
    }

    typealias EventSink = @Sendable (NearbyTransferEvent) async -> Void

    let id: UUID

    private let role: Role
    private let identity: NearbyTransferIdentity
    private let connection: NearbyTransferFramedConnection
    private let eventSink: EventSink
    private let pairingDecision = NearbyDecisionGate<Bool>()
    private let offerDecision = NearbyDecisionGate<NearbyTransferOfferDecision>()
    private var cryptor: NearbyTransferCryptor?
    private var receiver: NearbyTransferReceiver?
    private var peerName = "Nearby Mac"
    private var wireSessionID: UUID?
    private var didReachTerminalState = false
    private var didEndLocally = false
    private var didSendCancellation = false
    private var lastProgressEmissionInstant: ContinuousClock.Instant?
    private var lastProgressByteCount: UInt64 = 0

    init(
        id: UUID,
        role: Role,
        identity: NearbyTransferIdentity,
        connection: NearbyTransferFramedConnection,
        eventSink: @escaping EventSink
    ) {
        self.id = id
        self.role = role
        self.identity = identity
        self.connection = connection
        self.eventSink = eventSink
    }

    func run() async {
        do {
            switch role {
            case let .initiator(package):
                try await runInitiator(package: package)
            case .receiver:
                try await runReceiver()
            }
        } catch is CancellationError {
            await finishCancellation()
        } catch NearbyTransferError.cancelled {
            await finishCancellation()
        } catch NearbyTransferError.rejected {
            receiver?.cancel()
            if didEndLocally {
                await emitCancellation()
            } else {
                await emitFailure(NearbyTransferError.rejected)
            }
        } catch {
            receiver?.cancel()
            if didEndLocally {
                await emitCancellation()
            } else {
                await sendFailureIfPossible(error)
                await emitFailure(error)
            }
        }
        pairingDecision.cancel()
        offerDecision.cancel()
    }

    func resolvePairing(accepted: Bool) {
        if accepted == false { didEndLocally = true }
        pairingDecision.resolve(accepted)
    }

    func resolveOffer(_ decision: NearbyTransferOfferDecision) {
        if case .reject = decision { didEndLocally = true }
        offerDecision.resolve(decision)
    }

    func requestCancellation() async {
        didEndLocally = true
        pairingDecision.resolve(false)
        offerDecision.resolve(.reject)
        receiver?.cancel()
        await emitCancellation()
        scheduleCancellationIfPossible()
    }

    private func runInitiator(package: NearbyTransferPackage) async throws {
        let handshake = try NearbyTransferHandshake(identity: identity)
        let sessionID = package.manifest.transferID
        wireSessionID = sessionID

        let localCommit = NearbyTransferWire.HandshakeCommit(
            sessionID: sessionID,
            commitment: handshake.commitment(sessionID: sessionID, role: .initiator)
        )
        try await sendPublic(localCommit, type: .handshakeCommit)

        let remoteCommit: NearbyTransferWire.HandshakeCommit = try await receivePublic(
            NearbyTransferWire.HandshakeCommit.self,
            expectedType: .handshakeCommit
        )
        guard remoteCommit.sessionID == sessionID,
              remoteCommit.commitment.count == 32 else {
            throw NearbyTransferError.protocolViolation("session mismatch")
        }

        try await sendPublic(handshake.reveal, type: .handshakeReveal)
        let remoteReveal: NearbyTransferWire.HandshakeReveal = try await receivePublic(
            NearbyTransferWire.HandshakeReveal.self,
            expectedType: .handshakeReveal
        )
        try NearbyTransferHandshake.verify(
            remoteCommit.commitment,
            reveal: remoteReveal,
            sessionID: sessionID,
            role: .receiver
        )
        peerName = remoteReveal.deviceName
        cryptor = try NearbyTransferCryptor(
            handshake: handshake,
            remoteReveal: remoteReveal,
            initiatorReveal: handshake.reveal,
            receiverReveal: remoteReveal,
            sessionID: sessionID,
            isInitiator: true
        )

        try await performPairing(direction: .sending)

        let manifestData = try NearbyTransferWire.encode(package.manifest)
        guard manifestData.count <= NearbyTransferManifest.maximumEncodedByteCount else {
            throw NearbyTransferError.invalidSource("the file list is too large")
        }
        try await sendSecure(manifestData, type: .manifest)

        let decisionData = try await receiveSecure(expectedType: .transferDecision)
        let decision = try NearbyTransferWire.decode(
            NearbyTransferWire.TransferDecision.self,
            from: decisionData
        )
        guard decision.accepted else {
            throw NearbyTransferError.rejected
        }

        await emitProgress(
            direction: .sending,
            completedByteCount: 0,
            totalByteCount: package.manifest.totalByteCount
        )
        var sentByteCount: UInt64 = 0
        for entry in package.manifest.entries where entry.kind == .file {
            try Task.checkCancellation()
            guard let sourceURL = package.sourceURLsByEntryID[entry.id] else {
                throw NearbyTransferError.invalidSource("a source file disappeared")
            }
            try await sendFile(
                entry,
                sourceURL: sourceURL,
                sentByteCount: &sentByteCount,
                totalByteCount: package.manifest.totalByteCount
            )
        }

        let manifestDigest = Data(SHA256.hash(data: manifestData))
        try await sendSecure(
            try NearbyTransferWire.encode(
                NearbyTransferWire.TransferEnd(manifestDigest: manifestDigest)
            ),
            type: .transferEnd
        )
        _ = try await receiveSecure(expectedType: .committed)

        didReachTerminalState = true
        await eventSink(.completed(NearbyTransferCompletion(
            id: id,
            peerName: peerName,
            direction: .sent,
            itemCount: package.manifest.itemCount,
            destinationDirectoryURL: nil
        )))
    }

    private func runReceiver() async throws {
        let remoteCommit: NearbyTransferWire.HandshakeCommit = try await receivePublic(
            NearbyTransferWire.HandshakeCommit.self,
            expectedType: .handshakeCommit
        )
        guard remoteCommit.commitment.count == 32 else {
            throw NearbyTransferError.protocolViolation("invalid handshake commitment")
        }
        let sessionID = remoteCommit.sessionID
        wireSessionID = sessionID
        let handshake = try NearbyTransferHandshake(identity: identity)

        try await sendPublic(
            NearbyTransferWire.HandshakeCommit(
                sessionID: sessionID,
                commitment: handshake.commitment(sessionID: sessionID, role: .receiver)
            ),
            type: .handshakeCommit
        )

        let remoteReveal: NearbyTransferWire.HandshakeReveal = try await receivePublic(
            NearbyTransferWire.HandshakeReveal.self,
            expectedType: .handshakeReveal
        )
        try NearbyTransferHandshake.verify(
            remoteCommit.commitment,
            reveal: remoteReveal,
            sessionID: sessionID,
            role: .initiator
        )
        try await sendPublic(handshake.reveal, type: .handshakeReveal)
        peerName = remoteReveal.deviceName
        cryptor = try NearbyTransferCryptor(
            handshake: handshake,
            remoteReveal: remoteReveal,
            initiatorReveal: remoteReveal,
            receiverReveal: handshake.reveal,
            sessionID: sessionID,
            isInitiator: false
        )

        try await performPairing(direction: .receiving)

        let manifestData = try await receiveSecure(expectedType: .manifest)
        guard manifestData.count <= NearbyTransferManifest.maximumEncodedByteCount else {
            throw NearbyTransferError.protocolViolation("file list is too large")
        }
        let manifest = try NearbyTransferWire.decode(
            NearbyTransferManifest.self,
            from: manifestData
        )
        guard manifest.transferID == sessionID else {
            throw NearbyTransferError.protocolViolation("transfer identifier mismatch")
        }
        try NearbyTransferManifestValidator().validate(manifest)

        await eventSink(.offerReceived(NearbyIncomingOffer(
            id: id,
            peerName: peerName,
            itemNames: Array(manifest.topLevelNames.prefix(5)),
            itemCount: manifest.itemCount,
            totalByteCount: manifest.totalByteCount
        )))

        guard let offerDecision = try await wait(
            for: offerDecision,
            timeout: .seconds(180)
        ) else {
            throw NearbyTransferError.cancelled
        }
        let destinationDirectoryURL: URL
        switch offerDecision {
        case .reject:
            try await sendSecure(
                try NearbyTransferWire.encode(
                    NearbyTransferWire.TransferDecision(
                        accepted: false,
                        reason: "Declined"
                    )
                ),
                type: .transferDecision
            )
            throw NearbyTransferError.rejected

        case let .accept(destination):
            destinationDirectoryURL = destination
        }

        do {
            receiver = try NearbyTransferReceiver(
                manifest: manifest,
                destinationDirectoryURL: destinationDirectoryURL
            )
        } catch {
            try await sendSecure(
                try NearbyTransferWire.encode(
                    NearbyTransferWire.TransferDecision(
                        accepted: false,
                        reason: error.localizedDescription
                    )
                ),
                type: .transferDecision
            )
            throw error
        }

        try await sendSecure(
            try NearbyTransferWire.encode(
                NearbyTransferWire.TransferDecision(accepted: true, reason: nil)
            ),
            type: .transferDecision
        )
        await emitProgress(
            direction: .receiving,
            completedByteCount: 0,
            totalByteCount: manifest.totalByteCount
        )

        let expectedManifestDigest = Data(SHA256.hash(data: manifestData))
        var receivedByteCount: UInt64 = 0
        while true {
            try Task.checkCancellation()
            let frame = try await receiveAnySecure()
            switch frame.type {
            case .fileStart:
                let value = try NearbyTransferWire.decode(
                    NearbyTransferWire.FileReference.self,
                    from: frame.payload
                )
                try receiver?.startFile(entryID: value.entryID)

            case .fileChunk:
                let value = try NearbyTransferWire.decode(
                    NearbyTransferWire.FileChunk.self,
                    from: frame.payload
                )
                try receiver?.writeChunk(
                    entryID: value.entryID,
                    offset: value.offset,
                    data: value.data
                )
                let (sum, overflow) = receivedByteCount.addingReportingOverflow(
                    UInt64(value.data.count)
                )
                guard overflow == false, sum <= manifest.totalByteCount else {
                    throw NearbyTransferError.protocolViolation(
                        "received data exceeds the declared size"
                    )
                }
                receivedByteCount = sum
                await emitProgress(
                    direction: .receiving,
                    completedByteCount: receivedByteCount,
                    totalByteCount: manifest.totalByteCount
                )

            case .fileEnd:
                let value = try NearbyTransferWire.decode(
                    NearbyTransferWire.FileReference.self,
                    from: frame.payload
                )
                try receiver?.finishFile(entryID: value.entryID)

            case .transferEnd:
                let value = try NearbyTransferWire.decode(
                    NearbyTransferWire.TransferEnd.self,
                    from: frame.payload
                )
                guard value.manifestDigest == expectedManifestDigest,
                      receivedByteCount == manifest.totalByteCount,
                      let receiver else {
                    throw NearbyTransferError.protocolViolation(
                        "the transfer did not verify"
                    )
                }
                let destinationURLs = try receiver.commit()
                self.receiver = nil
                try await sendSecure(Data(), type: .committed)
                didReachTerminalState = true
                await eventSink(.completed(NearbyTransferCompletion(
                    id: id,
                    peerName: peerName,
                    direction: .received,
                    itemCount: destinationURLs.count,
                    destinationDirectoryURL: destinationDirectoryURL
                )))
                return

            default:
                throw NearbyTransferError.protocolViolation(
                    "unexpected message during file transfer"
                )
            }
        }
    }

    private func performPairing(
        direction: NearbyPairingPrompt.Direction
    ) async throws {
        guard let cryptor else {
            throw NearbyTransferError.protocolViolation("encryption was not established")
        }
        await eventSink(.pairingRequired(NearbyPairingPrompt(
            id: id,
            peerName: peerName,
            code: cryptor.pairingCode,
            direction: direction
        )))

        guard let accepted = try await wait(
            for: pairingDecision,
            timeout: .seconds(120)
        ) else {
            throw NearbyTransferError.cancelled
        }
        try await sendSecure(
            try NearbyTransferWire.encode(
                NearbyTransferWire.PairDecision(
                    accepted: accepted,
                    transcriptHash: cryptor.transcriptHash
                )
            ),
            type: .pairDecision
        )
        guard accepted else { throw NearbyTransferError.rejected }

        let responseData = try await receiveSecure(expectedType: .pairDecision)
        let response = try NearbyTransferWire.decode(
            NearbyTransferWire.PairDecision.self,
            from: responseData
        )
        guard response.transcriptHash == cryptor.transcriptHash else {
            throw NearbyTransferError.protocolViolation("pairing transcript mismatch")
        }
        guard response.accepted else { throw NearbyTransferError.rejected }
    }

    private func sendFile(
        _ entry: NearbyTransferManifestEntry,
        sourceURL: URL,
        sentByteCount: inout UInt64,
        totalByteCount: UInt64
    ) async throws {
        try await sendSecure(
            try NearbyTransferWire.encode(
                NearbyTransferWire.FileReference(entryID: entry.id)
            ),
            type: .fileStart
        )

        let handle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? handle.close() }
        var fileOffset: UInt64 = 0
        var hasher = SHA256()
        while let data = try handle.read(
            upToCount: NearbyTransferWire.fileChunkByteCount
        ), data.isEmpty == false {
            try Task.checkCancellation()
            let (newOffset, overflow) = fileOffset.addingReportingOverflow(
                UInt64(data.count)
            )
            guard overflow == false, newOffset <= entry.byteCount else {
                throw NearbyTransferError.sourceChanged(entry.displayName)
            }
            try await sendSecure(
                try NearbyTransferWire.encode(
                    NearbyTransferWire.FileChunk(
                        entryID: entry.id,
                        offset: fileOffset,
                        data: data
                    )
                ),
                type: .fileChunk
            )
            hasher.update(data: data)
            fileOffset = newOffset
            sentByteCount += UInt64(data.count)
            await emitProgress(
                direction: .sending,
                completedByteCount: sentByteCount,
                totalByteCount: totalByteCount
            )
        }
        guard fileOffset == entry.byteCount,
              Data(hasher.finalize()) == entry.sha256 else {
            throw NearbyTransferError.sourceChanged(entry.displayName)
        }

        try await sendSecure(
            try NearbyTransferWire.encode(
                NearbyTransferWire.FileReference(entryID: entry.id)
            ),
            type: .fileEnd
        )
    }

    private func sendPublic<Value: Encodable>(
        _ value: Value,
        type: NearbyTransferWire.FrameType
    ) async throws {
        guard type.isEncrypted == false else {
            throw NearbyTransferError.protocolViolation("invalid public message")
        }
        try await connection.send(type: type, payload: NearbyTransferWire.encode(value))
    }

    private func receivePublic<Value: Decodable>(
        _ type: Value.Type,
        expectedType: NearbyTransferWire.FrameType
    ) async throws -> Value {
        let connection = connection
        let frame = try await withThrowingTaskGroup(
            of: NearbyTransferWire.Frame.self
        ) { group in
            group.addTask {
                try await connection.receive()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                throw NearbyTransferError.timedOut
            }
            guard let frame = try await group.next() else {
                throw NearbyTransferError.cancelled
            }
            group.cancelAll()
            return frame
        }
        guard frame.type == expectedType, frame.type.isEncrypted == false else {
            throw NearbyTransferError.protocolViolation("unexpected handshake message")
        }
        return try NearbyTransferWire.decode(type, from: frame.payload)
    }

    private func sendSecure(
        _ plaintext: Data,
        type: NearbyTransferWire.FrameType
    ) async throws {
        guard var cryptor else {
            throw NearbyTransferError.protocolViolation("secure session is unavailable")
        }
        let encrypted = try cryptor.seal(plaintext, type: type)
        self.cryptor = cryptor
        try await connection.send(type: type, payload: encrypted)
    }

    private func receiveSecure(
        expectedType: NearbyTransferWire.FrameType
    ) async throws -> Data {
        let frame = try await receiveAnySecure()
        guard frame.type == expectedType else {
            throw NearbyTransferError.protocolViolation("unexpected secure message")
        }
        return frame.payload
    }

    private func receiveAnySecure() async throws -> NearbyTransferWire.Frame {
        let frame = try await connection.receive()
        guard frame.type.isEncrypted, var cryptor else {
            throw NearbyTransferError.protocolViolation("unencrypted session message")
        }
        let plaintext = try cryptor.open(frame.payload, type: frame.type)
        self.cryptor = cryptor

        switch frame.type {
        case .cancel:
            throw NearbyTransferError.cancelled
        case .failure:
            let failure = try NearbyTransferWire.decode(
                NearbyTransferWire.Failure.self,
                from: plaintext
            )
            throw NearbyTransferError.transferFailed(failure.message)
        default:
            return NearbyTransferWire.Frame(type: frame.type, payload: plaintext)
        }
    }

    private func wait<Value: Sendable>(
        for gate: NearbyDecisionGate<Value>,
        timeout: Duration
    ) async throws -> Value? {
        try await withThrowingTaskGroup(of: Value?.self) { group in
            group.addTask { await gate.wait() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw NearbyTransferError.timedOut
            }
            guard let result = try await group.next() else {
                throw NearbyTransferError.cancelled
            }
            group.cancelAll()
            return result
        }
    }

    private func emitProgress(
        direction: NearbyTransferProgress.Direction,
        completedByteCount: UInt64,
        totalByteCount: UInt64
    ) async {
        let now = ContinuousClock.now
        let byteDelta = completedByteCount >= lastProgressByteCount
            ? completedByteCount - lastProgressByteCount
            : UInt64.max
        let elapsedLongEnough = lastProgressEmissionInstant.map {
            $0.duration(to: now) >= .milliseconds(100)
        } ?? true
        let isBoundary = completedByteCount == 0
            || completedByteCount >= totalByteCount

        guard isBoundary
            || byteDelta >= 16 * 1_024 * 1_024
            || elapsedLongEnough else {
            return
        }
        lastProgressEmissionInstant = now
        lastProgressByteCount = completedByteCount

        await eventSink(.progress(NearbyTransferProgress(
            id: id,
            peerName: peerName,
            direction: direction,
            completedByteCount: completedByteCount,
            totalByteCount: totalByteCount
        )))
    }

    private func emitFailure(_ error: Error) async {
        guard didReachTerminalState == false else { return }
        didReachTerminalState = true
        await eventSink(.failed(sessionID: id, message: error.localizedDescription))
    }

    private func emitCancellation() async {
        guard didReachTerminalState == false else { return }
        didReachTerminalState = true
        await eventSink(.cancelled(sessionID: id))
    }

    private func finishCancellation() async {
        receiver?.cancel()
        await emitCancellation()
        scheduleCancellationIfPossible()
    }

    private func scheduleCancellationIfPossible() {
        guard var cryptor, didSendCancellation == false else { return }
        guard let encrypted = try? cryptor.seal(Data(), type: .cancel) else { return }
        self.cryptor = cryptor
        didSendCancellation = true

        let connection = connection
        let sendTask = Task {
            try? await connection.send(type: .cancel, payload: encrypted)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            sendTask.cancel()
        }
    }

    private func sendFailureIfPossible(_ error: Error) async {
        guard cryptor != nil else { return }
        let payload = try? NearbyTransferWire.encode(
            NearbyTransferWire.Failure(
                message: String(error.localizedDescription.prefix(300))
            )
        )
        if let payload {
            try? await sendSecure(payload, type: .failure)
        }
    }
}
