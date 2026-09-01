//
//  ExplorerTrafficLightButtonStyle.swift
//  FinallyExplorer
//

import SwiftUI

struct ExplorerTrafficLightButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.1),
                value: configuration.isPressed
            )
    }
}
