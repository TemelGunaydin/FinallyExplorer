import SwiftUI

struct VerifiedCopyReviewSheet: View {
    @Environment(\.explorerTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let plan: VerifiedCopyPlan
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Review Verified Copy", systemImage: "checkmark.shield")
                .font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("From", value: plan.snapshot.sourceURL.path)
                    .help(plan.snapshot.sourceURL.path)
                LabeledContent("To", value: plan.snapshot.destinationURL.path)
                    .help(plan.snapshot.destinationURL.path)
            }
            .font(.callout)
            .textSelection(.enabled)
            .lineLimit(3)
            .truncationMode(.middle)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .background(theme.control, in: .rect(cornerRadius: 10))
            Text("Files: \(plan.fileCount) · Folders: \(plan.directoryCount) · \(plan.byteCount.formatted(.byteCount(style: .file)))")
                .font(.headline)
            Text("Add only these missing items. Existing items will never be overwritten or deleted. Each file’s data is checked with SHA‑256 before it is added.")
                .font(.callout)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(plan.entries, id: \.relativePath) { entry in
                        Label(entry.relativePath, systemImage: entry.state.isDirectory ? "folder" : "doc")
                            .font(.callout)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .help(entry.relativePath)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .background(theme.control, in: .rect(cornerRadius: 10))
            Text("Hidden items follow your comparison setting. Packages, links, special files, mounted subfolders and cloud placeholders are skipped. File metadata is copied but not verified; new folders use standard permissions. On cancellation or failure, completed items stay in the destination.")
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("verified-copy-cancel")
                Button("Copy & Verify", systemImage: "checkmark.shield", action: onConfirm)
                    .buttonStyle(ExplorerPanePrimaryButtonStyle(isCompact: false))
                    .accessibilityIdentifier("verified-copy-confirm")
            }
        }
        .padding(22)
        .frame(width: 600, height: 540)
        .foregroundStyle(theme.textPrimary)
        .background(theme.panel)
        .tint(theme.accent)
        .accessibilityIdentifier("verified-copy-review")
    }
}
