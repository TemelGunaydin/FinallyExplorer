import FoundationModels

@Generable
nonisolated struct VisualDescriptionInterpretation {
    @Guide(description: "One group per distinct requested subject, not per synonym. A dog on a beach has exactly TWO groups: dog and beach. Do not add inferred subjects such as water, sand, animal or outdoors.", .maximumCount(4))
    var concepts: [Concept]
    @Guide(description: "Every requested condition unsupported by visual labels: dates, places/GPS, named people, exclusion, actions, file names, image text, relations or counting. Empty only for supported scene/object concepts.", .maximumCount(6))
    var unsupported: [String]

    @Generable
    struct Concept {
        @Guide(description: "Interchangeable English classifier labels for ONE subject. Example dog -> [dog, dogs, canine]. Do not put these synonyms in separate concept groups.", .minimumCount(1), .maximumCount(8))
        var alternatives: [String]
    }
}
