import SwiftUI

struct DocumentQuestionSheet: View {
    @Environment(\.explorerTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: DocumentQuestionModel
    var settings: ExplorerAISettings? = nil
    let onReveal: @MainActor (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Ask Documents", systemImage: "text.bubble").font(.system(.title2, design: .rounded).weight(.semibold))
                    .accessibilityIdentifier("document-question-sheet")
                Spacer()
                Text("ON DEVICE · MEMORY ONLY").font(.caption.weight(.semibold))
                Button("Close Document Questions", systemImage: "xmark") { model.cancel(); dismiss() }
                    .labelStyle(.iconOnly).buttonStyle(ExplorerPaneUtilityButtonStyle()).keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("document-close")
            }
            Text("Apple Intelligence answers using short passages from documents you explicitly select. No upload or API. Each question is independent; mention the subject rather than saying “it”.")
                .font(.callout).foregroundStyle(theme.textSecondary)
            DocumentQuestionSourcesView(model: model)
            if model.isEnabled == false {
                Text("Document Questions is off. Enable it in AI Settings.").font(.callout)
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout).textSelection(.enabled)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.accentSoft, in: .rect(cornerRadius: 8)).accessibilityIdentifier("document-error")
            }
            if let activity = model.activity {
                HStack {
                    ProgressView().controlSize(.small).tint(theme.textPrimary)
                    Text(model.isCancelling ? "Stopping…" : activity).font(.callout)
                    Spacer()
                    Button("Cancel", action: model.cancel).disabled(model.isCancelling).accessibilityIdentifier("document-cancel")
                }
            }
            DocumentAnswerView(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                TextField("What is the payment deadline?", text: $model.question, axis: .vertical)
                    .lineLimit(1...3).textFieldStyle(.plain).padding(12)
                    .background(theme.control, in: .rect(cornerRadius: 10))
                    .disabled(model.isWorking || model.isEnabled == false).onSubmit { model.ask() }
                    .accessibilityIdentifier("document-question")
                Button("Ask", systemImage: "arrow.up") { model.ask() }
                    .buttonStyle(ExplorerPanePrimaryButtonStyle(isCompact: false)).disabled(model.canAsk == false)
                    .accessibilityIdentifier("document-ask")
            }
            HStack {
                Text("Text and answers stay in window memory. Clear or close the window to forget them.")
                    .font(.caption).foregroundStyle(theme.textSecondary)
                Spacer()
                Button("Clear", systemImage: "eraser", action: model.clear).accessibilityIdentifier("document-clear")
            }
        }
        .padding(22).frame(width: 820, height: 720)
        .foregroundStyle(theme.textPrimary).background(theme.panel).tint(theme.accent)
        .onAppear { model.setEnabled(settings?.isDocumentQuestionsEnabled ?? true) }
        .onChange(of: settings?.isDocumentQuestionsEnabled) { model.setEnabled(settings?.isDocumentQuestionsEnabled ?? true) }
        .onDisappear { model.cancel() }
        .sheet(item: $model.inspectedClaim) { claim in
            DocumentCitationSheet(claim: claim) {
                model.reveal(claim) { url in onReveal(url); dismiss() }
            }.environment(\.explorerTheme, theme)
        }
    }
}
