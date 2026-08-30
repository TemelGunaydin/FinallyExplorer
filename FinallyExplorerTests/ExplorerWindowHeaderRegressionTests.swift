//
//  ExplorerWindowHeaderRegressionTests.swift
//  FinallyExplorerTests
//

import AppKit
import SwiftUI
import Testing
@testable import FinallyExplorer

struct ExplorerWindowHeaderRegressionTests {
    @MainActor
    @Test("Window chrome reserves breathing room without shifting its controls")
    func windowChromeKeepsComfortableHeight() {
        let header = ExplorerWindowHeader(
            activeFolderTitle: "Documents",
            paneCount: 1,
            isPreviewVisible: true,
            onToggleSidebar: {},
            onTogglePreview: {},
            onResetView: {}
        )
        let hostingView = NSHostingView(rootView: header)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1_200, height: 72)
        hostingView.layoutSubtreeIfNeeded()

        #expect(hostingView.fittingSize.height == 72)
    }
}
