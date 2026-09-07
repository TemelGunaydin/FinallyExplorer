nonisolated enum FolderComparisonFilter: String, CaseIterable, Identifiable {
    case differences = "Differences"
    case copyable = "Missing in Destination"
    case all = "All Items"

    var id: Self { self }
}
