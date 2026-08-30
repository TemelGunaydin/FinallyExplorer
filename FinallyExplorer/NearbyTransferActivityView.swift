//
//  NearbyTransferActivityView.swift
//  FinallyExplorer
//

import SwiftUI

struct NearbyTransferActivityView: View {
    @Environment(\.explorerTheme) private var theme

    let progress: NearbyTransferProgress
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: directionImage)
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(directionTitle)
                        .font(ExplorerTheme.actionFont)
                    Text(progress.peerName)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Button("Cancel", systemImage: "xmark", action: onCancel)
                    .labelStyle(.iconOnly)
                    .buttonStyle(ExplorerToolbarButtonStyle())
                    .accessibilityIdentifier("nearby-transfer-cancel-button")
            }
            ProgressView(value: progress.fractionCompleted)
                .tint(theme.accent)
            Text(progressText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(theme.textSecondary)
        }
        .padding(14)
        .frame(width: 310)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(theme.divider, lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .accessibilityIdentifier("nearby-transfer-progress")
    }

    private var directionTitle: String {
        progress.direction == .sending ? "Sending…" : "Receiving…"
    }

    private var directionImage: String {
        progress.direction == .sending ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
    }

    private var progressText: String {
        let completed = ByteCountFormatter.string(
            fromByteCount: Int64(clamping: progress.completedByteCount),
            countStyle: .file
        )
        let total = ByteCountFormatter.string(
            fromByteCount: Int64(clamping: progress.totalByteCount),
            countStyle: .file
        )
        return "\(completed) of \(total)"
    }
}
