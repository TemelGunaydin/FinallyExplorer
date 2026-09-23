import SwiftUI

struct DocumentAnswerView: View {
    @Environment(\.explorerTheme) private var theme
    @Bindable var model: DocumentQuestionModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let turn = model.history.last {
                    DocumentAnswerTurnView(turn: turn) { model.inspectedClaim = $0 }
                } else if model.errorMessage == nil && model.isWorking == false {
                    ContentUnavailableView(model.documents.isEmpty ? "Choose Documents to Get Started" : "What Would You Like to Know?", systemImage: "text.bubble")
                        .frame(maxWidth: .infinity)
                }
                if model.history.count > 1 {
                    DisclosureGroup("Previous answers (\(model.history.count - 1))") {
                        ForEach(model.history.dropLast()) { turn in
                            DocumentAnswerTurnView(turn: turn) { model.inspectedClaim = $0 }
                                .padding(.vertical, 8)
                        }
                    }.accessibilityIdentifier("document-previous-answers")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
