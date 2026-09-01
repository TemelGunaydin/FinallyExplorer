//
//  SidebarSplitViewBehaviorTests.swift
//  FinallyExplorerTests
//

import AppKit
import Testing
@testable import FinallyExplorer

@MainActor
struct SidebarSplitViewBehaviorTests {
    @Test("Sidebar divider is bounded and cannot collapse the sidebar")
    func dividerKeepsSidebarVisibleWithinBounds() async {
        let sidebarController = NSViewController()
        let attachment = SidebarSplitViewAttachmentView(
            minimumThickness: SidebarSplitViewBehaviorInstaller.minimumWidth,
            maximumThickness: SidebarSplitViewBehaviorInstaller.maximumWidth
        )
        sidebarController.view = attachment

        let splitController = NSSplitViewController()
        let sidebarItem = NSSplitViewItem(
            sidebarWithViewController: sidebarController
        )
        splitController.addSplitViewItem(sidebarItem)
        splitController.addSplitViewItem(
            NSSplitViewItem(viewController: NSViewController())
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = splitController
        window.orderFront(nil)
        defer { window.close() }

        window.contentView?.layoutSubtreeIfNeeded()
        attachment.scheduleConfiguration()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(
            sidebarItem.minimumThickness
                == SidebarSplitViewBehaviorInstaller.minimumWidth
        )
        #expect(
            sidebarItem.maximumThickness
                == SidebarSplitViewBehaviorInstaller.maximumWidth
        )
        #expect(sidebarItem.canCollapse == false)
        #expect(sidebarItem.canCollapseFromWindowResize == false)
    }
}
