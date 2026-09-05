import AppKit
import SwiftUI
import Testing
@testable import FinallyExplorer

struct ReadOnlyTextPreviewTests {
    @MainActor
    @Test("The code preview lays out selectable text and scrolls inside its viewport")
    func previewLaysOutAndScrolls() async {
        await #expect(processExitsWith: .success) {
            await exerciseTextPreviewInAWindow()
        }
    }
}

@MainActor
private func exerciseTextPreviewInAWindow() async {
    let contents = (1...200).map { "let line\($0) = \"Preview content\"" }.joined(separator: "\n")
    let hostingView = NSHostingView(rootView: ReadOnlyTextPreview(
        text: contents,
        textColor: .white
    ))
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.alphaValue = 0.01
    window.contentView = hostingView
    window.orderFront(nil)
    defer { window.close() }

    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while findPreviewTextView(in: hostingView)?.string != contents,
          ContinuousClock.now < deadline {
        await Task.yield()
        hostingView.layoutSubtreeIfNeeded()
    }
    hostingView.layoutSubtreeIfNeeded()

    guard let textView = findPreviewTextView(in: hostingView),
          let scrollView = textView.enclosingScrollView,
          let layoutManager = textView.layoutManager,
          let textContainer = textView.textContainer else {
        preconditionFailure("The preview must contain a native text view and scroll view.")
    }
    layoutManager.ensureLayout(for: textContainer)
    precondition(textView.string == contents)
    precondition(textView.isSelectable && textView.isEditable == false)
    precondition(textView.frame.width > 300)
    precondition(scrollView.contentSize.height > 400)
    precondition(layoutManager.usedRect(for: textContainer).height > scrollView.contentSize.height)
    precondition(textView.frame.height > scrollView.contentSize.height)

    textView.scrollRangeToVisible(NSRange(location: contents.utf16.count - 1, length: 1))
    precondition(scrollView.documentVisibleRect.minY > 0, "Long previews must scroll.")
}

@MainActor
private func findPreviewTextView(in view: NSView) -> NSTextView? {
    if let textView = view as? NSTextView { return textView }
    for child in view.subviews {
        if let textView = findPreviewTextView(in: child) { return textView }
    }
    return nil
}
