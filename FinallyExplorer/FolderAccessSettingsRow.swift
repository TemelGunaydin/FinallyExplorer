import SwiftUI

struct FolderAccessSettingsRow: View {
    @Environment(\.explorerTheme) private var theme
    let folder: RememberedFolderAccess
    let onForget: () -> Void

    private var title: String {
        folder.url.lastPathComponent.isEmpty ? "Startup Disk" : folder.url.lastPathComponent
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Label(title, systemImage: folder.isAvailable ? "folder" : "folder.badge.questionmark")
                    .font(.headline)
                    .lineLimit(2)
                Text(folder.url.path)
                    .font(.callout)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(folder.url.path)
                    .textSelection(.enabled)
                if folder.isAvailable == false {
                    Text("Unavailable — reconnect or allow again.")
                        .font(.callout)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Forget", action: onForget)
                .fixedSize()
                .help("Forget saved access. Files stay unchanged; current access lasts until you quit.")
                .accessibilityLabel("Forget access to \(title)")
                .accessibilityIdentifier("folder-access-forget-\(folder.id)")
        }
    }
}
