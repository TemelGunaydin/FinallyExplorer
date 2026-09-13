import SwiftUI

struct ExplorerSettingsView: View {
    let settings: ExplorerAISettings
    var folderAccess: FolderAccessModel? = nil

    var body: some View {
        TabView {
            Tab("On-Device AI", systemImage: "sparkles") {
                ExplorerAISettingsView(settings: settings)
            }

            Tab("Privacy & Support", systemImage: "hand.raised") {
                ExplorerPrivacySettingsView()
            }

            if let folderAccess {
                Tab("Folder Access", systemImage: "folder.badge.gearshape") {
                    FolderAccessSettingsView(access: folderAccess)
                }
            }
        }
        .frame(width: 580, height: 720)
        .accessibilityIdentifier("explorer-settings-view")
    }
}
