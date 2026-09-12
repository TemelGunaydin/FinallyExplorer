import SwiftUI

struct VisualSearchSheet: View {
    @Environment(\.explorerTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: VisualSearchModel
    let onReveal: @MainActor (URL) -> Void
    var settings: ExplorerAISettings? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Text("Find scenes and text in your photos. Analyze a folder to get started.")
                .font(.callout).foregroundStyle(theme.textSecondary)
            sourceControls
            VisualDescriptionControls(model: model)
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).textSelection(.enabled).padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.accentSoft, in: .rect(cornerRadius: 8))
                    .accessibilityIdentifier("visual-search-error")
            }
            if let progress = model.progress {
                VStack(spacing: 8) {
                    FileToolsProgressView(progress: progress, isCancelling: model.isCancelling,
                        detail: "Analyzing this folder only. Cancel keeps your last completed analysis.")
                    if progress.totalItems > 0 {
                        Text("\(progress.completedItems) of \(progress.totalItems) images processed").font(.callout)
                        ProgressView(value: Double(progress.completedItems), total: Double(progress.totalItems))
                            .frame(maxWidth: 360)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let snapshot = model.snapshot {
                results(snapshot)
            } else {
                ContentUnavailableView("Your Photos, Searchable", systemImage: "photo.badge.magnifyingglass",
                    description: Text("Choose a folder and select Analyze Folder.\nThen try “beach photos” or words from a receipt."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("visual-search-empty")
            }
            footer
        }
        .padding(22).frame(width: 820, height: 720)
        .foregroundStyle(theme.textPrimary).background(theme.panel).tint(theme.accent)
        .buttonStyle(ExplorerDialogButtonStyle())
        .accessibilityElement(children: .contain).accessibilityIdentifier("visual-search-sheet")
        .onDisappear { model.cancel() }
        .onAppear { model.setNaturalEnabled(settings?.isSmartSearchEnabled ?? true) }
        .onChange(of: settings?.isSmartSearchEnabled) { model.setNaturalEnabled(settings?.isSmartSearchEnabled ?? true) }
    }

    private var header: some View {
        HStack {
            Label("Visual Search", systemImage: "photo.badge.magnifyingglass")
                .font(.system(.title2, design: .rounded).weight(.semibold))
            Spacer()
            Text("ON DEVICE · MEMORY ONLY").font(.caption.weight(.semibold))
                .padding(6).background(theme.accentSoft, in: .rect(cornerRadius: 6))
            Button("Close Visual Search", systemImage: "xmark") { model.cancel(); dismiss() }
                .labelStyle(.iconOnly).buttonStyle(ExplorerPaneUtilityButtonStyle())
                .keyboardShortcut(.cancelAction).accessibilityIdentifier("visual-search-close")
        }
    }

    private var sourceControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Choose Folder…", systemImage: "folder", action: model.chooseFolder)
                    .accessibilityIdentifier("visual-search-choose-folder")
                Spacer()
                Toggle("Include hidden items", isOn: $model.includesHidden)
                Button(model.snapshot == nil ? "Analyze Folder" : "Analyze Again", systemImage: "sparkle.magnifyingglass") { model.analyze() }
                    .buttonStyle(ExplorerDialogButtonStyle(isProminent: true))
                    .disabled(model.sourceURL == nil).accessibilityIdentifier("visual-search-analyze")
            }.disabled(model.isWorking)
            Text(model.sourceURL?.path ?? "Choose the folder you want to analyze.")
                .font(.callout).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                .accessibilityIdentifier("visual-search-source")
            ExplorerReadingDetails(title: "Supported images & privacy", text: "Up to 300 images · 40 MB / 80 MP each · JPEG, PNG, HEIC, TIFF, BMP. English labels and text. Links, packages and cloud placeholders are skipped. Analysis stays in memory and does not require Apple Intelligence; other photo descriptions may. Visual matches can miss or misidentify subjects.")
        }
        .padding(12).background(theme.control, in: .rect(cornerRadius: 12)).disabled(model.isWorking)
    }

    private func results(_ snapshot: VisualSearchSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Search labels or text in images", text: $model.query)
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("visual-search-query")
                Picker("Match", selection: $model.mode) {
                    ForEach(VisualSearchMode.allCases) { Text($0.rawValue).tag($0) }
                }.frame(width: 215).accessibilityIdentifier("visual-search-mode")
            }.disabled(model.isWorking)
            Text("\(model.matches.count) \(model.matches.count == 1 ? "match" : "matches") · \(snapshot.entries.count) analyzed · \(snapshot.skipped.count) skipped")
                .font(.callout).foregroundStyle(theme.textPrimary)
                .accessibilityIdentifier("visual-search-summary")
            Text("\(snapshot.excludedHiddenCount) hidden / \(snapshot.excludedOtherCount) unsupported entries excluded · Visual matches can be imperfect.")
                .font(.caption).foregroundStyle(theme.textSecondary)
            if model.query.count > 200 {
                Text(VisualSearchError.queryTooLong.localizedDescription).font(.callout)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if snapshot.entries.isEmpty {
                        Text("No supported images could be analyzed in this folder.")
                    } else if model.matches.isEmpty {
                        Text(model.naturalPlan == nil
                             ? "No matches found. Try another scene or fewer words."
                             : "No photos match these filters. Try “All dates” or “All image types”.")
                    }
                    ForEach(model.matches.prefix(150)) { match in
                        VisualSearchResultRow(match: match) {
                            model.reveal(match.entry) { url in onReveal(url); dismiss() }
                        }.disabled(model.isWorking)
                    }
                    if model.matches.count > 150 { Text("Showing the first 150 matches. Narrow your search to see the rest.").font(.caption) }
                    if snapshot.skipped.isEmpty == false {
                        DisclosureGroup("Skipped images (\(snapshot.skipped.count))") {
                            ForEach(snapshot.skipped) { item in
                                Text("\(item.relativePath) — \(item.reason)").font(.caption).textSelection(.enabled)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            if model.isWorking {
                Button(model.isCancelling ? "Stopping…" : "Cancel", action: model.cancel)
                    .disabled(model.isCancelling).accessibilityIdentifier("visual-search-stop")
            }
            Text("No uploads. Kept in this Explorer window; Clear to forget.")
                .font(.caption).foregroundStyle(theme.textSecondary)
            Spacer()
            Button("Clear Analysis", systemImage: "eraser", action: model.clearIndex)
                .disabled(model.snapshot == nil && model.isWorking == false)
                .accessibilityIdentifier("visual-search-clear")
        }
    }
}
