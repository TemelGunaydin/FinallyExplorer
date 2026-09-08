nonisolated struct FolderOrganizationMove: Identifiable, Sendable {
    let sourceName: String
    let destinationFolder: String
    let sourceState: ComparedFileState
    var id: String { sourceName }
    var destinationPath: String { destinationFolder + "/" + sourceName }
}
