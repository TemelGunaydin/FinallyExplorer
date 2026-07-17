//
//  FolderContentsInspectorRegressionTests.swift
//  FinallyExplorerTests
//

import AppKit
import SwiftUI
import Testing
@testable import FinallyExplorer

struct FolderContentsInspectorRegressionTests {
    @MainActor
    @Test("Folder inspector has every dependency when rendered outside the main view tree")
    func explicitDependenciesSurvivePresentationBoundary() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                let folderURL = URL(
                    filePath: NSTemporaryDirectory(),
                    directoryHint: .isDirectory
                )
                let folder = FileItem(
                    url: folderURL,
                    isDirectory: true,
                    isImage: false,
                    fileSize: nil,
                    modificationDate: nil
                )
                let inspector = FolderContentsInspector(
                    folder: folder,
                    paneID: UUID(),
                    fileOperations: FileOperationCoordinator(),
                    terminalApplications: TerminalApplicationCoordinator(
                        workspace: EmptyTerminalWorkspace()
                    )
                )
                let hostingView = NSHostingView(rootView: inspector)

                hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
                hostingView.layoutSubtreeIfNeeded()
                _ = hostingView.fittingSize
            }
        }
    }
}

@MainActor
private final class EmptyTerminalWorkspace: TerminalWorkspace {
    func terminalApplicationCandidates() -> [TerminalApplicationCandidate] {
        []
    }

    func applicationURL(withBundleIdentifier bundleIdentifier: String) -> URL? {
        nil
    }

    func openDirectory(
        _ directoryURL: URL,
        withApplicationAt applicationURL: URL
    ) async throws {}
}
