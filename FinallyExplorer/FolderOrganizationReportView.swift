import SwiftUI

struct FolderOrganizationReportView: View {
    @Environment(\.explorerTheme) private var theme
    let report: FolderOrganizationReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(report.summary, systemImage: report.wasCancelled || report.errorMessage != nil
                  ? "exclamationmark.circle" : "checkmark.circle")
                .font(.headline).accessibilityIdentifier("organization-report")
            if let error = report.errorMessage {
                Text(error).font(.callout).textSelection(.enabled)
            }
            Text("Completed moves and created folders remain in place; changes are not automatically undone. Preview again before making further changes.")
                .font(.callout).foregroundStyle(theme.textSecondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if report.createdFolders.isEmpty == false {
                        Text("Created: \(report.createdFolders.joined(separator: ", "))")
                            .font(.callout).textSelection(.enabled)
                    }
                    ForEach(report.movedFiles) { move in
                        FolderOrganizationPathView(source: move.sourceName, destination: move.destinationPath)
                    }
                }
            }
        }
    }
}
