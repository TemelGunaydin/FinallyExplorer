//
//  NearbyTransferHandshake.swift
//  FinallyExplorer
//

import CryptoKit
import Foundation
import Security

nonisolated struct NearbyTransferHandshake: Sendable {
    enum Role: UInt8, Sendable {
        case initiator = 1
        case receiver = 2
    }

    let privateKey: Curve25519.KeyAgreement.PrivateKey
    let reveal: NearbyTransferWire.HandshakeReveal

    init(identity: NearbyTransferIdentity) throws {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        var randomBytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(
            kSecRandomDefault,
            randomBytes.count,
            &randomBytes
        )
        guard status == errSecSuccess else {
            throw NearbyTransferError.transferFailed(
                "Unable to create a secure nearby session."
            )
        }
        self.privateKey = privateKey
        reveal = NearbyTransferWire.HandshakeReveal(
            deviceID: identity.deviceID,
            deviceName: identity.name,
            publicKey: privateKey.publicKey.rawRepresentation,
            nonce: Data(randomBytes)
        )
    }

    func commitment(sessionID: UUID, role: Role) -> Data {
        Data(SHA256.hash(data: Self.canonicalReveal(
            reveal,
            sessionID: sessionID,
            role: role
        )))
    }

    static func verify(
        _ commitment: Data,
        reveal: NearbyTransferWire.HandshakeReveal,
        sessionID: UUID,
        role: Role
    ) throws {
        try validate(reveal)
        let expected = Data(SHA256.hash(data: canonicalReveal(
            reveal,
            sessionID: sessionID,
            role: role
        )))
        guard expected == commitment else {
            throw NearbyTransferError.protocolViolation(
                "the secure handshake did not match its commitment"
            )
        }
    }

    static func transcriptHash(
        sessionID: UUID,
        initiator: NearbyTransferWire.HandshakeReveal,
        receiver: NearbyTransferWire.HandshakeReveal
    ) -> Data {
        var transcript = Data("FinallyExplorer-Nearby-1".utf8)
        append(sessionID.uuidString.lowercased(), to: &transcript)
        transcript.append(canonicalReveal(
            initiator,
            sessionID: sessionID,
            role: .initiator
        ))
        transcript.append(canonicalReveal(
            receiver,
            sessionID: sessionID,
            role: .receiver
        ))
        return Data(SHA256.hash(data: transcript))
    }

    private static func validate(
        _ reveal: NearbyTransferWire.HandshakeReveal
    ) throws {
        guard reveal.deviceName.isEmpty == false,
              reveal.deviceName.utf8.count <= 240,
              reveal.publicKey.count == 32,
              reveal.nonce.count == 32 else {
            throw NearbyTransferError.protocolViolation("invalid secure handshake")
        }
    }

    private static func canonicalReveal(
        _ reveal: NearbyTransferWire.HandshakeReveal,
        sessionID: UUID,
        role: Role
    ) -> Data {
        var data = Data([NearbyTransferWire.protocolVersion, role.rawValue])
        append(sessionID.uuidString.lowercased(), to: &data)
        append(reveal.deviceID.uuidString.lowercased(), to: &data)
        append(reveal.deviceName, to: &data)
        append(reveal.publicKey, to: &data)
        append(reveal.nonce, to: &data)
        return data
    }

    private static func append(_ string: String, to data: inout Data) {
        append(Data(string.utf8), to: &data)
    }

    private static func append(_ value: Data, to data: inout Data) {
        var length = UInt32(value.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(value)
    }
}
