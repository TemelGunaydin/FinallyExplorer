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
            VisualSearchSourceControls(model: model)
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
                        detail: "Cancel keeps your previous analysis.")
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
                ContentUnavailableView("No Photos Analyzed", systemImage: "photo.badge.magnifyingglass")
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
            VisualSearchOptionsButton(model: model)
            Button("Close Visual Search", systemImage: "xmark") { model.cancel(); dismiss() }
                .labelStyle(.iconOnly).buttonStyle(ExplorerPaneUtilityButtonStyle())
                .keyboardShortcut(.cancelAction).accessibilityIdentifier("visual-search-close")
        }
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
            if model.matches.isEmpty == false {
                Text("\(model.matches.count) \(model.matches.count == 1 ? "photo" : "photos")")
                    .font(.callout).foregroundStyle(theme.textSecondary)
                    .accessibilityIdentifier("visual-search-summary")
            }
            if model.query.count > 200 {
                Text(VisualSearchError.queryTooLong.localizedDescription).font(.callout)
            }
            if model.matches.isEmpty {
                if model.errorMessage == nil, model.query.count <= 200 {
                    ContentUnavailableView(snapshot.entries.isEmpty ? "No Photos to Search" : "No Photos Found",
                                           systemImage: "photo.badge.magnifyingglass")
                        .accessibilityIdentifier("visual-search-no-results")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Spacer(minLength: 0)
                }
            } else {
                resultList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(model.matches.prefix(150)) { match in
                    VisualSearchResultRow(match: match) {
                        model.reveal(match.entry) { url in onReveal(url); dismiss() }
                    }.disabled(model.isWorking)
                }
                if model.matches.count > 150 { Text("Showing the first 150 matches. Narrow your search to see the rest.").font(.caption) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack {
            if model.isWorking {
                Button(model.isCancelling ? "Stopping…" : "Cancel", action: model.cancel)
                    .disabled(model.isCancelling).accessibilityIdentifier("visual-search-stop")
            }
            Spacer()
            if model.snapshot != nil || model.isWorking {
                Button("Clear Analysis", systemImage: "eraser", action: model.clearIndex)
                    .help("Forget this window’s image analysis. Your photos stay unchanged.")
                    .accessibilityIdentifier("visual-search-clear")
            }
        }
    }
}
