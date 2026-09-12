import AppKit
import Testing
@testable import FinallyExplorer

@MainActor
struct ExplorerToolsKeyboardTests {
    @Test("Menu keyboard handling accepts only navigation and activation keys")
    func keyPolicy() throws {
        let expected: [(UInt16, ExplorerToolsKeyboardAttachmentView.Command?)] = [
            (125, .move(1)), (126, .move(-1)), (48, .move(1)), (36, .activate), (76, .activate), (49, .activate), (53, .close),
            (0, nil), (51, nil), (123, nil), (124, nil)
        ]
        for (code, command) in expected {
            let event = try event(code)
            #expect(ExplorerToolsKeyboardAttachmentView.command(for: event) == command)
        }
        for flags: NSEvent.ModifierFlags in [.command, .control, .option, .shift] {
            #expect(ExplorerToolsKeyboardAttachmentView.command(for: try event(125, flags: flags)) == nil)
        }
        #expect(ExplorerToolsKeyboardAttachmentView.command(for: try event(125, flags: .function)) == .move(1))
        #expect(ExplorerToolsKeyboardAttachmentView.command(for: try event(48, flags: .shift)) == .move(-1))
    }

    @Test("Removing the menu's attachment removes its keyboard monitor without activating a window")
    func lifetime() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSView()
        window.contentView = host
        let attachment = ExplorerToolsKeyboardAttachmentView(onMove: { _ in }, onActivate: {}, onClose: {})
        host.addSubview(attachment)
        #expect(attachment.isMonitoring)
        #expect(window.isVisible == false)
        attachment.removeFromSuperview()
        #expect(attachment.isMonitoring == false)
        attachment.uninstall() // Teardown is safe even after view removal.
    }

    @Test("Menu keyboard routing ignores other windows and missing key windows")
    func windowScope() {
        let windows = (0..<3).map { _ in
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            return window
        }
        defer { windows.forEach { $0.close() } }
        let menu = windows[0], owner = windows[1], unrelated = windows[2]
        let matches = ExplorerToolsKeyboardAttachmentView.targetsMenu
        #expect(matches(menu, menu, menu, owner))
        #expect(matches(owner, owner, menu, owner))
        #expect(matches(nil, owner, menu, owner))
        #expect(matches(unrelated, owner, menu, owner) == false)
        #expect(matches(unrelated, unrelated, menu, owner) == false)
        #expect(matches(nil, unrelated, menu, owner) == false)
        #expect(matches(nil, nil, menu, nil) == false)
        #expect(windows.allSatisfy { $0.isVisible == false })
    }

    private func event(_ code: UInt16, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: code))
    }
}
