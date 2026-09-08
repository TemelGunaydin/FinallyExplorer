import SwiftUI

struct VisualDescriptionControls: View {
    @Environment(\.explorerTheme) private var theme
    @Bindable var model: VisualSearchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Find photos taken by the sea…", text: $model.naturalDraft)
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
                Text("Describe visible scenes or objects. Common seaside requests work instantly; other descriptions require Apple Intelligence. Dates and named places are not filters in this view.")
                    .font(.caption).foregroundStyle(theme.textSecondary)
            }
            if let request = model.naturalRequest, let plan = model.naturalPlan {
                Text("\(request)\nMatching visual evidence: \(plan.explanation)")
                    .font(.callout).textSelection(.enabled).lineLimit(4)
                    .accessibilityIdentifier("visual-description-evidence")
            }
        }
    }
}
