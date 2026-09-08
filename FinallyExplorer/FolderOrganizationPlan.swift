import Foundation

/// A read-only snapshot. A separate, reviewed move plan is required to authorize changes.
nonisolated struct FolderOrganizationPlan: Identifiable, Sendable {
    let id = UUID()
    let rootURL: URL
    let rootState: ComparedFileState
    let entries: [String: ComparedFolderEntry]
    let destinationFolders: [String: ComparedFileState]
    let rule: FolderOrganizationRule
    let proposed: [FolderOrganizationRow]
    let skipped: [FolderOrganizationRow]
    let excludedHiddenCount: Int
}
