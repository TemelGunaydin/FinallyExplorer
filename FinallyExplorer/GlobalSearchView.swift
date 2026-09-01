//
//  GlobalSearchView.swift
//  FinallyExplorer
//

import SwiftUI

struct GlobalSearchToolbar: View {
    @Environment(\.explorerTheme) private var theme

    let model: GlobalSearchModel
    let rootURL: URL
    let onReveal: (ExplorerSearchResult) -> Void

    @State private var isResultsPresented = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        @Bindable var model = model
        let isIndexReady = model.isIndexReady(in: rootURL)
        let isIndexing = model.isIndexing(in: rootURL)
        let indexFailureMessage = model.indexFailureMessage(in: rootURL)

        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    isIndexReady ? theme.chromeText : theme.chromeText.opacity(0.78)
                )

            ZStack(alignment: .leading) {
                TextField("", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .disabled(isIndexReady == false)
                    .foregroundStyle(isIndexReady ? theme.chromeText : Color.clear)
                    .accessibilityLabel("Search this Mac")
                    .accessibilityValue(searchFieldAccessibilityValue)
                    .accessibilityHint(searchFieldAccessibilityHint)
                    .accessibilityIdentifier("global-search-text-field")
                    .onSubmit(activateSelection)
                    .onKeyPress(.upArrow) {
                        model.moveSelection(.previous)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        model.moveSelection(.next)
                        return .handled
                    }

                if isIndexing {
                    Text("Indexing this Mac…")
                        .foregroundStyle(theme.chromeText.opacity(0.84))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                } else if indexFailureMessage != nil {
                    Text("Search unavailable")
                        .foregroundStyle(theme.chromeText.opacity(0.84))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                } else if model.query.isEmpty {
                    Text("Search this Mac")
                        .foregroundStyle(theme.chromeText.opacity(0.58))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isIndexing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(.white)
                    .environment(\.colorScheme, .dark)
                    .accessibilityHidden(true)
            } else if indexFailureMessage != nil {
                Button(
                    "Retry Search Indexing",
                    systemImage: "arrow.clockwise",
                    action: retryIndexing
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .help(
                    "Retry search preparation. \(indexFailureMessage ?? "Unknown error.")"
                )
                .accessibilityIdentifier("global-search-index-retry")
            } else if model.isSearching || model.isPreparingResults {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(.white)
                    .environment(\.colorScheme, .dark)
                    .accessibilityLabel("Searching this Mac")
            }

            if model.hasQuery {
                Button("Clear Search", systemImage: "xmark.circle.fill") {
                    model.clear()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
            }
        }
        .font(.system(.callout, design: .rounded))
        .foregroundStyle(theme.chromeText)
        .padding(.horizontal, 12)
        .frame(width: 460, height: 34)
        .background(
            Color.black.opacity(
                isIndexReady ? (isSearchFocused ? 0.28 : 0.17) : 0.12
            ),
            in: .rect(cornerRadius: 10)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isIndexReady && isSearchFocused
                        ? theme.accent.opacity(0.72)
                        : Color.white.opacity(isIndexReady ? 0.14 : 0.08),
                    lineWidth: isIndexReady && isSearchFocused ? 1.25 : 0.75
                )
        }
        .popover(isPresented: $isResultsPresented, arrowEdge: .bottom) {
            GlobalSearchResultsPopover(
                model: model,
                onReveal: reveal
            )
        }
        .task(id: rootURL) {
            await model.runIndexLifecycle(in: rootURL)
        }
        .task(id: model.request(in: rootURL)) {
            await model.search(in: rootURL)
        }
        .onChange(of: model.hasQuery) { _, hasQuery in
            isResultsPresented = hasQuery && model.isIndexReady(in: rootURL)
        }
        .onChange(of: isIndexReady) { _, isReady in
            if isReady {
                isResultsPresented = model.hasQuery
            } else {
                isSearchFocused = false
                isResultsPresented = false
            }
        }
    }

    private func activateSelection() {
        guard let result = model.selectedResult else { return }
        reveal(result)
    }

    private var searchFieldAccessibilityValue: String {
        if model.isIndexing(in: rootURL) {
            "Indexing"
        } else if model.indexFailureMessage(in: rootURL) != nil {
            "Unavailable"
        } else {
            model.query
        }
    }

    private var searchFieldAccessibilityHint: String {
        if model.isIndexing(in: rootURL) {
            "Search will be available when indexing finishes."
        } else if let message = model.indexFailureMessage(in: rootURL) {
            "Search preparation failed: \(message) Use the retry button to try again."
        } else {
            "Searches file names and contents on this Mac."
        }
    }

    private func retryIndexing() {
        Task {
            await model.prepare(in: rootURL)
        }
    }

    private func reveal(_ result: ExplorerSearchResult) {
        isResultsPresented = false
        isSearchFocused = false
        onReveal(result)
        model.clear()
    }
}

