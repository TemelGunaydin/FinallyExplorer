import AppKit
@testable import FinallyExplorer

@MainActor
final class SidebarSplitViewTestFixture {
    let window: NSWindow
    let splitView: NSSplitView
    let sidebarView: NSView
    let sidebarItem: NSSplitViewItem?
    let attachment: SidebarSplitViewAttachmentView

    init(usesSplitController: Bool = true) {
        sidebarView = NSView(frame: NSRect(x: 0, y: 0, width: 232, height: 640))
        attachment = SidebarSplitViewAttachmentView(minimumThickness: 210, maximumThickness: 280)
        attachment.frame = sidebarView.bounds
        attachment.autoresizingMask = [.width, .height]
        sidebarView.addSubview(attachment)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 0.01

        if usesSplitController {
            let sidebarController = NSViewController()
            sidebarController.view = sidebarView
            let controller = NSSplitViewController()
            let item = NSSplitViewItem(sidebarWithViewController: sidebarController)
            controller.addSplitViewItem(item)
            controller.addSplitViewItem(NSSplitViewItem(viewController: NSViewController()))
            sidebarItem = item
            splitView = controller.splitView
            window.contentViewController = controller
        } else {
            sidebarItem = nil
            splitView = NSSplitView(frame: NSRect(x: 0, y: 0, width: 900, height: 640))
            splitView.isVertical = true
            splitView.addArrangedSubview(sidebarView)
            splitView.addArrangedSubview(NSView(frame: NSRect(x: 233, y: 0, width: 667, height: 640)))
            window.contentView = splitView
        }
        window.orderBack(nil)
        window.contentView?.layoutSubtreeIfNeeded()
    }

    var widthConstraints: [NSLayoutConstraint] {
        // NSSplitViewController wraps the content view in a column container.
        splitView.subviews.flatMap(\.constraints).filter {
            $0.identifier?.hasPrefix("FinallyExplorer.sidebar.") == true
        }
    }

    func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while condition() == false, ContinuousClock.now < deadline {
            await Task.yield()
            window.contentView?.layoutSubtreeIfNeeded()
        }
        return condition()
    }

    func close() {
        attachment.detach()
        window.close()
    }
}
