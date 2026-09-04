//
//  OpenWithApplicationContextButton.swift
//  FinallyExplorer
//

import SwiftUI

struct OpenWithApplicationContextButton: View {
    let application: FileOpenApplication
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(
                    nsImage: ApplicationIconProvider.shared.icon(
                        for: application.applicationURL
                    )
                )
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)

                Text(application.name)
                    .lineLimit(1)

                Spacer(minLength: 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .explorerContextMenuRow()
        .disabled(isEnabled == false)
        .accessibilityLabel(application.name)
    }
}
