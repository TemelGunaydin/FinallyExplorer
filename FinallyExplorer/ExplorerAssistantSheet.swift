//
//  ExplorerAssistantSheet.swift
//  FinallyExplorer
//

import SwiftUI

struct ExplorerAssistantSheet: View {
    let folderURL: URL
    let items: [FileItem]
    let model: ExplorerAssistantModel

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    folderSummary

                    if let availabilityMessage = model.availabilityMessage {
                        ContentUnavailableView(
                            "Ask Explorer Is Unavailable",
                            systemImage: "sparkles.slash",
                            description: Text(availabilityMessage)
                        )
                    } else {
                        promptEditor(question: $model.question)
                        suggestions
                        response
                    }
                }
                .padding(20)
            }
            .scrollContentBackground(.hidden)
            .background(ExplorerTheme.canvas)
        }
        .frame(minWidth: 520, minHeight: 470)
        .background(ExplorerTheme.canvas)
        .tint(ExplorerTheme.accent)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Ask Explorer", systemImage: "sparkles")
                .font(ExplorerTheme.assistantTitleFont)

            Text("Private, on-device help for the folder in front of you.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .foregroundStyle(.white)
        .background(ExplorerTheme.assistantHeader)
        .overlay(alignment: .trailing) {
            Circle()
                .fill(ExplorerTheme.easyOnTheEyes.opacity(0.30))
                .frame(width: 150, height: 150)
                .blur(radius: 42)
                .offset(x: 36, y: 20)
                .allowsHitTesting(false)
        }
        .clipped()
    }

    private var folderSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(folderURL.lastPathComponent, systemImage: "folder.fill")
                .font(.headline)
                .foregroundStyle(ExplorerTheme.textPrimary)

            Text(folderURL.path(percentEncoded: false))
                .font(.caption)
                .foregroundStyle(ExplorerTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text("Uses metadata from \(items.count) visible items; file contents stay private.")
                .font(.caption)
                .foregroundStyle(ExplorerTheme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ExplorerTheme.elevatedPanel,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ExplorerTheme.divider, lineWidth: 0.75)
        }
    }

    private func promptEditor(question: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What would you like to know?")
                .font(.headline)

            TextField(
                "For example: Which files should I review first?",
                text: question,
                axis: .vertical
            )
            .lineLimit(3...6)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                ExplorerTheme.control,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(ExplorerTheme.divider, lineWidth: 0.75)
            }
            .disabled(model.isResponding)

            HStack {
                Spacer()

                Button("Ask", systemImage: "sparkles") {
                    model.ask(about: folderURL, items: items)
                }
                .buttonStyle(.borderedProminent)
                .tint(ExplorerTheme.accent)
                .disabled(model.canAsk == false)
            }
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try a quick question")
                .font(.subheadline.bold())

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    suggestionButton("Which files use the most space?")
                    suggestionButton("What should I review first?")
                    suggestionButton("Summarize this folder")
                }

                VStack(alignment: .leading, spacing: 8) {
                    suggestionButton("Which files use the most space?")
                    suggestionButton("What should I review first?")
                    suggestionButton("Summarize this folder")
                }
            }
        }
    }

    @ViewBuilder
    private var response: some View {
        if model.isResponding {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Thinking on this Mac…")
                    .foregroundStyle(ExplorerTheme.textSecondary)
            }
            .padding(.top, 2)
        } else if let answer = model.answer {
            VStack(alignment: .leading, spacing: 8) {
                Label("Explorer’s take", systemImage: "sparkles")
                    .font(.headline)

                Text(answer)
                    .textSelection(.enabled)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ExplorerTheme.elevatedPanel,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(ExplorerTheme.divider, lineWidth: 0.75)
            }
        } else if let errorMessage = model.errorMessage {
            ContentUnavailableView(
                "Ask Explorer Couldn’t Respond",
                systemImage: "exclamationmark.triangle.fill",
                description: Text(errorMessage)
            )
        }
    }

    private func suggestionButton(_ suggestion: String) -> some View {
        Button(suggestion) {
            model.useSuggestion(suggestion, about: folderURL, items: items)
        }
        .buttonStyle(.bordered)
        .tint(ExplorerTheme.accent)
        .disabled(model.isResponding)
    }
}
