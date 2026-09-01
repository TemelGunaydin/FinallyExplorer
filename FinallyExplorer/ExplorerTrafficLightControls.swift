//
//  ExplorerTrafficLightControls.swift
//  FinallyExplorer
//

import SwiftUI

struct ExplorerTrafficLightControls: View {
    let closeWindow: () -> Void
    let minimizeWindow: () -> Void
    let toggleFullScreen: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ExplorerTrafficLightButton(kind: .close, action: closeWindow)
            ExplorerTrafficLightButton(kind: .minimize, action: minimizeWindow)
            ExplorerTrafficLightButton(
                kind: .fullscreen,
                action: toggleFullScreen
            )
        }
        .padding(.horizontal, 4)
        .frame(width: 104, height: 36, alignment: .leading)
    }
}
