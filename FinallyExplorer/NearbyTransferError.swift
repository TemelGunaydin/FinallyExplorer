//
//  NearbyTransferError.swift
//  FinallyExplorer
//

import Foundation

nonisolated enum NearbyTransferError: LocalizedError, Sendable {
    case alreadyBusy
    case cancelled
    case connectionClosed
    case destinationUnavailable
    case insufficientSpace
    case invalidManifest(String)
    case invalidSource(String)
    case peerUnavailable
    case protocolViolation(String)
    case rejected
    case sourceChanged(String)
    case timedOut
    case transferFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyBusy:
            "Another nearby transfer is already active."
        case .cancelled:
            "The nearby transfer was cancelled."
        case .connectionClosed:
            "The nearby device disconnected."
        case .destinationUnavailable:
            "The selected destination folder is unavailable."
        case .insufficientSpace:
            "There is not enough free space for this transfer."
        case let .invalidManifest(reason):
            "The nearby device sent an invalid file list: \(reason)"
        case let .invalidSource(reason):
            "This item cannot be transferred: \(reason)"
        case .peerUnavailable:
            "That nearby device is no longer available."
        case let .protocolViolation(reason):
            "The nearby device sent an invalid message: \(reason)"
        case .rejected:
            "The nearby transfer was declined."
        case let .sourceChanged(name):
            "\(name) changed while it was being transferred."
        case .timedOut:
            "The nearby transfer timed out."
        case let .transferFailed(reason):
            reason
        }
    }
}
