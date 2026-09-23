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
                DocumentQuestionOptionsButton(model: model)
                Button("Close Document Questions", systemImage: "xmark") { model.cancel(); dismiss() }
                    .labelStyle(.iconOnly).buttonStyle(ExplorerPaneUtilityButtonStyle(isClose: true)).keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("document-close")
            }
            DocumentQuestionSourcesView(model: model)
            if model.isEnabled == false {
                Text("Document Questions is off. Enable it in AI Settings.").font(.callout)
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.accentSoft, in: .rect(cornerRadius: 8)).accessibilityIdentifier("document-error")
            }
            if let activity = model.activity {
                HStack {
                    ProgressView().controlSize(.small).tint(theme.textPrimary)
                    Text(model.isCancelling ? "Stopping…" : activity).font(.callout)
                        .lineLimit(2).truncationMode(.middle).accessibilityIdentifier("document-read-activity")
                    Spacer()
                    Button("Cancel", action: model.cancel).disabled(model.isCancelling).accessibilityIdentifier("document-cancel")
                }
                .padding(10).background(theme.control, in: .rect(cornerRadius: 10))
            }
            DocumentAnswerView(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                TextField("Ask a question or explain this document…", text: $model.question, axis: .vertical)
                    .lineLimit(1...3).textFieldStyle(.plain).padding(12)
                    .background(theme.control, in: .rect(cornerRadius: 10))
                    .disabled(model.isWorking || model.isEnabled == false).onSubmit { model.ask() }
                    .accessibilityIdentifier("document-question")
                Button("Ask", systemImage: "arrow.up") { model.ask() }
                    .buttonStyle(ExplorerDialogButtonStyle(isProminent: true)).disabled(model.canAsk == false)
                    .accessibilityIdentifier("document-ask")
            }
        }
        .padding(22).frame(width: 820, height: 720)
        .foregroundStyle(theme.textPrimary).background(theme.panel).tint(theme.accent)
        .buttonStyle(ExplorerDialogButtonStyle())
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
