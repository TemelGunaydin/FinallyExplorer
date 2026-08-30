//
//  ExplorerSearchViews.swift
//  FinallyExplorer
//

import SwiftUI

struct ExplorerSearchControlBar: View {
    @Binding var scope: ExplorerSearchScope
    @Binding var contentMode: FFFContentSearchMode

    let isSearching: Bool
    let resultCount: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            wideControls
            compactControls
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            ExplorerTheme.elevatedPanel,
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(ExplorerTheme.divider, lineWidth: 0.75)
        }
    }

    private var wideControls: some View {
        HStack(spacing: 12) {
            Picker("Search In", selection: $scope) {
                ForEach(ExplorerSearchScope.allCases) { scope in
                    Text(scope.title)
                        .tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 190)

            if scope == .contents {
                Picker("Match Type", selection: $contentMode) {
                    ForEach(FFFContentSearchMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }

            Spacer()

            searchStatus
        }
    }

    private var compactControls: some View {
        HStack(spacing: 8) {
            Picker("Search In", selection: $scope) {
                ForEach(ExplorerSearchScope.allCases) { scope in
                    Text(scope.title)
                        .tag(scope)
                }
            }
            .pickerStyle(.menu)

            if scope == .contents {
                Picker("Match Type", selection: $contentMode) {
                    ForEach(FFFContentSearchMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }

            Spacer(minLength: 4)
            searchStatus
        }
    }

    @ViewBuilder
    private var searchStatus: some View {
        if isSearching {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Searching")
        } else {
            Text("\(resultCount) results")
                .font(.caption)
                .foregroundStyle(ExplorerTheme.textSecondary)
        }
    }
}

struct ExplorerSearchResultsView: View {
    let paneID: UUID
    let sidebar: SidebarModel
    let query: String
    let results: [ExplorerSearchResult]
    let isSearching: Bool
    let errorMessage: ExplorerSearchMessage?

    @Binding var selection: ExplorerSearchResult.ID?

    let onSelect: (ExplorerSearchResult) -> Void
    let onOpen: (ExplorerSearchResult) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage {
                ExplorerSearchMessageBanner(message: errorMessage)
            }

            if isSearching, results.isEmpty {
                ProgressView("Preparing search index…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, errorMessage.isError, results.isEmpty {
                ContentUnavailableView(
                    "Unable to Search",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(errorMessage.text)
                )
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(results, selection: $selection) { result in
                    ExplorerSearchRowView(
                        paneID: paneID,
                        sidebar: sidebar,
                        result: result,
                        onSelect: { onSelect(result) },
                        onOpen: { onOpen(result) }
                    )
                    .tag(result.id)
                    .listRowBackground(
                        selection == result.id
                            ? ExplorerTheme.selectedRow
                            : ExplorerTheme.row
                    )
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(ExplorerTheme.panel)
                .listRowSeparatorTint(ExplorerTheme.divider)
            }
        }
        .background(ExplorerTheme.panel)
    }
}

private struct ExplorerSearchMessageBanner: View {
    let message: ExplorerSearchMessage

    var body: some View {
        Label(message.text, systemImage: message.isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
            .font(.caption)
            .foregroundStyle(
                message.isError ? Color.red : ExplorerTheme.supportAccent
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                message.isError
                    ? Color.red.opacity(0.10)
                    : ExplorerTheme.supportAccent.opacity(0.10)
            )
    }
}

private struct ExplorerSearchRowView: View {
    let paneID: UUID
    let sidebar: SidebarModel
    let result: ExplorerSearchResult
    let onSelect: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            FileItemIconView(item: result.item)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(result.item.name)
                        .font(.body)
                        .foregroundStyle(ExplorerTheme.textPrimary)

                    if result.contentMatch?.isDefinition == true {
                        Text("Definition")
                            .font(.caption)
                            .foregroundStyle(ExplorerTheme.textPrimary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(ExplorerTheme.accentSoft, in: .capsule)
                    }
                }

                Text(result.relativePath)
                    .font(.caption)
                    .foregroundStyle(ExplorerTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let match = result.contentMatch {
                    Text("Line \(match.lineNumber), column \(match.column + 1)")
                        .font(.caption)
                        .foregroundStyle(ExplorerTheme.textTertiary)

                    HighlightedSearchLine(
                        text: match.lineContent,
                        matchByteRanges: match.matchByteRanges
                    )
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 12)

            FileSizeLabel(item: result.item)
                .frame(minWidth: 72, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 1)
                .onEnded { onSelect() }
        )
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { onOpen() }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(result.item.name)
        .accessibilityHint(
            result.item.isDirectory
                ? "Double-click to open folder"
                : "Double-click to open file"
        )
        .accessibilityAction(named: "Open", onOpen)
        .internalFileInteraction(
            for: result.item,
            paneID: paneID,
            sidebar: sidebar
        )
        .accessibilityIdentifier("file-row-\(paneID)-\(result.item.name)")
    }

}

private struct HighlightedSearchLine: View {
    let text: String
    let matchByteRanges: [Range<Int>]

    var body: some View {
        highlightedText
    }

    private var highlightedText: Text {
        let ranges = matchByteRanges
            .compactMap(stringRange)
            .sorted { $0.lowerBound < $1.lowerBound }
        var output = AttributedString()
        var cursor = text.startIndex

        for range in ranges where range.lowerBound >= cursor {
            if cursor < range.lowerBound {
                output.append(AttributedString(String(text[cursor..<range.lowerBound])))
            }

            var matchedText = AttributedString(String(text[range]))
            matchedText.font = .system(.caption, design: .monospaced).bold()
            matchedText.foregroundColor = ExplorerTheme.accent
            output.append(matchedText)
            cursor = range.upperBound
        }

        if cursor < text.endIndex {
            output.append(AttributedString(String(text[cursor...])))
        }

        return Text(output)
    }

    private func stringRange(_ byteRange: Range<Int>) -> Range<String.Index>? {
        guard byteRange.lowerBound >= 0,
              byteRange.upperBound >= byteRange.lowerBound else {
            return nil
        }

        let utf8 = text.utf8
        guard let lowerUTF8 = utf8.index(
            utf8.startIndex,
            offsetBy: byteRange.lowerBound,
            limitedBy: utf8.endIndex
        ),
            let upperUTF8 = utf8.index(
                utf8.startIndex,
                offsetBy: byteRange.upperBound,
                limitedBy: utf8.endIndex
            ),
            let lower = String.Index(lowerUTF8, within: text),
            let upper = String.Index(upperUTF8, within: text) else {
            return nil
        }

        return lower..<upper
    }
}
