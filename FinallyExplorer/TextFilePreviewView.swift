import AppKit
import SwiftUI

struct TextFilePreviewView: View {
    @Environment(\.explorerTheme) private var theme

    let item: FileItem

    @State private var preview: TextFilePreview?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if let preview {
                if preview.text.isEmpty {
                    ContentUnavailableView("File Is Empty", systemImage: "doc.plaintext")
                } else {
                    ReadOnlyTextPreview(text: preview.text, textColor: theme.textPrimary)
                        .accessibilityLabel("Text preview of \(item.name)")
                }
                if preview.isTruncated {
                    Text("Showing the first 256 KB. Open the file to view all contents.")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .padding(12)
                }
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Preview Unavailable", systemImage: "doc.questionmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Open File") { NSWorkspace.shared.open(item.url) }
                }
            } else {
                ProgressView("Loading preview…")
                    .tint(theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.inspector)
        .task(id: item) {
            preview = nil
            errorMessage = nil
            do {
                let result = try await TextFilePreviewService().load(item.url)
                try Task.checkCancellation()
                preview = result
            } catch is CancellationError {
                return
            } catch {
                guard Task.isCancelled == false else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
