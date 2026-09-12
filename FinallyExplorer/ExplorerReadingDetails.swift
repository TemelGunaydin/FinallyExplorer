import SwiftUI

/// Keeps constraints available without crowding the main task flow.
struct ExplorerReadingDetails: View {
    @Environment(\.explorerTheme) private var theme
    let title: String
    let text: String

    var body: some View {
        DisclosureGroup(title) {
            Text(text).font(.callout).foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
        }
        .font(.callout).tint(theme.textSecondary)
    }
}
