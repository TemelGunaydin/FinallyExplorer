import SwiftUI

struct FileToolsProgressView: View {
    @Environment(\.explorerTheme) private var theme
    let progress: FolderWorkProgress
    var isCancelling = false
    var isTrashing = false

    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large).tint(theme.textPrimary)
            Text(isCancelling ? "Stopping safely…" : progress.phase).font(.headline)
            Text(progress.relativePath)
                .font(.callout).foregroundStyle(theme.textSecondary)
                .lineLimit(2).truncationMode(.middle)
            if let fraction = progress.fraction {
                ProgressView(value: fraction).frame(maxWidth: 360)
            }
            Text(isTrashing
                 ? "If you cancel, files already moved to Trash stay there. Remaining files are left alone."
                 : "Only this folder is being scanned. Large folders can take time; you can cancel at any point.")
                .font(.callout).foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
}
