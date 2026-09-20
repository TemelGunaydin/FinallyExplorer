import SwiftUI

struct FolderAccessSettingsView: View {
    @Environment(\.explorerTheme) private var theme
    let access: FolderAccessModel
    @State private var isChoosing = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Text("Remembered folders")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(theme.textSecondary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    Button("Allow a Folder…", systemImage: "folder.badge.plus", action: chooseFolder)
                        .buttonStyle(ExplorerDialogButtonStyle(isProminent: true))
                        .disabled(isChoosing)
                        .accessibilityIdentifier("settings-allow-folder")
                }

                if let message = errorMessage ?? access.storageError {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("folder-access-error")
                }

                if access.folders.isEmpty == false || access.storageError == nil {
                    VStack(alignment: .leading, spacing: 16) {
                        if access.folders.isEmpty {
                            Text("No folders remembered yet.")
                                .foregroundStyle(theme.textSecondary)
                                .padding(.vertical, 12)
                                .accessibilityIdentifier("folder-access-empty")
                        }
                        ForEach(access.folders) { folder in
                            FolderAccessSettingsRow(folder: folder) { forget(folder.id) }
                            if folder.id != access.folders.last?.id {
                                Divider().overlay(theme.divider)
                            }
                        }
                        if access.folders.contains(where: { $0.isAvailable == false }) {
                            Button("Retry Unavailable", systemImage: "arrow.clockwise") {
                                access.restoreUnavailableFolders()
                            }
                            .accessibilityIdentifier("folder-access-retry")
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.control, in: .rect(cornerRadius: 14))
                }

                if access.forgottenForNextLaunch {
                    Label("Saved access removed for next launch.", systemImage: "checkmark.circle")
                        .font(.callout)
                        .accessibilityIdentifier("folder-access-forgotten")
                }
                if access.folders.isEmpty == false || access.forgottenForNextLaunch {
                    Text("Forget clears saved access. Current access lasts until you quit; files, favorites and macOS permissions stay unchanged.")
                        .font(.callout)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
        }
        .frame(width: 580)
        .frame(maxHeight: .infinity)
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
