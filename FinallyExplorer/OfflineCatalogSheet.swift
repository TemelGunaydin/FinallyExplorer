import SwiftUI

struct OfflineCatalogSheet: View {
    @Environment(\.explorerTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: OfflineCatalogModel
    let mountedVolumes: MountedVolumeMonitor
    let onReveal: @MainActor @Sendable (URL, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Text("Search saved disk metadata even when the disk is disconnected. Names, paths, sizes and dates only — no file contents. Nothing is scanned automatically.")
                .font(.callout).foregroundStyle(theme.textSecondary)
            OfflineCatalogSourceControls(model: model)
            if model.catalogs.isEmpty == false { catalogControls }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).textSelection(.enabled)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.accentSoft, in: .rect(cornerRadius: 8))
                    .accessibilityIdentifier("offline-catalog-error")
            }
            if let notice = model.notice {
                Text(notice).font(.callout).foregroundStyle(theme.textPrimary)
                    .accessibilityIdentifier("offline-catalog-notice")
            }
            results.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                if model.isWorking {
                    Button(model.isCancelling ? "Stopping…" : "Cancel", action: model.cancel)
                        .disabled(model.isCancelling).accessibilityIdentifier("offline-catalog-stop")
                }
                Spacer()
                Button("Check Connection", systemImage: "arrow.clockwise") { model.refreshConnections() }
                    .disabled(model.isWorking).accessibilityIdentifier("offline-catalog-check-connection")
            }
        }
        .padding(22).frame(width: 820, height: 720)
        .foregroundStyle(theme.textPrimary).background(theme.panel).tint(theme.accent)
        .accessibilityElement(children: .contain).accessibilityIdentifier("offline-catalog-sheet")
        .interactiveDismissDisabled(model.isWorking)
        .sheet(item: $model.removal) { summary in
            OfflineCatalogRemovalSheet(summary: summary) { model.confirmRemoval(summary) }
                .environment(\.explorerTheme, theme)
        }
        .task { if model.didAttemptLoad == false { await model.load()?.value } }
        .onChange(of: mountedVolumes.revision) { model.refreshConnections() }
        .onDisappear { model.cancel() }
    }

    private var header: some View {
        HStack {
            Label("Offline Catalogs", systemImage: "externaldrive")
                .font(.system(.title2, design: .rounded).weight(.semibold))
            Spacer()
            Text("LOCAL METADATA ONLY").font(.caption.weight(.semibold))
                .padding(6).background(theme.accentSoft, in: .rect(cornerRadius: 6))
            Button("Close Catalogs", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly).buttonStyle(ExplorerPaneUtilityButtonStyle())
                .keyboardShortcut(.cancelAction).disabled(model.isWorking)
                .accessibilityIdentifier("offline-catalog-close")
        }
    }

    private var catalogControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Saved catalog", selection: $model.selectedID) {
                    Text("Select catalog").tag(Optional<UUID>.none)
                    ForEach(model.catalogs) { summary in Text(summary.title).lineLimit(1).truncationMode(.middle).tag(Optional(summary.id)) }
                }
                .frame(minWidth: 0, maxWidth: .infinity)
                .disabled(model.isWorking).accessibilityIdentifier("offline-catalog-picker")
                Button("Refresh Snapshot") { model.refreshSelected() }
                    .disabled(model.isConnected == false || model.isWorking)
                    .accessibilityIdentifier("offline-catalog-refresh")
                Button("Remove Saved Catalog", systemImage: "trash") { model.removal = model.selected }
                    .labelStyle(.iconOnly).disabled(model.selected == nil || model.isWorking)
                    .help("Remove saved metadata only; original files are kept")
                    .accessibilityIdentifier("offline-catalog-remove")
            }
            if let selected = model.selected {
                HStack {
                    Label(model.connectionDescription, systemImage: model.isConnected ? "externaldrive" : "externaldrive.badge.xmark")
                        .accessibilityIdentifier("offline-catalog-connection")
                    Spacer()
                    Text("Scanned \(selected.scannedAt.formatted(date: .abbreviated, time: .shortened))")
                }
                Text("\(selected.entryCount) saved · \(selected.skippedCount) unsupported entries skipped · \(selected.excludedHiddenCount) hidden entries excluded")
            }
        }
        .font(.caption).foregroundStyle(theme.textSecondary)
    }

    @ViewBuilder private var results: some View {
        if let progress = model.progress {
            FileToolsProgressView(progress: progress, isCancelling: model.isCancelling,
                detail: "No file contents are copied. Canceling a scan keeps the previously saved catalog.")
        } else if model.selected != nil {
            OfflineCatalogResultsView(model: model) { url, isDirectory in
                onReveal(url, isDirectory)
                dismiss()
            }
        } else {
            ContentUnavailableView("Catalog an External Disk", systemImage: "externaldrive.badge.plus",
                description: Text("Choose a connected disk or a folder on it, then select Scan & Save. Its saved metadata will remain searchable offline."))
        }
    }
}
