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
        }
        .buttonStyle(.plain)
        .explorerContextMenuRow(isDestructive: isDestructive)
        .disabled(isEnabled == false)
    }
}
