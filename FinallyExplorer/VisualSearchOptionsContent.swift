import SwiftUI

/// Secondary search evidence and scan diagnostics are available on demand.
struct VisualSearchOptionsContent: View {
    @Environment(\.explorerTheme) private var theme
    @Bindable var model: VisualSearchModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Search Options").font(.headline)
                Toggle("Include hidden items", isOn: $model.includesHidden)
                    .toggleStyle(.checkbox)
                    .disabled(model.isWorking)
                    .help("Changing this option clears the current analysis.")
                    .accessibilityIdentifier("visual-search-hidden-items")
                if let plan = model.naturalPlan {
                    Divider()
                    Button(
                        "Reset Search Filters", systemImage: "arrow.counterclockwise", action: model.startNewPhotoSearch
                    )
                    .accessibilityIdentifier("visual-description-new-search")
                    .help("Keep the photo analysis and start a fresh search")
                    DisclosureGroup("Search Details") {
                        Text(plan.explanation).font(.callout).foregroundStyle(theme.textSecondary)
                            .textSelection(.enabled).lineLimit(3).help(plan.explanation)
                            .accessibilityIdentifier("visual-description-evidence")
                            .accessibilityValue(plan.explanation)
                        if plan.filters.captureInterval != nil {
                            Text("\(model.missingCaptureDateCount) photos have no capture date.")
                                .font(.callout).foregroundStyle(theme.textSecondary)
                                .help("Date filters use camera EXIF; missing time zones use this Mac’s time zone.")
                                .accessibilityIdentifier("visual-description-date-coverage")
                        }
                    }
                    .accessibilityIdentifier("visual-search-details")
                }
                if let snapshot = model.snapshot {
                    Divider()
                    if model.isNaturalEnabled {
                        TextField("Search labels or text in images", text: $model.query)
                            .textFieldStyle(.roundedBorder).accessibilityIdentifier("visual-search-query")
                    }
                    Picker("Match", selection: $model.mode) {
                        ForEach(VisualSearchMode.allCases) { Text($0.rawValue).tag($0) }
                    }.accessibilityIdentifier("visual-search-mode")
                    DisclosureGroup("Analysis Details") {
                        LabeledContent("Analyzed", value: "\(snapshot.entries.count)")
                        if snapshot.excludedHiddenCount > 0 {
                            LabeledContent("Hidden items excluded", value: "\(snapshot.excludedHiddenCount)")
                        }
                        if snapshot.excludedOtherCount > 0 {
                            LabeledContent("Unsupported items excluded", value: "\(snapshot.excludedOtherCount)")
                        }
                        if snapshot.skipped.isEmpty == false {
                            DisclosureGroup("Skipped images (\(snapshot.skipped.count))") {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(snapshot.skipped) { item in
                                            Text("\(item.relativePath) — \(item.reason)")
                                                .font(.callout).foregroundStyle(theme.textSecondary).textSelection(
                                                    .enabled)
                                        }
                                    }
                                }
                                .frame(maxHeight: 180)
                            }
                        }
                    }
                    Button("Clear Analysis", systemImage: "eraser", action: model.clearIndex)
                        .help("Forget image analysis without changing your photos")
                        .accessibilityIdentifier("visual-search-clear")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(2)
        }
        .frame(maxHeight: 360)
        .font(.callout)
        .padding(18).frame(width: 340)
        .foregroundStyle(theme.textPrimary).background(theme.panel).tint(theme.accent)
        .buttonStyle(ExplorerDialogButtonStyle())
        .accessibilityElement(children: .contain).accessibilityIdentifier("visual-search-options-content")
    }
}
