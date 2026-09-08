import SwiftUI

struct OfflineCatalogResultsView: View {
    @Environment(\.explorerTheme) private var theme
    @Bindable var model: OfflineCatalogModel
    let onReveal: @MainActor @Sendable (URL, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            filters
            HStack {
                Text("Showing \(model.rows.count) of \(model.totalMatches) matches")
                    .accessibilityIdentifier("offline-catalog-match-count")
                Spacer()
                if model.isSearching { ProgressView().controlSize(.small).tint(theme.textPrimary).accessibilityLabel("Searching saved metadata") }
                Text("Saved metadata, not a live folder")
            }
            .font(.caption).foregroundStyle(theme.textSecondary)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.rows) { entry in row(entry) }
                }
            }
            .overlay {
                if model.rows.isEmpty && model.isSearching == false {
                    ContentUnavailableView("No Saved Matches", systemImage: "magnifyingglass", description: Text("Try another name, path or filter. Refresh the catalog to include newer files."))
                }
            }
        }
    }

    private var filters: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").accessibilityHidden(true)
                TextField("Search saved names and paths", text: $model.query)
                    .textFieldStyle(.plain).autocorrectionDisabled()
                    .accessibilityIdentifier("offline-catalog-search")
                if model.query.isEmpty == false {
                    Button("Clear Search", systemImage: "xmark.circle.fill") { model.query = "" }
                        .labelStyle(.iconOnly).buttonStyle(.plain)
                }
            }
            .padding(10).background(theme.control, in: .rect(cornerRadius: 8))
            HStack(spacing: 14) {
                HStack {
                    Text("Extension")
                    TextField("Extension", text: $model.fileExtension, prompt: Text("e.g. pdf"))
                        .textFieldStyle(.plain).padding(6)
                        .autocorrectionDisabled()
                        .background(theme.control, in: .rect(cornerRadius: 6))
                        .frame(width: 80).accessibilityLabel("File extension")
                        .accessibilityIdentifier("offline-catalog-extension")
                }
                Picker("Size", selection: $model.minimumBytes) {
                    Text("Any size").tag(Int64(0))
                    Text("At least 1 MB").tag(Int64(1_000_000))
                    Text("At least 100 MB").tag(Int64(100_000_000))
                    Text("At least 1 GB").tag(Int64(1_000_000_000))
                }
                Picker("Modified", selection: $model.modifiedWithinDays) {
                    Text("Any time").tag(0)
                    Text("Last 7 days").tag(7)
                    Text("Last 30 days").tag(30)
                    Text("Last year").tag(365)
                }
            }
            .font(.callout)
        }
        .disabled(model.isWorking)
    }

    private func row(_ entry: OfflineCatalogEntry) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: entry.isDirectory ? "folder" : "doc")
                    .font(.title3).foregroundStyle(theme.accent).frame(width: 26).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                    Text(entry.relativePath).font(.caption).foregroundStyle(theme.textSecondary)
                        .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(entry.byteCount.map { $0.formatted(.byteCount(style: .file)) } ?? "Folder")
                    Text(entry.modifiedAt, format: .dateTime.year().month().day())
                }
                .font(.caption).foregroundStyle(theme.textSecondary)
                Button("Show in Explorer", systemImage: "arrow.up.right.square") {
                    model.reveal(entry) { [onReveal] url, isDirectory in onReveal(url, isDirectory) }
                }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
                .disabled(model.isConnected == false || model.isWorking)
                .help(model.isConnected ? "Show the original item in Explorer" : "Connect the original disk to show this item")
                .accessibilityLabel("Show \(entry.name) in Explorer")
                .accessibilityIdentifier("offline-catalog-reveal-\(entry.relativePath)")
            }
            Divider().overlay(theme.divider)
        }
        .padding(.vertical, 10).padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offline-catalog-entry-\(entry.relativePath)")
    }
}
