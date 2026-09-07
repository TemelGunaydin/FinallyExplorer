import Foundation

/// An immutable, reviewable list. A comparison never itself authorizes a write.
nonisolated struct VerifiedCopyPlan: Identifiable, Sendable {
    let id = UUID()
    let snapshot: FolderComparisonSnapshot
    let entries: [ComparedFolderEntry]
    let fileCount: Int
    let directoryCount: Int
    let byteCount: Int64

    init(snapshot: FolderComparisonSnapshot) throws {
        self.snapshot = snapshot
        entries = snapshot.missingEntries.sorted {
            let leftDepth = $0.relativePath.split(separator: "/").count
            let rightDepth = $1.relativePath.split(separator: "/").count
            if leftDepth != rightDepth { return leftDepth < rightDepth }
            return $0.relativePath < $1.relativePath
        }
        fileCount = entries.count { $0.state.isRegularFile }
        directoryCount = entries.count { $0.state.isDirectory }
        var total: Int64 = 0
        for entry in entries where entry.state.isRegularFile {
            guard entry.sha256 != nil else { throw FolderComparisonError.changed(entry.relativePath) }
            let added = total.addingReportingOverflow(entry.state.size)
            guard added.overflow == false, entry.state.size >= 0 else { throw FolderComparisonError.limitExceeded }
            total = added.partialValue
        }
        byteCount = total
    }
}
