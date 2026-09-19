import CoreGraphics
import Testing
@testable import FinallyExplorer

struct WorkspaceLayoutMetricsTests {
    @Test("Preview yields room to the file pane in the former 900-point window")
    func narrowWindowPreview() {
        let width = WorkspaceLayoutMetrics.previewWidth(availableWidth: 619, isVisible: true)
        #expect(width == 220)
        #expect(619 - width >= WorkspaceLayoutMetrics.minimumPaneWidth)
    }

    @Test("Preview expands only after the workspace has its comfortable width")
    func previewExpands() {
        #expect(WorkspaceLayoutMetrics.previewWidth(availableWidth: 660, isVisible: true) == 240)
        #expect(WorkspaceLayoutMetrics.previewWidth(availableWidth: 760, isVisible: true) == 340)
        #expect(WorkspaceLayoutMetrics.previewWidth(availableWidth: 1_500, isVisible: true) == 340)
    }

    @Test("Preview never consumes the minimum pane width", arguments: [
        CGFloat(0), 280, 340, 400, 560, 619, 668, 760, 1_048, 1_800
    ], [true, false])
    func previewBounds(available: CGFloat, visible: Bool) {
        let preview = WorkspaceLayoutMetrics.previewWidth(availableWidth: available, isVisible: visible)
        #expect(preview >= 0)
        #expect(preview <= WorkspaceLayoutMetrics.preferredPreviewWidth)
        #expect(available - preview >= min(available, WorkspaceLayoutMetrics.minimumPaneWidth))
        if visible == false { #expect(preview == 0) }
    }

    @Test("Transient invalid proposals cannot create an invalid frame", arguments: [
        CGFloat(-1), .infinity, -.infinity, .nan
    ])
    func invalidProposals(available: CGFloat) {
        #expect(WorkspaceLayoutMetrics.previewWidth(availableWidth: available, isVisible: true) == 0)
    }

    @Test("Minimum window fits two minimum-width panes beside the widest sidebar")
    @MainActor
    func gridFitsMinimumWindow() {
        let available = WorkspaceLayoutMetrics.minimumWindowWidth
            - SidebarSplitViewBehaviorInstaller.maximumWidth - 1 - 7
        #expect(available / 2 >= WorkspaceLayoutMetrics.minimumPaneWidth)
    }
}
