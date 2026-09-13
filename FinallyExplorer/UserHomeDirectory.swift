import Foundation

nonisolated enum UserHomeDirectory {
    /// `homeDirectoryForCurrentUser` is the app container when sandboxed. A named
    /// account lookup identifies the real home, but grants no permission to read it.
    static var url: URL {
        FileManager.default.homeDirectory(forUser: NSUserName())
            ?? FileManager.default.homeDirectoryForCurrentUser
    }
}
