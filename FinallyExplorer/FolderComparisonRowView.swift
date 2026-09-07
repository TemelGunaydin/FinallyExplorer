import SwiftUI

struct FolderComparisonRowView: View {
    @Environment(\.explorerTheme) private var theme
    let row: FolderComparisonRow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: (row.source ?? row.destination)?.state.isDirectory == true ? "folder" : "doc")
                .foregroundStyle(theme.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.relativePath)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(row.relativePath)
                    .textSelection(.enabled)
                if let reason = row.source?.skippedReason ?? row.destination?.skippedReason {
                    Text(reason).font(.caption).foregroundStyle(theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Label(row.status.rawValue, systemImage: statusSymbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(theme.control, in: .rect(cornerRadius: 6))
                .fixedSize()
        }
        .padding(10)
        .background(theme.row, in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private var statusSymbol: String {
        switch row.status {
        case .onlySource: "arrow.right.circle"
        case .onlyDestination: "arrow.left.circle"
        case .same: "checkmark.circle"
        case .different: "not.equal"
        case .folder: "folder"
        case .conflict: "exclamationmark.triangle"
        case .skipped: "minus.circle"
        }
    }
}
