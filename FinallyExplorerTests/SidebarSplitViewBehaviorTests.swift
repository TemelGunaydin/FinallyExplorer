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
    func dividerKeepsSidebarVisibleWithinBounds() async throws {
        let fixture = SidebarSplitViewTestFixture()
        defer { fixture.close() }
        let sidebarItem = try #require(fixture.sidebarItem)

        #expect(await fixture.waitUntil {
            sidebarItem.maximumThickness == 280 && sidebarItem.minimumThickness == 210
        })
        #expect(sidebarItem.canCollapse == false)
        #expect(sidebarItem.canCollapseFromWindowResize == false)

        fixture.splitView.setPosition(650, ofDividerAt: 0)
        #expect(await fixture.waitUntil { fixture.sidebarView.frame.width <= 280.5 })
        fixture.splitView.setPosition(20, ofDividerAt: 0)
        #expect(await fixture.waitUntil { fixture.sidebarView.frame.width >= 209.5 })
    }

    @Test("Layout restores limits overwritten after initial attachment")
    func restoresLimitsAfterNativeReconfiguration() async throws {
        let fixture = SidebarSplitViewTestFixture()
        defer { fixture.close() }
        let sidebarItem = try #require(fixture.sidebarItem)
        try #require(await fixture.waitUntil { sidebarItem.maximumThickness == 280 })

        sidebarItem.minimumThickness = 0
        sidebarItem.maximumThickness = 900
        sidebarItem.canCollapse = true
        sidebarItem.canCollapseFromWindowResize = true
        fixture.attachment.needsLayout = true
        fixture.attachment.layoutSubtreeIfNeeded()

        #expect(await fixture.waitUntil {
            sidebarItem.maximumThickness == 280
                && sidebarItem.minimumThickness == 210
                && sidebarItem.canCollapse == false
                && sidebarItem.canCollapseFromWindowResize == false
        })
    }

    @Test("A split without an NSSplitViewController still bounds the real column")
    func constrainsColumnWithoutNativeController() async throws {
        let fixture = SidebarSplitViewTestFixture(usesSplitController: false)
        defer { fixture.close() }
        try #require(fixture.splitView.delegate is NSSplitViewController == false)
        try #require(await fixture.waitUntil { fixture.widthConstraints.count == 2 })

        #expect(fixture.widthConstraints.allSatisfy { $0.isActive })
        fixture.splitView.setPosition(700, ofDividerAt: 0)
        #expect(await fixture.waitUntil { fixture.sidebarView.frame.width <= 280.5 })
        fixture.splitView.setPosition(30, ofDividerAt: 0)
        #expect(await fixture.waitUntil { fixture.sidebarView.frame.width >= 209.5 })
    }

    @Test("Hiding through the toolbar releases the minimum width, then restores it")
    func explicitHidingAndTeardownRemainSupported() async throws {
        let fixture = SidebarSplitViewTestFixture()
        defer { fixture.close() }
        try #require(await fixture.waitUntil { fixture.widthConstraints.count == 2 })
        let constraints = fixture.widthConstraints
        let minimum = try #require(constraints.first { $0.relation == .greaterThanOrEqual })
        let maximum = try #require(constraints.first { $0.relation == .lessThanOrEqual })

        fixture.attachment.isSidebarVisible = false
        #expect(minimum.isActive == false)
        #expect(maximum.isActive)
        fixture.attachment.isSidebarVisible = true
        #expect(minimum.isActive)

        fixture.attachment.removeFromSuperview()
        #expect(constraints.allSatisfy { $0.isActive == false })
        #expect(fixture.widthConstraints.isEmpty)
    }
}
