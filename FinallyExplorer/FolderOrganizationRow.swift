nonisolated struct FolderOrganizationRow: Identifiable, Sendable {
    let sourcePath: String
    let destinationPath: String?
    let skippedReason: String?
    var id: String { sourcePath }
}
