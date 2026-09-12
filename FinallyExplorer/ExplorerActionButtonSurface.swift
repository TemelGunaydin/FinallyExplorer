import SwiftUI

struct ExplorerActionButtonSurface<Content: View>: View {
    @Environment(\.explorerTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    let isPressed: Bool
    let isProminent: Bool
    var showsFocus = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .font(ExplorerTheme.actionFont)
            .foregroundStyle(isEnabled ? theme.textPrimary : theme.textSecondary)
            .symbolRenderingMode(.hierarchical)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(minHeight: 36)
            .background {
                RoundedRectangle(cornerRadius: 11)
                    .fill(theme.imperialPrimer.opacity(isEnabled ? 0.65 : 0))
                    .offset(y: 3)
                RoundedRectangle(cornerRadius: 11)
                    .fill(isEnabled && isProminent ? theme.accentSoft : theme.control)
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .fill((isProminent ? theme.accent : theme.supportAccent)
                                .opacity(isEnabled ? (isPressed ? 0.26 : isHovered ? 0.18 : 0.10) : 0))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .strokeBorder((showsFocus || isFocused) && isEnabled ? theme.accent : theme.divider,
                                          lineWidth: (showsFocus || isFocused) && isEnabled ? 2 : 1)
                    }
            }
            .contentShape(.rect(cornerRadius: 11))
            .shadow(color: .black.opacity(isEnabled ? 0.18 : 0), radius: 3, y: 3)
            .offset(y: isPressed && isEnabled && reduceMotion == false ? 2 : 0)
            .onHover { isHovered = $0 }
    }
}
