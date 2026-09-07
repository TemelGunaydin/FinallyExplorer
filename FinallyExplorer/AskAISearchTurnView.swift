import SwiftUI

struct AskAISearchTurnView: View {
    @Environment(\.explorerTheme) private var theme
    let turn: AskAISearchTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(turn.request)
                .font(.body.weight(.semibold))
            Label(turn.response, systemImage: turn.isError ? "exclamationmark.circle" : "line.3.horizontal.decrease")
                .font(.callout)
                .foregroundStyle(theme.textSecondary)
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(theme.accentSoft.opacity(0.4), in: .rect(cornerRadius: 12))
    }
}
