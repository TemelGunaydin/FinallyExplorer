nonisolated enum FolderOrganizationRule: String, CaseIterable, Identifiable, Sendable {
    case fileType = "File Type"
    case modifiedMonth = "Modified Month"
    var id: Self { self }
}
