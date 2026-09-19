import CoreGraphics
import Testing
@testable import FinallyExplorer

struct PaneToolbarArrangementTests {
    private let singlePaneGroups = [
        CGSize(width: 236, height: 44),
        CGSize(width: 210, height: 36),
        CGSize(width: 118, height: 34)
    ]

    @Test("A wide toolbar keeps navigation leading and both action groups trailing")
    func wideToolbar() {
        let layout = PaneToolbarArrangement(groupSizes: singlePaneGroups, availableWidth: 800)
        #expect(layout.size == CGSize(width: 800, height: 44))
        #expect(layout.frames[0].minX == 0)
        #expect(layout.frames[1].minX == 464)
        #expect(layout.frames[2].maxX == 800)
        #expect(layout.frames.allSatisfy { $0.midY == 22 })
    }

    @Test("A narrow toolbar moves actions together below the location picker")
    func actionsWrapTogether() {
        let layout = PaneToolbarArrangement(groupSizes: singlePaneGroups, availableWidth: 500)
        #expect(layout.size == CGSize(width: 500, height: 88))
        #expect(layout.frames[0].origin == .zero)
        #expect(layout.frames[1].minY == 52)
        #expect(layout.frames[1].midY == layout.frames[2].midY)
        #expect(layout.frames[2].maxX == 500)
    }

    @Test("The active compact pane fits all seven actions on its second row")
    func minimumGridPane() {
        let layout = PaneToolbarArrangement(groupSizes: [
            CGSize(width: 226, height: 38), // Location plus Back.
            CGSize(width: 118, height: 36), // New Folder, Terminal, hidden items.
            CGSize(width: 160, height: 34)  // Two splits, reset, close.
        ], availableWidth: WorkspaceLayoutMetrics.minimumPaneWidth - 50)
        #expect(layout.size == CGSize(width: 290, height: 82))
        #expect(layout.frames[1].midY == layout.frames[2].midY)
        #expect(layout.frames[2].maxX == 290)
    }

    @Test("Narrow proposals never overlap or clip complete button groups", arguments: [
        CGFloat(0), 236, 290, 335, 336, 500, 579, 580, 800, 1_200
    ])
    func framesRemainContained(width: CGFloat) {
        let layout = PaneToolbarArrangement(groupSizes: singlePaneGroups, availableWidth: width)
        let bounds = CGRect(origin: .zero, size: layout.size)
        #expect(layout.frames.count == singlePaneGroups.count)
        for index in layout.frames.indices {
            #expect(layout.frames[index].size == singlePaneGroups[index])
            #expect(bounds.contains(layout.frames[index]))
            for next in layout.frames.indices where next > index {
                #expect(layout.frames[index].intersects(layout.frames[next]) == false)
            }
        }
    }

    @Test("Exactly fitting action groups stay together; one point less wraps")
    func wrapBoundary() {
        let fitting = PaneToolbarArrangement(groupSizes: singlePaneGroups, availableWidth: 336)
        let narrower = PaneToolbarArrangement(groupSizes: singlePaneGroups, availableWidth: 335)
        #expect(fitting.frames[1].midY == fitting.frames[2].midY)
        #expect(narrower.frames[2].minY > narrower.frames[1].maxY)
        #expect(narrower.size.height == 130)
    }

    @Test("Unspecified and infinite proposals return a finite ideal size")
    func idealSize() {
        let ideal = PaneToolbarArrangement(groupSizes: singlePaneGroups, availableWidth: nil)
        let infinite = PaneToolbarArrangement(groupSizes: singlePaneGroups, availableWidth: .infinity)
        #expect(ideal.size == CGSize(width: 580, height: 44))
        #expect(infinite.frames == ideal.frames)
        #expect(infinite.size == ideal.size)
    }

    @Test("Empty toolbar has no rows or negative height")
    func emptyToolbar() {
        let layout = PaneToolbarArrangement(groupSizes: [], availableWidth: 800)
        #expect(layout.size == .zero)
        #expect(layout.frames.isEmpty)
    }
}
