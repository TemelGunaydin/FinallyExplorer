import Foundation

nonisolated enum FolderOrganizationError: LocalizedError, Equatable, Sendable {
    case invalidPlan
    case changed(String)
    case collision(String)
    case fileSystem(String, Int32)

    var errorDescription: String? {
        switch self {
        case .invalidPlan: "Preview this folder again before organizing it. Only the listed regular files can be moved."
        case let .changed(path): "A file or folder changed since the preview. Preview again before continuing.\n\(path)"
        case let .collision(path): "The destination is no longer available. Nothing was overwritten. Preview again.\n\(path)"
        case let .fileSystem(path, code): "Could not organize this item: \(POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO).localizedDescription)\n\(path)"
        }
    }

    static func message(for error: any Error) -> String {
        if let error = error as? FolderComparisonError {
            switch error {
            case let .changed(path): return Self.changed(path).localizedDescription
            case let .collision(path): return Self.collision(path).localizedDescription
            case let .fileSystem(path, code): return Self.fileSystem(path, code).localizedDescription
            default: return FileToolsError.message(for: error)
            }
        }
        return error.localizedDescription
    }
}
