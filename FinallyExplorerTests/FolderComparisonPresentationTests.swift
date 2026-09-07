import AppKit
import SwiftUI
import Testing
@testable import FinallyExplorer

@MainActor
struct FolderComparisonPresentationTests {
    @Test("Comparison and review fit their sheets in light and dark without activating a window", arguments: [false, true])
    func offscreenLayout(_ dark: Bool) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Reports/Accounting report.pdf", "fixture")
        try fixture.write("Changed.json", "before")
        try fixture.write("Changed.json", "after!", in: fixture.destination)
        let model = FolderComparisonModel(locations: [
            FolderComparisonLocation(id: UUID(), title: "Panel 1 · Source", url: fixture.source),
            FolderComparisonLocation(id: UUID(), title: "Panel 2 · Destination", url: fixture.destination)
        ], preferredSourceID: nil, operations: FileOperationCoordinator())
        await model.compare()?.value
        let plan = try #require(model.copyCandidate)
        try render(FolderComparisonSheet(model: model), name: "Compare", width: 760, height: 660, dark: dark)
        try render(VerifiedCopyReviewSheet(plan: plan, onConfirm: {}), name: "VerifiedCopy", width: 600, height: 540, dark: dark)
    }

    private func render(_ view: some View, name: String, width: CGFloat, height: CGFloat, dark: Bool) throws {
        let view = view.environment(\.explorerTheme, ExplorerTheme.palette(for: .mesa))
            .environment(\.colorScheme, dark ? .dark : .light)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        defer { window.close() }
        // No orderFront/makeKey: keep the user's desktop untouched.
        hosting.layoutSubtreeIfNeeded()
        #expect(hosting.fittingSize.width <= width)
        #expect(hosting.fittingSize.height <= height)
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(png.count > 1_000)
        try png.write(to: URL(filePath: "/tmp/FinallyExplorer-\(name)-\(dark ? "dark" : "light").png"), options: .atomic)
    }
}
