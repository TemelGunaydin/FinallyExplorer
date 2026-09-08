import SwiftUI

struct FolderOrganizationPathView: View {
    @Environment(\.explorerTheme) private var theme
    let source: String
    let destination: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(source).font(.callout.weight(.medium))
            Label(destination, systemImage: "arrow.turn.down.right")
                .font(.callout).foregroundStyle(theme.textSecondary)
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12).background(theme.control, in: .rect(cornerRadius: 10))
    }
}
