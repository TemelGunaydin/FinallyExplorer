import SwiftUI

struct FolderOrganizationSheet: View {
    @Environment(\.explorerTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: FolderOrganizationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Organize Folder", systemImage: "folder.badge.gearshape")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                Spacer()
                Text("REVIEW BEFORE MOVING").font(.caption.weight(.semibold)).foregroundStyle(theme.textPrimary)
                    .padding(6).background(theme.accentSoft, in: .rect(cornerRadius: 6))
                Button("Close Organization", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly).buttonStyle(ExplorerPaneUtilityButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isApplying)
                    .accessibilityIdentifier("organization-close")
            }
            Text(model.rootURL.path)
                .font(.callout).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).background(theme.control, in: .rect(cornerRadius: 10))
            HStack {
                Picker("Group by", selection: $model.rule) {
                    ForEach(FolderOrganizationRule.allCases) { rule in Text(rule.rawValue).tag(rule) }
                }
                .frame(maxWidth: 300).disabled(model.isWorking)
                .accessibilityIdentifier("organization-rule")
                Spacer()
                Toggle("Include hidden items", isOn: $model.includesHidden).disabled(model.isWorking)
            }
            Text("Group files directly inside this folder into subfolders. Existing folders and their contents stay in place. Dates use modification time in your Mac’s calendar and timezone. Nothing changes until you review and confirm the moves.")
                .font(.callout).foregroundStyle(theme.textSecondary)
            Divider().overlay(theme.divider)
            FolderOrganizationResultsView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                if model.isWorking {
                    Button(model.isCancelling ? "Stopping…" : "Cancel", action: model.cancel)
                        .disabled(model.isCancelling)
                        .accessibilityIdentifier("organization-stop")
                }
                Spacer()
                Button("Preview Changes", systemImage: "eye") { model.preview() }
                    .disabled(model.canPreview == false)
                    .accessibilityIdentifier("organization-preview")
                Button("Review Moves…", systemImage: "checklist") { model.reviewMoves() }
                    .buttonStyle(ExplorerPanePrimaryButtonStyle(isCompact: false))
                    .disabled(model.canReview == false)
                    .accessibilityIdentifier("organization-review-button")
            }
        }
        .padding(22)
        .frame(width: 760, height: 660)
        .foregroundStyle(theme.textPrimary).background(theme.panel).tint(theme.accent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("organization-sheet")
        .interactiveDismissDisabled(model.isApplying)
        .sheet(item: $model.review) { review in
            FolderOrganizationReviewSheet(plan: review, canConfirm: model.canReview) {
                model.confirmMoves(review)
            }
            .environment(\.explorerTheme, theme)
        }
        .onDisappear { model.cancel() }
    }
}
