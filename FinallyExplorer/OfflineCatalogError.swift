import Foundation

nonisolated enum OfflineCatalogError: LocalizedError, Equatable, Sendable {
    case invalidSource
    case unavailableVolume
    case ambiguousVolume
    case changedItem
    case invalidCatalog
    case tooLarge
    case catalogLimit
    case cleanupFailed

    var errorDescription: String? {
        switch self {
        case .invalidSource: "Choose a folder on a connected local external disk with a persistent volume UUID. Internal disks, network shares and app packages are not supported here."
        case .unavailableVolume: "Connect the original disk to continue. Saved metadata is still searchable while it is offline."
        case .ambiguousVolume: "More than one connected disk has this volume identifier. Disconnect the duplicate before continuing."
        case .changedItem: "This file or folder changed or is no longer at its saved location. Choose the folder again and refresh the catalog."
        case .invalidCatalog: "The saved catalog is invalid or uses an unsupported format. It has not been replaced."
        case .tooLarge: "This folder exceeds the catalog limit. Choose a smaller subfolder (up to 100,000 entries and 64 levels). The previous catalog has not been replaced."
        case .catalogLimit: "You can keep up to 32 catalogs. Remove an unused saved catalog before adding another."
        case .cleanupFailed: "The catalog was removed from the list, but its local snapshot could not be completely deleted. No files on the original disk were changed."
        }
    }

    static func message(for error: any Error) -> String {
        if let error = error as? FolderComparisonError {
            if error == .limitExceeded { return Self.tooLarge.localizedDescription }
            return "The folder could not be read consistently. Reconnect the disk, check access, and try again. The previous catalog has not been replaced.\n\(error.localizedDescription)"
        }
        return error.localizedDescription
    }
}
