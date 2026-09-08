import AppKit
import SwiftUI
import Testing
@testable import FinallyExplorer

@MainActor
struct FileToolsPresentationTests {
    @Test("Duplicate results, removal review and organization preview fit in light and dark", arguments: [false, true])
    func offscreenLayout(_ dark: Bool) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Reports/Accounting report.pdf", "same")
        try fixture.write("Archived accounting report.pdf", "same")
        try fixture.write("Source.json", "source")
        let duplicates = DuplicateFilesModel(rootURL: fixture.source, operations: FileOperationCoordinator())
        await duplicates.scan()?.value
        let snapshot = try #require(duplicates.snapshot)
        let plan = try DuplicateTrashPlan(snapshot: snapshot, selection: ["Archived accounting report.pdf"])
        try render(DuplicateFilesSheet(model: duplicates, onReveal: { _ in }), name: "Duplicates", width: 760, height: 660, dark: dark)
        try render(DuplicateTrashReviewSheet(plan: plan, onConfirm: {}), name: "DuplicateReview", width: 620, height: 540, dark: dark)
        let organization = FolderOrganizationModel(rootURL: fixture.source)
        await organization.preview()?.value
        try render(FolderOrganizationSheet(model: organization), name: "Organization", width: 760, height: 660, dark: dark)
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
