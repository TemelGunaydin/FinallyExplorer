//
//  NearbyTransferCryptor.swift
//  FinallyExplorer
//

import CryptoKit
import Foundation

nonisolated struct NearbyTransferCryptor: Sendable {
    private let sessionID: UUID
    private let outboundKey: SymmetricKey
    private let inboundKey: SymmetricKey
    private let outboundNoncePrefix: Data
    private let inboundNoncePrefix: Data
    private let outboundDirection: UInt8
    private let inboundDirection: UInt8
    private(set) var outboundSequence: UInt64 = 0
    private(set) var inboundSequence: UInt64 = 0
    let pairingCode: String
    let transcriptHash: Data

    init(
        handshake: NearbyTransferHandshake,
        remoteReveal: NearbyTransferWire.HandshakeReveal,
        initiatorReveal: NearbyTransferWire.HandshakeReveal,
        receiverReveal: NearbyTransferWire.HandshakeReveal,
        sessionID: UUID,
        isInitiator: Bool
    ) throws {
        let remotePublicKey: Curve25519.KeyAgreement.PublicKey
        do {
            remotePublicKey = try Curve25519.KeyAgreement.PublicKey(
                rawRepresentation: remoteReveal.publicKey
            )
        } catch {
            throw NearbyTransferError.protocolViolation("invalid public key")
        }

        let sharedSecret = try handshake.privateKey.sharedSecretFromKeyAgreement(
            with: remotePublicKey
        )
        let transcriptHash = NearbyTransferHandshake.transcriptHash(
            sessionID: sessionID,
            initiator: initiatorReveal,
            receiver: receiverReveal
        )
        let initiatorToReceiverKey = Self.deriveKey(
            from: sharedSecret,
            salt: transcriptHash,
            label: "initiator-to-receiver-key",
            byteCount: 32
        )
        let receiverToInitiatorKey = Self.deriveKey(
            from: sharedSecret,
            salt: transcriptHash,
            label: "receiver-to-initiator-key",
            byteCount: 32
        )
        let initiatorNonce = Self.keyData(Self.deriveKey(
            from: sharedSecret,
            salt: transcriptHash,
            label: "initiator-to-receiver-nonce",
            byteCount: 4
        ))
        let receiverNonce = Self.keyData(Self.deriveKey(
            from: sharedSecret,
            salt: transcriptHash,
            label: "receiver-to-initiator-nonce",
            byteCount: 4
        ))
        let pairingData = Self.keyData(Self.deriveKey(
            from: sharedSecret,
            salt: transcriptHash,
            label: "pairing-code",
            byteCount: 8
        ))

        self.sessionID = sessionID
        self.transcriptHash = transcriptHash
        if isInitiator {
            outboundKey = initiatorToReceiverKey
            inboundKey = receiverToInitiatorKey
            outboundNoncePrefix = initiatorNonce
            inboundNoncePrefix = receiverNonce
            outboundDirection = 1
            inboundDirection = 2
        } else {
            outboundKey = receiverToInitiatorKey
            inboundKey = initiatorToReceiverKey
            outboundNoncePrefix = receiverNonce
            inboundNoncePrefix = initiatorNonce
            outboundDirection = 2
            inboundDirection = 1
        }

        let codeValue = pairingData.prefix(4).reduce(UInt32(0)) {
            ($0 << 8) | UInt32($1)
        } % 100_000_000
        pairingCode = String(format: "%08u", codeValue)
    }

    mutating func seal(
        _ plaintext: Data,
        type: NearbyTransferWire.FrameType
    ) throws -> Data {
        guard type.isEncrypted, outboundSequence < UInt64.max else {
            throw NearbyTransferError.protocolViolation("invalid send sequence")
        }
        let sequence = outboundSequence
        let nonce = try Self.nonce(prefix: outboundNoncePrefix, sequence: sequence)
        let aad = authenticatedData(
            type: type,
            sequence: sequence,
            direction: outboundDirection,
            plaintextByteCount: plaintext.count
        )
        let sealed = try ChaChaPoly.seal(
            plaintext,
            using: outboundKey,
            nonce: nonce,
            authenticating: aad
        )

        var payload = Data()
        Self.append(sequence, to: &payload)
        payload.append(sealed.ciphertext)
        payload.append(sealed.tag)
        outboundSequence += 1
        return payload
    }

    mutating func open(
        _ payload: Data,
        type: NearbyTransferWire.FrameType
    ) throws -> Data {
        guard type.isEncrypted, payload.count >= 24 else {
            throw NearbyTransferError.protocolViolation("invalid encrypted message")
        }
        let sequence = Self.uint64(from: payload.prefix(8))
        guard sequence == inboundSequence, inboundSequence < UInt64.max else {
            throw NearbyTransferError.protocolViolation(
                "a message was replayed or arrived out of order"
            )
        }

        let encrypted = payload.dropFirst(8)
        let ciphertext = Data(encrypted.dropLast(16))
        let tag = Data(encrypted.suffix(16))
        let nonce = try Self.nonce(prefix: inboundNoncePrefix, sequence: sequence)
        let aad = authenticatedData(
            type: type,
            sequence: sequence,
            direction: inboundDirection,
            plaintextByteCount: ciphertext.count
        )

        do {
            let box = try ChaChaPoly.SealedBox(
                nonce: nonce,
                ciphertext: ciphertext,
                tag: tag
            )
            let plaintext = try ChaChaPoly.open(
                box,
                using: inboundKey,
                authenticating: aad
            )
            inboundSequence += 1
            return plaintext
        } catch {
            throw NearbyTransferError.protocolViolation(
                "encrypted message authentication failed"
            )
        }
    }

    private func authenticatedData(
        type: NearbyTransferWire.FrameType,
        sequence: UInt64,
        direction: UInt8,
        plaintextByteCount: Int
    ) -> Data {
        var data = Data([NearbyTransferWire.protocolVersion, direction, type.rawValue])
        Self.append(sessionID.uuidString.lowercased(), to: &data)
        Self.append(sequence, to: &data)
        var count = UInt32(plaintextByteCount).bigEndian
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        return data
    }

    private static func deriveKey(
        from sharedSecret: SharedSecret,
        salt: Data,
        label: String,
        byteCount: Int
    ) -> SymmetricKey {
        sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: Data(label.utf8),
            outputByteCount: byteCount
        )
    }

    private static func keyData(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    private static func nonce(prefix: Data, sequence: UInt64) throws -> ChaChaPoly.Nonce {
        guard prefix.count == 4 else {
            throw NearbyTransferError.protocolViolation("invalid nonce prefix")
        }
        var data = prefix
        append(sequence, to: &data)
        return try ChaChaPoly.Nonce(data: data)
    }

    private static func append(_ string: String, to data: inout Data) {
        let value = Data(string.utf8)
        var count = UInt32(value.count).bigEndian
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        data.append(value)
    }

    private static func append(_ value: UInt64, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private static func uint64(from data: Data.SubSequence) -> UInt64 {
        data.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}
