import SwiftUI

struct FolderComparisonSheet: View {
    @Environment(\.explorerTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: FolderComparisonModel

    var body: some View {
        VStack(spacing: 14) {
            header
            HStack(alignment: .top, spacing: 12) {
                locationPicker("Source", selection: $model.sourceID, location: model.source)
                locationPicker("Destination", selection: $model.destinationID, location: model.destination)
            }
            .disabled(model.isWorking)
            HStack {
                Toggle("Include hidden items", isOn: $model.includesHidden)
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("folder-comparison-hidden")
                Spacer()
                Button(model.snapshot == nil ? "Compare" : "Compare Again", systemImage: "arrow.left.arrow.right") {
                    model.compare()
                }
                .buttonStyle(ExplorerPanePrimaryButtonStyle(isCompact: false))
                .disabled(model.canCompare == false)
                .accessibilityIdentifier("folder-comparison-start")
            }
            Text("Compare regular file data with SHA‑256. Metadata is not compared. Packages, links, special files, mounted subfolders and cloud placeholders are not followed. Nothing changes until you approve a copy.")
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Divider().overlay(theme.divider)
            results
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .padding(22)
        .frame(width: 760, height: 660)
        .foregroundStyle(theme.textPrimary)
        .background(theme.panel)
        .tint(theme.accent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("folder-comparison-sheet")
        .interactiveDismissDisabled(model.isCopying)
        .onDisappear { model.cancel() }
        .sheet(item: $model.copyConfirmation) { plan in
            VerifiedCopyReviewSheet(plan: plan) { model.confirmCopy(plan) }
                .environment(\.explorerTheme, theme)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label("Compare Folders", systemImage: "arrow.left.arrow.right")
                .font(.system(.title2, design: .rounded).weight(.semibold))
            Spacer()
            Text("LOCAL · NO AI REQUIRED")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
            Button("Close Comparison", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .buttonStyle(ExplorerPaneUtilityButtonStyle())
                .keyboardShortcut(.cancelAction)
                .disabled(model.isCopying)
                .accessibilityIdentifier("folder-comparison-close")
        }
    }

    private func locationPicker(_ title: String, selection: Binding<UUID?>, location: FolderComparisonLocation?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(title, selection: selection) {
                Text("Choose a panel").tag(nil as UUID?)
                ForEach(model.locations) { location in
                    Text(location.title).tag(Optional(location.id))
                }
            }
            .accessibilityIdentifier("folder-comparison-\(title.lowercased())")
            Text(location?.url.path ?? "Open a second folder in another panel.")
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(location?.url.path ?? "")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(theme.control, in: .rect(cornerRadius: 12))
    }

    @ViewBuilder private var results: some View {
        if model.isWorking, let progress = model.progress {
            VStack(spacing: 16) {
                ProgressView().controlSize(.large).tint(theme.textPrimary)
                Text(model.isCancelling ? "Stopping safely…" : progress.phase).font(.headline)
                Text(progress.relativePath)
                    .font(.callout).foregroundStyle(theme.textSecondary)
                    .lineLimit(2).truncationMode(.middle)
                if let fraction = progress.fraction {
                    ProgressView(value: fraction).frame(maxWidth: 360)
                }
                Text(model.isCopying ? "Completed, verified items will stay in the destination if you cancel." : "Reading file contents. Large folders can take time; you can cancel at any point.")
                    .font(.callout).foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        } else if let report = model.report {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Label(report.summary, systemImage: report.errorMessage == nil && report.wasCancelled == false ? "checkmark.shield" : "exclamationmark.circle")
                        .font(.headline)
                        .accessibilityIdentifier("verified-copy-report")
                    if let error = report.errorMessage { Text(error).textSelection(.enabled) }
                    Text("Completed items are in the destination. Existing files were not overwritten or deleted. Compare again to see the current differences.")
                        .foregroundStyle(theme.textSecondary)
                    Text(report.destinationURL.path).font(.callout).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        } else if let error = model.errorMessage {
            ContentUnavailableView {
                Label("Comparison Stopped", systemImage: "exclamationmark.circle")
            } description: {
                Text(error).textSelection(.enabled)
            }
        } else if let snapshot = model.snapshot {
            comparisonResults(snapshot)
        } else {
            ContentUnavailableView {
                Label("Compare Two Open Folders", systemImage: "folder")
            } description: {
                Text("Open different, non-overlapping folders in two panels, choose a source and destination above, then compare. You can review differences before copying missing items.")
            }
        }
    }

    private func comparisonResults(_ snapshot: FolderComparisonSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.summary).font(.callout.weight(.medium))
            HStack {
                Picker("Show", selection: $model.filter) {
                    ForEach(FolderComparisonFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .frame(maxWidth: 330)
                Spacer()
                Text("\(snapshot.excludedHiddenCount) hidden excluded")
                    .font(.caption).foregroundStyle(theme.textSecondary)
            }
            if model.visibleRows.isEmpty {
                ContentUnavailableView {
                    Label("No Items in This View", systemImage: "checkmark.circle")
                } description: {
                    Text("Try All Items to see the complete comparison.")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.visibleRows) { row in FolderComparisonRowView(row: row) }
                    }
                }
                .accessibilityIdentifier("folder-comparison-results")
            }
        }
    }

    private var footer: some View {
        HStack {
            if model.isWorking {
                Button("Cancel", action: model.cancel)
                    .disabled(model.isCancelling)
                    .accessibilityIdentifier("folder-comparison-cancel")
            }
            Spacer()
            Button("Review Copy Missing…", systemImage: "checkmark.shield", action: model.reviewCopy)
                .buttonStyle(ExplorerPanePrimaryButtonStyle(isCompact: false))
                .disabled(model.canReviewCopy == false)
                .accessibilityIdentifier("folder-comparison-review-copy")
        }
    }
}
