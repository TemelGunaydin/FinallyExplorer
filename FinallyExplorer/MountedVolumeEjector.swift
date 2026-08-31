//
//  MountedVolumeEjector.swift
//  FinallyExplorer
//

import Foundation

nonisolated protocol MountedVolumeEjecting: Sendable {
    func eject(_ volumeURL: URL) async throws
}

nonisolated enum MountedVolumeEjectError: LocalizedError, Equatable, Sendable {
    case volumeMustBeLocal(value: String)
    case cannotEjectFileSystemRoot

    var errorDescription: String? {
        switch self {
        case let .volumeMustBeLocal(value):
            "Only a locally mounted disk can be ejected.\n\nValue: \(value)"
        case .cannotEjectFileSystemRoot:
            "The startup disk cannot be ejected."
        }
    }
}

/// Uses the same whole-device unmount-and-eject operation exposed by Finder.
nonisolated struct SystemMountedVolumeEjector: MountedVolumeEjecting {
    @concurrent
    func eject(_ volumeURL: URL) async throws {
        let normalizedURL = volumeURL.standardizedFileURL
        let host = normalizedURL.host?.lowercased()
        guard normalizedURL.isFileURL,
              host == nil || host == "" || host == "localhost" else {
            throw MountedVolumeEjectError.volumeMustBeLocal(
                value: volumeURL.absoluteString
            )
        }
        guard normalizedURL.path(percentEncoded: false) != "/" else {
            throw MountedVolumeEjectError.cannotEjectFileSystemRoot
        }

        try await FileManager.default.unmountVolume(
            at: normalizedURL,
            options: [.allPartitionsAndEjectDisk]
        )
    }
}
