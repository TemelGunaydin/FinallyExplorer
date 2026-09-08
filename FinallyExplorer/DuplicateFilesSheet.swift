import SwiftUI

struct DuplicateFilesSheet: View {
    @Environment(\.explorerTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: DuplicateFilesModel
    let onReveal: (URL) -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label("Find Duplicates", systemImage: "doc.on.doc")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                Spacer()
                Text("LOCAL · NO AI REQUIRED")
                    .font(.caption.weight(.semibold)).foregroundStyle(theme.textSecondary)
                Button("Close Duplicates", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(ExplorerPaneUtilityButtonStyle())
                    .disabled(model.isTrashing)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("duplicates-close")
            }
            Text(model.rootURL.path)
                .font(.callout).lineLimit(2).truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(theme.control, in: .rect(cornerRadius: 10))
            HStack {
                Toggle("Include hidden items", isOn: $model.includesHidden).disabled(model.isWorking)
                    .accessibilityIdentifier("duplicates-hidden")
                Spacer()
                Button(model.snapshot == nil ? "Scan Folder" : "Scan Again", systemImage: "magnifyingglass") { model.scan() }
                    .buttonStyle(ExplorerPanePrimaryButtonStyle(isCompact: false))
                    .disabled(model.canScan == false)
                    .accessibilityIdentifier("duplicates-scan")
            }
            Text("Exact file contents, verified with SHA‑256 and byte-for-byte comparison. Links, packages, cloud placeholders, resource forks and empty files are excluded. No files are selected or removed automatically.")
                .font(.caption).foregroundStyle(theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider().overlay(theme.divider)
            results.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                if model.isWorking {
                    Button("Cancel", action: model.cancel).disabled(model.isCancelling)
                        .accessibilityIdentifier("duplicates-cancel")
                } else {
                    Button("Clear Selection", action: model.clearSelection).disabled(model.selection.isEmpty)
                    Text("\(model.selection.count) selected").font(.callout).foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Button("Review Removal…", systemImage: "trash", action: model.reviewTrash)
                    .buttonStyle(ExplorerPanePrimaryButtonStyle(isCompact: false))
                    .disabled(model.canReview == false)
                    .accessibilityIdentifier("duplicates-review")
            }
        }
        .padding(22)
        .frame(width: 760, height: 660)
        .foregroundStyle(theme.textPrimary)
        .background(theme.panel)
        .tint(theme.accent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("duplicates-sheet")
        .interactiveDismissDisabled(model.isTrashing)
        .onDisappear { model.cancel() }
        .sheet(item: $model.review) { plan in
            DuplicateTrashReviewSheet(plan: plan) { model.confirmTrash(plan) }
                .environment(\.explorerTheme, theme)
        }
    }

    @ViewBuilder private var results: some View {
        if model.isWorking, let progress = model.progress {
            FileToolsProgressView(progress: progress, isCancelling: model.isCancelling, isTrashing: model.isTrashing)
        } else if let report = model.report {
            VStack(alignment: .leading, spacing: 16) {
                Label(report.summary, systemImage: report.errorMessage == nil && report.wasCancelled == false ? "checkmark.shield" : "exclamationmark.circle")
                    .font(.headline).accessibilityIdentifier("duplicate-trash-report")
                if let error = report.errorMessage { Text(error).textSelection(.enabled) }
                Text("Completed removals are in Trash. Scan again to see the current files.")
                    .foregroundStyle(theme.textSecondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(report.trashedPaths, id: \.self) { Text($0).font(.callout).textSelection(.enabled) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(12)
        } else if let error = model.errorMessage {
            ContentUnavailableView("Scan Stopped", systemImage: "exclamationmark.circle", description: Text(error))
        } else if let snapshot = model.snapshot {
            VStack(alignment: .leading, spacing: 10) {
                Text("Groups: \(snapshot.groups.count) · Duplicate data: \(snapshot.duplicateBytes.formatted(.byteCount(style: .file)))")
                    .font(.headline).accessibilityIdentifier("duplicates-summary")
                Text("File data size, not guaranteed disk space. \(snapshot.excludedHiddenCount) hidden items excluded.")
                    .font(.caption).foregroundStyle(theme.textSecondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if snapshot.groups.isEmpty {
                            ContentUnavailableView("No Exact Duplicates", systemImage: "checkmark.circle", description: Text("No matching copies among the files eligible for this scan."))
                        }
                        ForEach(snapshot.groups) { group in
                            DuplicateGroupView(group: group, selection: model.selection) { model.toggle($0, in: group) } onReveal: { file in
                                onReveal(snapshot.rootURL.appending(path: file.relativePath))
                                dismiss()
                            }
                        }
                        if snapshot.skipped.isEmpty == false {
                            DisclosureGroup("Skipped items (\(snapshot.skipped.count))") {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(snapshot.skipped, id: \.relativePath) { entry in
                                        Text("\(entry.relativePath) — \(entry.skippedReason ?? "Excluded")")
                                            .font(.caption).foregroundStyle(theme.textSecondary)
                                    }
                                }.padding(.top, 8)
                            }
                        }
                    }
                }
            }
        } else {
            ContentUnavailableView("Find Matching File Contents", systemImage: "doc.on.doc", description: Text("Scan this folder and its subfolders, then choose which copies to keep. Nothing changes until you review and approve a removal."))
        }
    }
}
