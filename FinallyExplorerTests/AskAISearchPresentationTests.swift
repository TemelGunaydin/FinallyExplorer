import AppKit
import SwiftUI
import Testing
@testable import FinallyExplorer

@MainActor
struct AskAISearchPresentationTests {
    @Test("Ask AI lays out within its sheet in both appearances without activating a window", arguments: [false, true])
    func offscreenLayout(_ dark: Bool) async throws {
        let suite = "FinallyExplorer.AskAI.Layout.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ExplorerAISettings(defaults: defaults)
        let model = AskAISearchModel(interpreter: AskAISearchInterpreterStub(), executor: SmartSearchExecutorStub())
        if dark {
            model.draft = "Find the accounting report from two days ago"
            await model.submit(rootURL: URL(filePath: "/fixture"))?.value
        }
        let view = AskAISearchSheet(model: model, settings: settings, rootURL: URL(filePath: "/fixture"), onReveal: { _ in })
            .environment(\.explorerTheme, ExplorerTheme.palette(for: .mesa))
            .environment(\.colorScheme, dark ? .dark : .light)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        defer { window.close() }
        // Never order this window on screen or take the user's focus.
        hosting.layoutSubtreeIfNeeded()
        #expect(hosting.fittingSize.width <= 700)
        #expect(hosting.fittingSize.height <= 600)
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(png.count > 1_000)
        let url = URL(filePath: "/tmp/FinallyExplorer-AskAI-\(dark ? "dark" : "light").png")
        try png.write(to: url, options: .atomic)
    }
}
