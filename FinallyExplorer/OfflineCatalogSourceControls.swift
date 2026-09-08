import SwiftUI

struct OfflineCatalogSourceControls: View {
    @Environment(\.explorerTheme) private var theme
    @Bindable var model: OfflineCatalogModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Menu("Connected Disks", systemImage: "externaldrive") {
                    if model.connectedVolumes.isEmpty { Text("No supported external disk connected") }
                    ForEach(model.connectedVolumes, id: \.rootURL) { volume in
                        Button(volume.name) { model.prepare(volume.rootURL) }
                    }
                }
                .fixedSize().accessibilityIdentifier("offline-catalog-volume-menu")
                Button("Choose Folder…", action: model.chooseFolder)
                    .accessibilityIdentifier("offline-catalog-choose-folder")
                Spacer()
                Toggle("Include hidden items", isOn: $model.includesHidden)
            }
            if let source = model.source {
                HStack(spacing: 12) {
                    Label(source.rootURL.path, systemImage: "folder")
                        .font(.callout).lineLimit(2).truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    Button("Scan & Save", systemImage: "externaldrive.badge.plus") { model.scanAndSave() }
                        .buttonStyle(ExplorerPanePrimaryButtonStyle(isCompact: false))
                        .accessibilityIdentifier("offline-catalog-save")
                }
                Text("Only this folder will be scanned. Existing saved metadata is replaced only after a successful scan.")
                    .font(.caption).foregroundStyle(theme.textSecondary)
            }
        }
        .disabled(model.isWorking)
        .padding(12).background(theme.control, in: .rect(cornerRadius: 12))
    }
}
