//
//  NearbyTransferFramedConnection.swift
//  FinallyExplorer
//

import Foundation
import Network

nonisolated struct NearbyTransferFramedConnection: Sendable {
    private static let headerByteCount = 8
    private static let magic: [UInt8] = [0x46, 0x58]

    private let connection: NetworkConnection<TCP>

    init(connection: NetworkConnection<TCP>) {
        self.connection = connection
    }

    func send(
        type: NearbyTransferWire.FrameType,
        payload: Data
    ) async throws {
        guard payload.count <= NearbyTransferWire.maximumFrameByteCount,
              let length = UInt32(exactly: payload.count) else {
            throw NearbyTransferError.protocolViolation("message is too large")
        }

        var frame = Data(Self.magic)
        frame.append(NearbyTransferWire.protocolVersion)
        frame.append(type.rawValue)
        var bigEndianLength = length.bigEndian
        withUnsafeBytes(of: &bigEndianLength) { frame.append(contentsOf: $0) }
        frame.append(payload)
        try await connection.send(frame)
    }

    func receive() async throws -> NearbyTransferWire.Frame {
        let header = try await connection.receive(exactly: Self.headerByteCount).content
        guard header.count == Self.headerByteCount else {
            throw NearbyTransferError.connectionClosed
        }
        let bytes = [UInt8](header)
        guard Array(bytes[0..<2]) == Self.magic,
              bytes[2] == NearbyTransferWire.protocolVersion,
              let type = NearbyTransferWire.FrameType(rawValue: bytes[3]) else {
            throw NearbyTransferError.protocolViolation("unknown message header")
        }

        let length = bytes[4..<8].reduce(UInt32(0)) {
            ($0 << 8) | UInt32($1)
        }
        guard length <= NearbyTransferWire.maximumFrameByteCount else {
            throw NearbyTransferError.protocolViolation("message is too large")
        }

        let payload: Data
        if length == 0 {
            payload = Data()
        } else {
            payload = try await connection.receive(exactly: Int(length)).content
            guard payload.count == Int(length) else {
                throw NearbyTransferError.connectionClosed
            }
        }
        return NearbyTransferWire.Frame(type: type, payload: payload)
    }
}
