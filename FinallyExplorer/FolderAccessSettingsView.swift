import SwiftUI

struct FolderAccessSettingsView: View {
    @Environment(\.explorerTheme) private var theme
    let access: FolderAccessModel
    @State private var isChoosing = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Folder Access", systemImage: "folder.badge.gearshape")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                Text("Choose folders once and remember access on this Mac. macOS privacy and file permissions still apply.")
                    .foregroundStyle(theme.textSecondary)

                Button("Allow a Folder…", systemImage: "folder.badge.plus") { chooseFolder() }
                    .buttonStyle(ExplorerDialogButtonStyle(isProminent: true))
                    .disabled(isChoosing)
                    .accessibilityIdentifier("settings-allow-folder")

                if let message = errorMessage ?? access.storageError {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(theme.textPrimary)
                        .accessibilityIdentifier("folder-access-error")
                }

                VStack(alignment: .leading, spacing: 16) {
                    if access.folders.isEmpty {
                        Text("No folders remembered yet.")
                            .foregroundStyle(theme.textSecondary)
                    }
                    ForEach(access.folders) { folder in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(folder.url.lastPathComponent.isEmpty ? "Startup Disk" : folder.url.lastPathComponent,
                                      systemImage: folder.isAvailable ? "folder" : "folder.badge.questionmark")
                                    .font(ExplorerTheme.actionFont)
                                    .lineLimit(2)
                                Spacer(minLength: 8)
                                Button("Forget") { forget(folder.id) }
                                    .help("Do not restore this folder's access on the next launch")
                                    .accessibilityLabel("Forget access to \(folder.url.lastPathComponent)")
                            }
                            Text(folder.url.path)
                                .font(.callout)
                                .foregroundStyle(theme.textSecondary)
                                .textSelection(.enabled)
                            if folder.isAvailable == false {
                                Text("Reconnect its disk or choose this folder again.")
                                    .font(.callout)
                                    .foregroundStyle(theme.textSecondary)
                            }
                        }
                        if folder.id != access.folders.last?.id {
                            Divider().overlay(theme.divider)
                        }
                    }
                    if access.folders.contains(where: { $0.isAvailable == false }) {
                        Button("Retry Unavailable Folders", systemImage: "arrow.clockwise") {
                            access.restoreUnavailableFolders()
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.control, in: .rect(cornerRadius: 14))

                if access.forgottenForNextLaunch {
                    Label("Folder access will no longer be restored after you quit and reopen the app.", systemImage: "checkmark.circle")
                }
                Text("Forgetting access does not remove files or sidebar favorites. Current access lasts until the app quits so active file operations can finish. It does not revoke access granted separately in macOS Settings.")
                    .font(.callout)
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(theme.textPrimary)
        .background(theme.panel)
        .tint(theme.accent)
        .buttonStyle(ExplorerDialogButtonStyle())
        .accessibilityIdentifier("folder-access-settings-view")
    }

    private func chooseFolder() {
        guard isChoosing == false else { return }
        isChoosing = true
        errorMessage = nil
        Task {
            defer { isChoosing = false }
            do { _ = try await FolderAccessPicker.choose(using: access, startingAt: nil) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func forget(_ id: UUID) {
        do { try access.forget(id); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}
