//
//  AccessibilityPreviewRegressionTests.swift
//  FinallyExplorerTests
//

import AppKit
import SwiftUI
import Testing
@testable import FinallyExplorer

struct AccessibilityPreviewRegressionTests {
    @MainActor
    @Test("Selecting a preview item keeps the SwiftUI accessibility tree acyclic")
    func previewSelectionDoesNotRecurseWhileLabelsResolve() async {
        await #expect(processExitsWith: .success) {
            await exercisePreviewSelectionWhileResolvingAccessibilityLabels()
        }
    }
}

@MainActor
private func exercisePreviewSelectionWhileResolvingAccessibilityLabels() async {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory
        .appending(
            path: "FinallyExplorer-Accessibility-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    let imageURL = rootURL.appending(path: "preview.png")
    let imageData = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    try! fileManager.createDirectory(
        at: rootURL,
        withIntermediateDirectories: true
    )
    try! imageData.write(to: imageURL)
    defer { try? fileManager.removeItem(at: rootURL) }

    let workspace = WorkspaceModel(initialPlace: .downloads)
    let pane = workspace.activePane!
    let image = FileItem(
        url: imageURL,
        isDirectory: false,
        isImage: true,
        fileSize: Int64(imageData.count),
        modificationDate: nil
    )

    pane.navigation.open(rootURL)
    pane.directoryContents = [image]
    pane.isLoading = false

    let contentView = ContentView(
        workspace: workspace,
        fileOperations: FileOperationCoordinator(),
        terminalApplications: TerminalApplicationCoordinator(
            workspace: AccessibilityRegressionTerminalWorkspace()
        )
    )
    let hostingView = NSHostingView(rootView: contentView)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1_200, height: 760),
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
    resolveAccessibilityLabels(from: hostingView)

    pane.selectedURL = imageURL
    pane.isInspectorPresented = true
    try? await Task.sleep(for: .milliseconds(250))
    hostingView.layoutSubtreeIfNeeded()
    resolveAccessibilityLabels(from: hostingView)
}

@MainActor
private func resolveAccessibilityLabels(from root: NSObject) {
    var visited: Set<ObjectIdentifier> = []
    resolveAccessibilityLabels(from: root, visited: &visited, depth: 0)
}

@MainActor
private func resolveAccessibilityLabels(
    from element: NSObject,
    visited: inout Set<ObjectIdentifier>,
    depth: Int
) {
    precondition(depth < 256, "Accessibility children must not form a cycle")

    let identifier = ObjectIdentifier(element)
    guard visited.insert(identifier).inserted else { return }

    _ = element.accessibilityAttributeValue(
        NSAccessibility.Attribute.description
    )

    let children = element.accessibilityAttributeValue(
        NSAccessibility.Attribute.children
    ) as? [Any] ?? []

    for case let child as NSObject in children {
        resolveAccessibilityLabels(
            from: child,
            visited: &visited,
            depth: depth + 1
        )
    }
}

@MainActor
private final class AccessibilityRegressionTerminalWorkspace: TerminalWorkspace {
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
