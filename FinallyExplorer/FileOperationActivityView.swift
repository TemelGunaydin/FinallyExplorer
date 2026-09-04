//
//  FileOperationActivityView.swift
//  FinallyExplorer
//

import SwiftUI

struct FileOperationActivityView: View {
    @Environment(\.explorerTheme) private var theme

    let title: String
    let systemImage: String
    let completedItemCount: Int
    let totalItemCount: Int
    let onCancel: () -> Void

    private var showsItemProgress: Bool {
        totalItemCount > 1
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.accent)
                .frame(width: 38, height: 38)
                .background(theme.accentSoft, in: .rect(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(ExplorerTheme.actionFont)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if showsItemProgress {
                        Text("\(completedItemCount) of \(totalItemCount)")
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                            .monospacedDigit()
                    }
                }

                if showsItemProgress {
                    ProgressView(
                        value: Double(completedItemCount),
                        total: Double(totalItemCount)
                    )
                    .progressViewStyle(.linear)
                    .tint(theme.accent)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(theme.accent)
                        .accessibilityLabel(title)
                }
            }

            Button(
                "Cancel File Operation",
                systemImage: "xmark",
                action: onCancel
            )
            .labelStyle(.iconOnly)
            .buttonStyle(ExplorerToolbarButtonStyle())
            .help("Cancel file operation")
        }
        .padding(12)
        .frame(minWidth: 300, idealWidth: 340, maxWidth: 380)
        .background(
            theme.elevatedPanel,
            in: .rect(cornerRadius: 15)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .stroke(theme.accent.opacity(0.5), lineWidth: 1)
        }
        .shadow(
            color: theme.imperialPrimer.opacity(0.3),
            radius: 14,
            x: 0,
            y: 6
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("file-operation-activity")
    }
}
