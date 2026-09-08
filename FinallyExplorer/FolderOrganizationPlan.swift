import Foundation

nonisolated enum FolderOrganizationRule: String, CaseIterable, Identifiable, Sendable {
    case fileType = "File Type"
    case modifiedMonth = "Modified Month"
    var id: Self { self }
}

nonisolated struct FolderOrganizationRow: Identifiable, Sendable {
    let sourcePath: String
    let destinationPath: String?
    let skippedReason: String?
    var id: String { sourcePath }
}

/// A read-only proposal. There is deliberately no execution method in this delivery.
nonisolated struct FolderOrganizationPlan: Sendable {
    let rootURL: URL
    let rule: FolderOrganizationRule
    let proposed: [FolderOrganizationRow]
    let skipped: [FolderOrganizationRow]
    let excludedHiddenCount: Int
}
