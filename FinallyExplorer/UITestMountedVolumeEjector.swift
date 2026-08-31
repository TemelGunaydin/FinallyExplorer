//
//  UITestMountedVolumeEjector.swift
//  FinallyExplorer
//

import Foundation

/// Prevents UI automation from attempting to eject a real disk.
nonisolated struct UITestMountedVolumeEjector: MountedVolumeEjecting {
    func eject(_ volumeURL: URL) async throws {
        try await Task.sleep(for: .milliseconds(250))
    }
}
