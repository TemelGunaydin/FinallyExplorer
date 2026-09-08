import SwiftUI

struct FolderOrganizationResultsView: View {
    @Environment(\.explorerTheme) private var theme
    let model: FolderOrganizationModel

    var body: some View {
        if model.isWorking, let progress = model.progress {
            FileToolsProgressView(progress: progress, isCancelling: model.isCancelling,
                detail: model.isApplying
                    ? "If you cancel, completed moves and created folders stay in place. Remaining files are left alone."
                    : nil)
        } else if let report = model.report {
            FolderOrganizationReportView(report: report)
        } else if let error = model.errorMessage {
            ContentUnavailableView("Preview Stopped", systemImage: "exclamationmark.circle", description: Text(error))
        } else if let plan = model.plan {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(plan.proposed.count) proposed · \(plan.skipped.count) skipped · \(plan.excludedHiddenCount) hidden excluded")
                    .font(.headline).accessibilityIdentifier("organization-summary")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if plan.proposed.isEmpty {
                            ContentUnavailableView("No Changes Proposed", systemImage: "folder", description: Text("There are no eligible files to organize with this rule."))
                        }
                        ForEach(plan.proposed) { row in
                            FolderOrganizationPathView(source: row.sourcePath, destination: row.destinationPath ?? "")
                        }
                        if plan.skipped.isEmpty == false {
                            DisclosureGroup("Skipped items") {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(plan.skipped) { row in
                                        Text("\(row.sourcePath) — \(row.skippedReason ?? "Excluded")")
                                            .font(.caption).foregroundStyle(theme.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } else {
            ContentUnavailableView("See Where Files Would Go", systemImage: "folder", description: Text("Choose a grouping rule, then preview the proposed paths. Review Moves lets you check them once more before making changes."))
        }
    }
}
