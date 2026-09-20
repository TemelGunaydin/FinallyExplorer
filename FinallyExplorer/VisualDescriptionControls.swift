import SwiftUI

struct VisualDescriptionControls: View {
    @Environment(\.explorerTheme) private var theme
    @Bindable var model: VisualSearchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(model.naturalPlan == nil ? "Find beach photos from last week…" : "Refine: Only HEIC · Yesterday instead…", text: $model.naturalDraft)
                    .textFieldStyle(.plain).padding(10)
                    .background(theme.control, in: .rect(cornerRadius: 8))
                    .onSubmit { model.findPhotos() }
                    .accessibilityLabel("Describe photos")
                    .accessibilityIdentifier("visual-description-input")
                Button("Find Photos", systemImage: "sparkle.magnifyingglass") { model.findPhotos() }
                    .buttonStyle(ExplorerDialogButtonStyle(isProminent: true))
                    .disabled(model.snapshot == nil || model.naturalDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help(model.snapshot == nil ? "Analyze a folder first" : "Search the analyzed photos")
                    .accessibilityIdentifier("visual-description-submit")
            }
            .disabled(model.isWorking || model.isNaturalEnabled == false)
            if model.isDescribing {
                HStack { ProgressView().controlSize(.small).tint(theme.textPrimary); Text("Understanding the photo description…") }.font(.callout)
            } else if model.isNaturalEnabled == false {
                Text("Photo descriptions are off. Enable Ask AI & Smart Search in Settings.").font(.caption)
            }
            if let request = model.naturalRequest, let plan = model.naturalPlan {
                HStack(alignment: .top) {
                    Text("\(request)\nMatching visual evidence: \(plan.explanation)")
                        .font(.callout).textSelection(.enabled).lineLimit(3)
                        .accessibilityIdentifier("visual-description-evidence")
                        .accessibilityValue("\(request)\nMatching visual evidence: \(plan.explanation)")
                    Spacer(minLength: 8)
                    Button("New Photo Search") { model.startNewPhotoSearch() }
                        .disabled(model.isWorking)
                        .accessibilityIdentifier("visual-description-new-search")
                }
                if plan.filters.summary.isEmpty == false {
                    Text(plan.filters.summary).font(.callout.weight(.medium)).textSelection(.enabled)
                        .accessibilityIdentifier("visual-description-filters")
                        .accessibilityValue(plan.filters.summary)
                }
                if plan.filters.captureInterval != nil {
                    Text("\(model.missingCaptureDateCount) excluded: no capture date. Dates use camera EXIF; missing time zones use this Mac’s time zone.")
                        .font(.caption).foregroundStyle(theme.textSecondary)
                        .accessibilityIdentifier("visual-description-date-coverage")
                }
            }
        }
    }
}
