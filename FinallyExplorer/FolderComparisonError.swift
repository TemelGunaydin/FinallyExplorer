import Foundation

nonisolated enum FolderComparisonError: LocalizedError, Equatable, Sendable {
    case invalidFolders
    case overlappingFolders
    case limitExceeded
    case changed(String)
    case collision(String)
    case verificationFailed(String)
    case stagingCleanupFailed(String)
    case fileSystem(String, Int32)

    var errorDescription: String? {
        switch self {
        case .invalidFolders: "Choose two accessible local folders."
        case .overlappingFolders: "Choose different folders that are not inside one another."
        case .limitExceeded: "This comparison is too large. Choose smaller folders (up to 50,000 entries per folder and 64 levels)."
        case let .changed(path): "The folder or file changed since it was compared. Compare again before copying.\n\(path)"
        case let .collision(path): "An item already exists at the destination. Nothing was replaced.\n\(path)"
        case let .verificationFailed(path): "The copied data did not pass SHA-256 verification and was not published.\n\(path)"
        case let .stagingCleanupFailed(path): "The copy stopped, but its temporary file could not be removed. No final file was added. Check the destination permissions before removing this temporary file:\n\(path)"
        case let .fileSystem(path, code): "Could not access or copy this item: \(POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO).localizedDescription)\n\(path)"
        }
    }
}
