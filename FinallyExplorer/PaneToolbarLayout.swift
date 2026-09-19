import SwiftUI

/// Reflows the existing views instead of duplicating stateful menus in fallbacks.
struct PaneToolbarLayout: Layout {
    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGSize {
        arrangement(for: subviews, width: proposal.width).size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize,
        subviews: Subviews, cache: inout ()
    ) {
        let arrangement = arrangement(for: subviews, width: bounds.width)
        for (subview, frame) in zip(subviews, arrangement.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrangement(for subviews: Subviews, width: CGFloat?) -> PaneToolbarArrangement {
        PaneToolbarArrangement(
            groupSizes: subviews.map { $0.sizeThatFits(.unspecified) },
            availableWidth: width
        )
    }
}
