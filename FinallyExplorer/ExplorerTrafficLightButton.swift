//
//  ExplorerTrafficLightButton.swift
//  FinallyExplorer
//

import SwiftUI

struct ExplorerTrafficLightButton: View {
    @Environment(\.accessibilityDifferentiateWithoutColor)
    private var differentiateWithoutColor

    let kind: ExplorerTrafficLightKind
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(kind.color)
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.24), lineWidth: 0.8)
                    }
                    .shadow(
                        color: Color.black.opacity(0.24),
                        radius: 1.5,
                        x: 0,
                        y: 1
                    )

                Image(systemName: kind.systemImage)
                    .font(.system(size: 7.5, weight: .black))
                    .foregroundStyle(Color.black.opacity(0.7))
                    .opacity(isHovered || differentiateWithoutColor ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .frame(width: 19, height: 19)
            .frame(width: 28, height: 32)
            .contentShape(.rect)
        }
        .buttonStyle(ExplorerTrafficLightButtonStyle())
        .onHover { isHovered = $0 }
        .help(kind.title)
        .accessibilityLabel(kind.title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var accessibilityIdentifier: String {
        switch kind {
        case .close:
            "window-close-button"
        case .minimize:
            "window-minimize-button"
        case .fullscreen:
            "window-fullscreen-button"
        }
    }
}
