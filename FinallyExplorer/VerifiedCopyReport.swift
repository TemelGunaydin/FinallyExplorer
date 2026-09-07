import Foundation

nonisolated struct VerifiedCopyReport: Sendable {
    let destinationURL: URL
    var verifiedFiles: [String] = []
    var createdDirectories: [String] = []
    var wasCancelled = false
    var errorMessage: String?

    var changedDirectories: Set<URL> {
        Set((verifiedFiles + createdDirectories).map {
            destinationURL.appending(path: $0).deletingLastPathComponent()
        })
    }

    var summary: String {
        let outcome = wasCancelled ? "Copy cancelled" : errorMessage == nil ? "Copy complete" : "Copy stopped"
        return "\(outcome) · Verified files: \(verifiedFiles.count) · Folders added: \(createdDirectories.count)"
    }
}
