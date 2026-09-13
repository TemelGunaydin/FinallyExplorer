import AppKit

@MainActor
protocol FolderAccessChoosing {
    /// An accepted URL carries AppKit's implicit scope; the receiver must release it.
    func choose(startingAt url: URL?) async -> URL?
}

@MainActor
struct NativeFolderAccessChooser: FolderAccessChoosing {
    func choose(startingAt url: URL?) async -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Allow Folder Access"
        panel.prompt = "Allow Access"
        panel.message = "Choose a folder FinallyExplorer can read and manage. Access will be remembered on this Mac."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = url
        guard await panel.begin() == .OK else { return nil }
        return panel.url
    }
}

@MainActor
enum FolderAccessPicker {
    /// Cancelling leaves the workspace and the persisted grants untouched.
    static func choose(using access: FolderAccessModel, startingAt url: URL?,
                       chooser: (any FolderAccessChoosing)? = nil) async throws -> URL? {
        guard Task.isCancelled == false else { return nil }
        let chooser = chooser ?? NativeFolderAccessChooser()
        guard let selectedURL = await chooser.choose(startingAt: url) else { return nil }
        guard Task.isCancelled == false else {
            selectedURL.stopAccessingSecurityScopedResource()
            return nil
        }
        return try access.acceptPanelSelection(selectedURL)
    }
}
