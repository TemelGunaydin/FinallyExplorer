import Foundation

nonisolated enum VisualSearchError: LocalizedError, Sendable {
    case invalidFolder, tooManyImages, imageTooLarge, unreadableImage, changed, unavailable, queryTooLong

    var errorDescription: String? {
        switch self {
        case .invalidFolder: "Choose a local folder, not the entire Mac, a network folder, or an app or library package."
        case .tooManyImages: "This folder has more than 300 supported images. Choose a smaller folder. Nothing was saved."
        case .imageTooLarge: "Image exceeds the 40 MB or 80 megapixel limit."
        case .unreadableImage: "Image could not be decoded or analyzed."
        case .changed: "The folder or image changed. Analyze the folder again before opening this result."
        case .unavailable: "Visual analysis is unavailable. Try again; no previous results were replaced."
        case .queryTooLong: "Use up to 200 characters to search labels or image text."
        }
    }

    static func message(for error: any Error) -> String {
        guard let folderError = error as? FolderComparisonError else { return error.localizedDescription }
        switch folderError {
        case .limitExceeded: return "This folder is too large to analyze. Choose a smaller folder (up to 25,000 entries, 64 levels, and 2 MB of paths)."
        case .changed: return VisualSearchError.changed.localizedDescription
        case .fileSystem: return "This folder or an image could not be read. Check its access permissions and try again. Previous analysis was kept."
        default: return VisualSearchError.invalidFolder.localizedDescription
        }
    }
}
