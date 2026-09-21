import SwiftUI

/// Secondary search evidence and scan diagnostics are available on demand.
struct VisualSearchOptionsContent: View {
    @Environment(\.explorerTheme) private var theme
    @Bindable var model: VisualSearchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search Options").font(.headline)
            Toggle("Include hidden items", isOn: $model.includesHidden)
                .toggleStyle(.checkbox)
                .disabled(model.isWorking)
                .help("Changing this option clears the current analysis.")
                .accessibilityIdentifier("visual-search-hidden-items")
            if let plan = model.naturalPlan {
                Divider()
                Text("Search Details").font(.headline)
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
            if let snapshot = model.snapshot {
                Divider()
                Text("Analysis Details").font(.headline)
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
                                        .font(.callout).foregroundStyle(theme.textSecondary).textSelection(.enabled)
                                }
                            }
                        }
                        .frame(maxHeight: 180)
                    }
                }
            }
        }
        .font(.callout)
        .padding(18).frame(width: 340)
        .foregroundStyle(theme.textPrimary).background(theme.panel).tint(theme.accent)
        .accessibilityElement(children: .contain).accessibilityIdentifier("visual-search-options-content")
    }
}
