import Foundation

nonisolated struct VisualSearchSnapshot: Sendable {
    struct Entry: Identifiable, Sendable {
        var id: String { relativePath }
        let relativePath: String
        let state: ComparedFileState
        let evidence: VisualImageEvidence
    }

    struct Skipped: Identifiable, Sendable {
        var id: String { relativePath }
        let relativePath: String
        let reason: String
    }

    let id = UUID()
    let rootURL: URL
    let rootState: ComparedFileState
    let tree: [String: ComparedFolderEntry]
    let entries: [Entry]
    let skipped: [Skipped]
    let excludedHiddenCount: Int
    let excludedOtherCount: Int
    let scannedAt: Date
}