private struct GlobalSearchResultsPopover: View {
    @Environment(\.explorerTheme) private var theme

    let model: GlobalSearchModel
    let onReveal: (ExplorerSearchResult) -> Void

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            GlobalSearchScopeBar(
                scope: $model.scope,
                contentMode: $model.contentMode,
                resultCount: model.results.count
            )

            Divider()
                .overlay(theme.divider)

            if let message = model.message,
               message.isError == false || model.results.isEmpty == false {
                GlobalSearchMessageBanner(message: message)
            }

            resultsBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 680, height: 470)
        .background(theme.panel)
    }

    @ViewBuilder
    private var resultsBody: some View {
        if (model.isSearching || model.isPreparingResults), model.results.isEmpty {
            ProgressView("Searching this Mac…")
        } else if let message = model.message,
                  message.isError,
                  model.results.isEmpty {
            ContentUnavailableView(
                "Unable to Search This Mac",
                systemImage: "exclamationmark.triangle.fill",
                description: Text(message.text)
            )
        } else if model.results.isEmpty {
            ContentUnavailableView.search(text: model.query)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.results) { result in
                            GlobalSearchResultRow(
                                query: model.query,
                                result: result,
                                isSelected: model.selectedResultID == result.id,
                                onSelect: { model.select(result) },
                                onReveal: { onReveal(result) }
                            )
                            .id(result.id)
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.visible)
                .onChange(of: model.selectedResultID) { oldResultID, resultID in
                    guard let resultID else { return }
                    if oldResultID == nil,
                       resultID == model.results.first?.id {
                        return
                    }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(resultID, anchor: .center)
                    }
                }
            }
        }
    }
}

private struct GlobalSearchScopeBar: View {
    @Environment(\.explorerTheme) private var theme

    @Binding var scope: ExplorerSearchScope
    @Binding var contentMode: FFFContentSearchMode

    let resultCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Picker("Search In", selection: $scope) {
                ForEach(ExplorerSearchScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            .accessibilityIdentifier("global-search-scope-picker")

            if scope == .contents {
                Picker("Content Match", selection: $contentMode) {
                    ForEach(FFFContentSearchMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 230)
                .accessibilityIdentifier("global-search-content-mode-picker")
            }

            Spacer(minLength: 8)

            Text("\(resultCount) results")
                .font(.callout)
                .foregroundStyle(theme.textSecondary)
                .monospacedDigit()
        }
        .padding(12)
        .background(theme.elevatedPanel)
    }
}

private struct GlobalSearchMessageBanner: View {
    @Environment(\.explorerTheme) private var theme

    let message: ExplorerSearchMessage

    var body: some View {
        Label(
            message.text,
            systemImage: message.isError
                ? "exclamationmark.triangle.fill"
                : "info.circle.fill"
        )
        .font(.callout)
        .foregroundStyle(message.isError ? Color.red : theme.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            message.isError
                ? Color.red.opacity(0.10)
                : theme.supportAccent.opacity(0.10)
        )
    }
}

private struct GlobalSearchResultRow: View {
    @Environment(\.explorerTheme) private var theme

    let query: String
    let result: ExplorerSearchResult
    let isSelected: Bool
    let onSelect: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            FileItemIconView(item: result.item)

            VStack(alignment: .leading, spacing: 3) {
                HighlightedSearchName(text: result.item.name, query: query)

                Text(result.item.url.deletingLastPathComponent().path())
                    .font(.callout)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let match = result.contentMatch {
                    Text("Line \(match.lineNumber), column \(match.column + 1)")
                        .font(.caption)
                        .foregroundStyle(theme.textTertiary)

                    HighlightedSearchLine(
                        text: match.lineContent,
                        matchByteRanges: match.matchByteRanges
                    )
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "return")
                    .foregroundStyle(theme.accent)
                    .help("Press Return to reveal this item")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            isSelected ? theme.selectedRow : Color.clear,
            in: .rect(cornerRadius: 10)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(theme.accent.opacity(0.30), lineWidth: 0.75)
            }
        }
        .onTapGesture(count: 2, perform: onReveal)
        .onTapGesture(count: 1, perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(result.item.name)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier("global-search-result-\(result.id)")
    }
}
