import SwiftUI

struct OfflineCatalogRemovalSheet: View {
    @Environment(\.explorerTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let summary: OfflineCatalogSummary
    let onConfirm: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Remove Saved Catalog?", systemImage: "externaldrive.badge.minus")
                .font(.title2.weight(.semibold))
            Text(summary.title).font(.headline).lineLimit(3).truncationMode(.middle)
            Text("This removes saved names and metadata from this Mac. Original files on the disk will not be changed. You can scan the disk again later.")
                .foregroundStyle(theme.textSecondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Remove Saved Catalog", role: .destructive) { onConfirm(); dismiss() }
                    .accessibilityIdentifier("offline-catalog-remove-confirm")
            }
        }
        .padding(24).frame(width: 500)
        .foregroundStyle(theme.textPrimary).background(theme.panel).tint(theme.accent)
        .accessibilityElement(children: .contain).accessibilityIdentifier("offline-catalog-removal-sheet")
    }
}
