//
//  WorkspaceSplitContainer.swift
//  FinallyExplorer
//

import SwiftUI

/// Keeps nested panes inside the `NavigationSplitView` detail proposal.
/// AppKit-backed `HSplitView` and `VSplitView` can rebase themselves to the
/// whole unified-titlebar window when their child tree changes at runtime.
struct WorkspaceSplitContainer<First: View, Second: View>: View {
    @Environment(\.explorerTheme) private var theme

    let axis: WorkspaceSplitAxis
    let first: First
    let second: Second

    @State private var firstFraction: CGFloat = 0.5
    @GestureState private var dragTranslation: CGFloat = 0

    private let dividerHitLength: CGFloat = 7

    init(
        axis: WorkspaceSplitAxis,
        @ViewBuilder first: () -> First,
        @ViewBuilder second: () -> Second
    ) {
        self.axis = axis
        self.first = first()
        self.second = second()
    }

    var body: some View {
        GeometryReader { proxy in
            let totalLength = axis == .sideBySide
                ? proxy.size.width
                : proxy.size.height
            let availableLength = max(0, totalLength - dividerHitLength)
            let firstLength = resolvedFirstLength(
                availableLength: availableLength,
                translation: dragTranslation
            )
            let secondLength = max(0, availableLength - firstLength)

            switch axis {
            case .sideBySide:
                HStack(spacing: 0) {
                    first
                        .frame(
                            width: firstLength,
                            height: proxy.size.height
                        )
                        .clipped()

                    splitDivider(availableLength: availableLength)

                    second
                        .frame(
                            width: secondLength,
                            height: proxy.size.height
                        )
                        .clipped()
                }

            case .stacked:
                VStack(spacing: 0) {
                    first
                        .frame(
                            width: proxy.size.width,
                            height: firstLength
                        )
                        .clipped()

                    splitDivider(availableLength: availableLength)

                    second
                        .frame(
                            width: proxy.size.width,
                            height: secondLength
                        )
                        .clipped()
                }
            }
        }
    }

    private func resolvedFirstLength(
        availableLength: CGFloat,
        translation: CGFloat
    ) -> CGFloat {
        guard availableLength > 0 else { return 0 }

        let preferredMinimum = axis == .sideBySide ? 280.0 : 220.0
        let minimum = min(preferredMinimum, availableLength / 2)
        let maximum = max(minimum, availableLength - minimum)
        let proposed = availableLength * firstFraction + translation
        return min(max(proposed, minimum), maximum)
    }

    private func splitDivider(availableLength: CGFloat) -> some View {
        ZStack {
            Color.clear

            Rectangle()
                .fill(theme.divider)
                .frame(
                    width: axis == .sideBySide ? 1 : nil,
                    height: axis == .stacked ? 1 : nil
                )
        }
        .frame(
            width: axis == .sideBySide ? dividerHitLength : nil,
            height: axis == .stacked ? dividerHitLength : nil
        )
        .contentShape(Rectangle())
        .gesture(dragGesture(availableLength: availableLength))
        .help("Drag to resize the adjacent panes")
        .accessibilityElement()
        .accessibilityIdentifier(
            axis == .sideBySide
                ? "workspace-column-divider"
                : "workspace-row-divider"
        )
        .accessibilityLabel(
            axis == .sideBySide ? "Resize columns" : "Resize rows"
        )
        .accessibilityHint("Drag to resize the adjacent panes")
        .accessibilityAdjustableAction(adjustSplit)
    }

    private func dragGesture(availableLength: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($dragTranslation) { value, state, _ in
                state = axis == .sideBySide
                    ? value.translation.width
                    : value.translation.height
            }
            .onEnded { value in
                guard availableLength > 0 else { return }

                let translation = axis == .sideBySide
                    ? value.translation.width
                    : value.translation.height
                firstFraction = resolvedFirstLength(
                    availableLength: availableLength,
                    translation: translation
                ) / availableLength
            }
    }

    private func adjustSplit(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment:
            firstFraction = min(0.9, firstFraction + 0.05)
        case .decrement:
            firstFraction = max(0.1, firstFraction - 0.05)
        @unknown default:
            break
        }
    }
}
