import SwiftUI

struct FolderOrganizationReviewSheet: View {
    @Environment(\.explorerTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let plan: FolderOrganizationMovePlan
    var canConfirm = true
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Review Folder Organization", systemImage: "folder.badge.gearshape")
                .font(.title2.weight(.semibold))
            Text(plan.snapshot.rootURL.path)
                .font(.callout).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
            Text("Files to move: \(plan.moves.count) · New folders: \(plan.foldersToCreate.count)")
                .font(.headline)
            Text("Only these files will move into subfolders on the same disk. File names stay the same. Existing files are never overwritten. Changed files or conflicting destinations stop the operation.")
                .font(.callout)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if plan.foldersToCreate.isEmpty == false {
                        Text("Create: \(plan.foldersToCreate.joined(separator: ", "))")
                            .font(.callout.weight(.medium)).textSelection(.enabled)
                    }
                    ForEach(plan.moves) { move in
                        FolderOrganizationPathView(source: move.sourceName, destination: move.destinationPath)
                    }
                }
            }
            Text("If stopped, completed moves and created folders stay in place. There is no automatic undo for this operation.")
                .font(.callout).foregroundStyle(theme.textSecondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("organization-review-cancel")
                Button("Move Files", systemImage: "folder", action: onConfirm)
                    .buttonStyle(ExplorerPanePrimaryButtonStyle(isCompact: false))
                    .disabled(canConfirm == false)
                    .accessibilityIdentifier("organization-confirm")
            }
        }
        .padding(22).frame(width: 620, height: 560)
        .foregroundStyle(theme.textPrimary).background(theme.panel).tint(theme.accent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("organization-review")
    }
}
