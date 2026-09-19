import CoreGraphics

/// Widths include the pane/inspector's outer padding.
nonisolated enum WorkspaceLayoutMetrics {
    static let minimumWindowWidth: CGFloat = 980
    static let minimumWindowHeight: CGFloat = 640
    static let defaultWindowWidth: CGFloat = 1_280
    static let defaultWindowHeight: CGFloat = 800
    static let minimumPaneWidth: CGFloat = 340
    static let paneOuterPadding: CGFloat = 6
    static let preferredWorkspaceWidth: CGFloat = 420
    static let minimumPreviewWidth: CGFloat = 220
    static let preferredPreviewWidth: CGFloat = 340

    static func previewWidth(availableWidth: CGFloat, isVisible: Bool) -> CGFloat {
        guard isVisible, availableWidth.isFinite else { return 0 }
        let available = max(0, availableWidth)
        let desired = min(
            preferredPreviewWidth,
            max(minimumPreviewWidth, available - preferredWorkspaceWidth)
        )
        return min(desired, max(0, available - minimumPaneWidth))
    }
}
