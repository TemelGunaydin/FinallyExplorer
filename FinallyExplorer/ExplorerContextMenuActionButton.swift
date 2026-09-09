//
//  ExplorerContextMenuActionButton.swift
//  FinallyExplorer
//

import SwiftUI

struct ExplorerContextMenuActionButton: View {
    let title: String
    let systemImage: String
    var shortcut: String? = nil
    var isEnabled = true
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .frame(width: 18)

                Text(title)
                    .lineLimit(1)

                Spacer(minLength: 12)

                if let shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // Keep the row's frame and hit shape inside the Button label. A
            // frame outside a plain Button looks wider without enlarging it.
            .explorerContextMenuRow(isDestructive: isDestructive)
        }
        .buttonStyle(.plain)
        .disabled(isEnabled == false)
        .accessibilityLabel(title)
    }
}
