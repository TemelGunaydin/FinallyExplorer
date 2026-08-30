//
//  NearbyTransferWire.swift
//  FinallyExplorer
//

import Foundation

nonisolated enum NearbyTransferWire {
    static let protocolVersion: UInt8 = 1
    static let maximumFrameByteCount = 1_048_576
    static let fileChunkByteCount = 256 * 1_024

    enum FrameType: UInt8, Sendable {
        case handshakeCommit = 1
        case handshakeReveal = 2
        case pairDecision = 10
        case manifest = 11
        case transferDecision = 12
        case fileStart = 13
        case fileChunk = 14
        case fileEnd = 15
        case transferEnd = 16
        case committed = 17
        case cancel = 18
        case failure = 19

        var isEncrypted: Bool { rawValue >= 10 }
    }

    struct Frame: Sendable {
        let type: FrameType
        let payload: Data
    }

    struct HandshakeCommit: Codable, Sendable {
        let sessionID: UUID
        let commitment: Data
    }

    struct HandshakeReveal: Codable, Sendable {
        let deviceID: UUID
        let deviceName: String
        let publicKey: Data
        let nonce: Data
    }

    struct PairDecision: Codable, Sendable {
        let accepted: Bool
        let transcriptHash: Data
    }

    struct TransferDecision: Codable, Sendable {
        let accepted: Bool
        let reason: String?
    }

    struct FileReference: Codable, Sendable {
        let entryID: UUID
    }

    struct FileChunk: Codable, Sendable {
        let entryID: UUID
        let offset: UInt64
        let data: Data
    }

    struct TransferEnd: Codable, Sendable {
        let manifestDigest: Data
    }

    struct Failure: Codable, Sendable {
        let message: String
    }

    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(value)
    }

    static func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        do {
            return try PropertyListDecoder().decode(type, from: data)
        } catch {
            throw NearbyTransferError.protocolViolation("malformed message")
        }
    }
}
