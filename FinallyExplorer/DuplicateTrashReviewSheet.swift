import SwiftUI

struct DuplicateTrashReviewSheet: View {
    @Environment(\.explorerTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let plan: DuplicateTrashPlan
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Review Duplicate Removal", systemImage: "trash")
                .font(.title2.weight(.semibold))
            Text(plan.snapshot.rootURL.path)
                .font(.callout).lineLimit(2).truncationMode(.middle)
                .textSelection(.enabled)
            Text("Files: \(plan.pairs.count) · \(plan.selectedBytes.formatted(.byteCount(style: .file))) of file data")
                .font(.headline)
            Text("Only the selected files will move to Trash. At least one matching copy stays in each group. Contents are checked again before removal; names, dates, tags and permissions may differ.")
                .font(.callout)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(plan.pairs) { pair in
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Trash: \(pair.remove.relativePath)", systemImage: "trash")
                            Label("Keep: \(pair.keep.relativePath)", systemImage: "checkmark.shield")
                                .foregroundStyle(theme.textSecondary)
                        }
                        .font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(theme.control, in: .rect(cornerRadius: 10))
                    }
                }
            }
            Text("Nothing is permanently deleted. Space is not reclaimed until Trash is emptied, and shared storage may reduce the amount recovered.")
                .font(.caption).foregroundStyle(theme.textSecondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("duplicate-trash-cancel")
                Button("Move to Trash", systemImage: "trash", action: onConfirm)
                    .buttonStyle(ExplorerPanePrimaryButtonStyle(isCompact: false))
                    .accessibilityIdentifier("duplicate-trash-confirm")
            }
        }
        .padding(22)
        .frame(width: 620, height: 540)
        .foregroundStyle(theme.textPrimary)
        .background(theme.panel)
        .tint(theme.accent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("duplicate-trash-review")
    }
}
