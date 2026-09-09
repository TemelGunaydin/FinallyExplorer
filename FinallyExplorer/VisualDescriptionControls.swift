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
                    .disabled(model.snapshot == nil || model.naturalDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("visual-description-submit")
            }
            .disabled(model.isWorking || model.isNaturalEnabled == false)
            if model.isDescribing {
                HStack { ProgressView().controlSize(.small).tint(theme.textPrimary); Text("Understanding the photo description…") }.font(.callout)
            } else if model.isNaturalEnabled == false {
                Text("Photo descriptions are off. Enable Ask AI & Smart Search in Settings.").font(.caption)
            } else if model.snapshot == nil {
                Text("First choose and analyze a folder above. Then describe the photos in English — no labels to enter.").font(.caption)
            } else {
                Text("Describe a scene with a date or image type. Follow up with “Only HEIC” or “Yesterday instead”. New scene requests replace the filters. Common seaside requests work instantly; other scenes require Apple Intelligence.")
                    .font(.caption).foregroundStyle(theme.textSecondary)
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
                    Text("\(model.missingCaptureDateCount) \(model.missingCaptureDateCount == 1 ? "image has" : "images have") no usable capture date and \(model.missingCaptureDateCount == 1 ? "is" : "are") excluded. Dates use EXIF, never the file’s creation date. Missing camera time zones are interpreted in the Mac’s local time zone at analysis.")
                        .font(.caption).foregroundStyle(theme.textSecondary)
                        .accessibilityIdentifier("visual-description-date-coverage")
                }
            }
        }
    }
}
