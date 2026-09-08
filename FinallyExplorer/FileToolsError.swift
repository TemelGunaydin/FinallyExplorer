import Foundation

nonisolated enum FileToolsError: LocalizedError, Equatable, Sendable {
    case invalidSelection
    case scanAgain(String)
    case invalidFolder
    case unsupportedMetadata(String)

    var errorDescription: String? {
        switch self {
        case .invalidSelection: "Select duplicate files and leave at least one copy in each group. Nothing was changed."
        case let .scanAgain(path): "A file or folder changed. Scan again before continuing.\n\(path)"
        case .invalidFolder: "Choose an accessible local folder, not an application/package or the entire system drive."
        case let .unsupportedMetadata(path): "Resource fork or unreadable metadata — excluded: \(path)"
        }
    }

    static func message(for error: any Error) -> String {
        if let error = error as? FolderComparisonError {
            switch error {
            case let .changed(path): return Self.scanAgain(path).localizedDescription
            case .invalidFolders, .overlappingFolders: return Self.invalidFolder.localizedDescription
            case .limitExceeded: return "Choose a smaller folder: up to 50,000 entries and 64 folder levels are supported."
            default: break
            }
        }
        return error.localizedDescription
    }
}
