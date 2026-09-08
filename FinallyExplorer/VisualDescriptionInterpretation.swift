import FoundationModels

@Generable
nonisolated struct VisualDescriptionInterpretation {
    @Guide(description: "Required visual concepts. Each inner group contains synonymous English classifier labels, not extra unrelated subjects.", .maximumCount(4))
    var concepts: [[String]]
    @Guide(description: "Every requested condition unsupported by visual labels: dates, places/GPS, named people, exclusion, actions, file names, image text, relations or counting. Empty only for supported scene/object concepts.", .maximumCount(6))
    var unsupported: [String]
}
