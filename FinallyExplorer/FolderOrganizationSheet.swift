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
                Text("PREVIEW ONLY").font(.caption.weight(.semibold)).foregroundStyle(theme.textPrimary)
                    .padding(6).background(theme.accentSoft, in: .rect(cornerRadius: 6))
                Button("Close Organization", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly).buttonStyle(ExplorerPaneUtilityButtonStyle())
                    .keyboardShortcut(.cancelAction)
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
            Text("Preview subfolders for the files directly inside this folder. Existing folders and their contents stay in place. Dates use modification time in your Mac’s calendar and timezone. No files are moved and no folders are created in this version.")
                .font(.callout).foregroundStyle(theme.textSecondary)
            Divider().overlay(theme.divider)
            results.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                if model.isWorking { Button("Cancel", action: model.cancel) }
                Spacer()
                Button("Preview Changes", systemImage: "eye") { model.preview() }
                    .buttonStyle(ExplorerPanePrimaryButtonStyle(isCompact: false))
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("organization-preview")
            }
        }
        .padding(22)
        .frame(width: 760, height: 660)
        .foregroundStyle(theme.textPrimary).background(theme.panel).tint(theme.accent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("organization-sheet")
        .onDisappear { model.cancel() }
    }

    @ViewBuilder private var results: some View {
        if model.isWorking, let progress = model.progress {
            FileToolsProgressView(progress: progress)
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
                            VStack(alignment: .leading, spacing: 6) {
                                Text(row.sourcePath).font(.callout.weight(.medium))
                                Label(row.destinationPath ?? "", systemImage: "arrow.turn.down.right")
                                    .font(.callout).foregroundStyle(theme.textSecondary)
                            }
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12).background(theme.control, in: .rect(cornerRadius: 10))
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
            ContentUnavailableView("See Where Files Would Go", systemImage: "folder", description: Text("Choose a grouping rule, then preview the proposed source and destination paths. This is a read-only plan, not an automatic cleanup."))
        }
    }
}
