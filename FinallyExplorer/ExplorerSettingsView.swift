import SwiftUI

struct ExplorerSettingsView: View {
    let settings: ExplorerAISettings

    var body: some View {
        TabView {
            Tab("On-Device AI", systemImage: "sparkles") {
                ExplorerAISettingsView(settings: settings)
            }

            Tab("Privacy & Support", systemImage: "hand.raised") {
                ExplorerPrivacySettingsView()
            }
        }
        .frame(width: 580, height: 720)
        .accessibilityIdentifier("explorer-settings-view")
    }
}
