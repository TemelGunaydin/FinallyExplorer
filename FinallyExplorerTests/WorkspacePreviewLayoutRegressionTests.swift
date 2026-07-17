//
//  WorkspacePreviewLayoutRegressionTests.swift
//  FinallyExplorerTests
//

import AppKit
import SwiftUI
import Testing
@testable import FinallyExplorer

struct WorkspacePreviewLayoutRegressionTests {
    @MainActor
    @Test("Grid selection avoids preview transitions and single-pane preview stays stable")
    func gridSelectionDoesNotStartPreviewLayout() async {
        await #expect(processExitsWith: .success) {
            await exerciseGridSelectionInARealWindow()
        }
    }
}

@MainActor
private func exerciseGridSelectionInARealWindow() async {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory
        .appending(
            path: "FinallyExplorer-Preview-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    let folderURL = rootURL.appending(path: "Folder", directoryHint: .isDirectory)
    let childURL = folderURL.appending(path: "child.txt")
    let imageURL = rootURL.appending(path: "preview.png")
    let imageData = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    try! fileManager.createDirectory(
        at: folderURL,
        withIntermediateDirectories: true
    )
    try! Data("child".utf8).write(to: childURL)
    try! imageData.write(to: imageURL)
    defer { try? fileManager.removeItem(at: rootURL) }

    let firstPaneID = layoutUUID(1)
    var generatedIDs = (2...7).map(layoutUUID)
    let workspace = WorkspaceModel(
        initialPlace: .downloads,
        initialPaneID: firstPaneID,
        idGenerator: { generatedIDs.removeFirst() }
    )

    let secondPaneID = workspace.split(
        paneID: firstPaneID,
        direction: .right
    )!
    let thirdPaneID = workspace.split(
        paneID: secondPaneID,
        direction: .below
    )!
    let fourthPaneID = workspace.split(
        paneID: firstPaneID,
        direction: .below
    )!
    let paneIDs = [firstPaneID, secondPaneID, thirdPaneID, fourthPaneID]
    let folder = FileItem(
        url: folderURL,
        isDirectory: true,
        isImage: false,
        fileSize: nil,
        modificationDate: nil
    )
    let image = FileItem(
        url: imageURL,
        isDirectory: false,
        isImage: true,
        fileSize: Int64(imageData.count),
        modificationDate: nil
    )

    for paneID in paneIDs {
        let pane = workspace.pane(paneID)!
        pane.navigation.open(rootURL)
        pane.directoryContents = [folder]
        pane.isLoading = false
    }

    let contentView = ContentView(
        workspace: workspace,
        fileOperations: FileOperationCoordinator(),
        terminalApplications: TerminalApplicationCoordinator(
            workspace: PreviewLayoutTerminalWorkspace()
        )
    )
    let hostingView = NSHostingView(rootView: contentView)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1_496, height: 939),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.alphaValue = 0.01
    window.contentView = hostingView
    window.orderFront(nil)
    defer { window.close() }

    hostingView.layoutSubtreeIfNeeded()

    for paneID in paneIDs {
        let pane = workspace.pane(paneID)!
        workspace.activate(paneID)
        pane.selectedURL = nil
        await Task.yield()
        pane.selectedURL = folderURL

        try? await Task.sleep(for: .milliseconds(100))
        hostingView.layoutSubtreeIfNeeded()

        precondition(
            pane.isInspectorPresented == false,
            "Grid mode must not create the trailing preview presentation."
        )
    }

    // Collapse the grid, then exercise both AppKit-backed preview branches in
    // the same window. The preview column remains mounted while its contents
    // change, so no system inspector move transition can be introduced.
    precondition(workspace.close(firstPaneID))
    precondition(workspace.close(secondPaneID))
    precondition(workspace.close(thirdPaneID))
    let remainingPane = workspace.pane(fourthPaneID)!
    try? await Task.sleep(for: .milliseconds(500))
    remainingPane.directoryContents = [folder, image]

    remainingPane.selectedURL = nil
    await Task.yield()
    remainingPane.selectedURL = imageURL
    remainingPane.isInspectorPresented = true
    try? await Task.sleep(for: .milliseconds(250))
    hostingView.layoutSubtreeIfNeeded()
    precondition(remainingPane.isInspectorPresented)

    remainingPane.selectedURL = folderURL
    try? await Task.sleep(for: .milliseconds(250))
    hostingView.layoutSubtreeIfNeeded()
    precondition(remainingPane.isInspectorPresented)

    // Keep the AppKit display cycle alive long enough to expose the former
    // Update Constraints loop, which first appeared after repeated pane clicks.
    try? await Task.sleep(for: .seconds(2))
    hostingView.layoutSubtreeIfNeeded()
}

@MainActor
private final class PreviewLayoutTerminalWorkspace: TerminalWorkspace {
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

private func layoutUUID(_ value: Int) -> UUID {
    UUID(
        uuidString: String(
            format: "00000000-0000-0000-0000-%012X",
            value
        )
    )!
}
