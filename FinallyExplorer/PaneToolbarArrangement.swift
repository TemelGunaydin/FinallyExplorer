import CoreGraphics

/// Wraps whole control groups, preserving order and keeping actions trailing.
/// Kept independent of SwiftUI so every layout boundary can be tested directly.
nonisolated struct PaneToolbarArrangement {
    let size: CGSize
    let frames: [CGRect]

    init(groupSizes: [CGSize], availableWidth: CGFloat?, spacing: CGFloat = 8) {
        guard groupSizes.isEmpty == false else {
            size = .zero
            frames = []
            return
        }

        let idealWidth = groupSizes.reduce(0) { $0 + $1.width }
            + CGFloat(groupSizes.count - 1) * spacing
        let widestGroup = groupSizes.map(\.width).max() ?? 0
        let proposedWidth = availableWidth.flatMap { $0.isFinite ? $0 : nil }
            ?? idealWidth
        let width = max(widestGroup, proposedWidth)
        var rows: [[Int]] = [[]]
        var rowWidth: CGFloat = 0

        for index in groupSizes.indices {
            let gap = rows[rows.count - 1].isEmpty ? 0 : spacing
            // Keep file actions beside the split/preview controls when the
            // full toolbar no longer fits next to the location picker.
            let startsActionsRow = index == 1 && idealWidth > width
            if startsActionsRow || rowWidth + gap + groupSizes[index].width > width,
               rows[rows.count - 1].isEmpty == false {
                rows.append([])
                rowWidth = 0
            }
            if rows[rows.count - 1].isEmpty == false { rowWidth += spacing }
            rows[rows.count - 1].append(index)
            rowWidth += groupSizes[index].width
        }

        var result = Array(repeating: CGRect.zero, count: groupSizes.count)
        var y: CGFloat = 0
        for row in rows {
            let height = row.map { groupSizes[$0].height }.max() ?? 0
            let usedWidth = row.reduce(0) { $0 + groupSizes[$1].width }
                + CGFloat(row.count - 1) * spacing
            let containsNavigation = row.first == 0
            var x: CGFloat = containsNavigation ? 0 : width - usedWidth

            for index in row {
                let group = groupSizes[index]
                result[index] = CGRect(
                    x: x, y: y + (height - group.height) / 2,
                    width: group.width, height: group.height
                )
                x += group.width + spacing
                if index == 0 { x += width - usedWidth }
            }
            y += height + spacing
        }
        size = CGSize(width: width, height: y - spacing)
        frames = result
    }
}
