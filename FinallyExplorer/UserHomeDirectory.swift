import Foundation
import Darwin

nonisolated enum UserHomeDirectory {
    /// Foundation's home lookups can return the sandbox container even when a
    /// username is supplied. Consult the account database using its reentrant API.
    /// This identifies the location only; it never grants permission to read it.
    static var url: URL {
        accountHomeURL
            ?? FileManager.default.homeDirectory(forUser: NSUserName())
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private static let accountHomeURL: URL? = {
        var capacity = 16_384
        while capacity <= 1_048_576 {
            var buffer = [CChar](repeating: 0, count: capacity)
            let (code, path): (Int32, String?) = buffer.withUnsafeMutableBufferPointer { storage in
                var record = passwd()
                var result: UnsafeMutablePointer<passwd>?
                let code = getpwuid_r(getuid(), &record, storage.baseAddress, storage.count, &result)
                guard code == 0, result != nil, let directory = record.pw_dir else { return (code, nil) }
                // Copy before the buffer's lifetime ends; never retain C pointers.
                return (code, String(validatingCString: directory))
            }
            if code == ERANGE { capacity *= 2; continue }
            guard code == 0, let path, path.hasPrefix("/") else { return nil }
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        return nil
    }()

    static func standardFolder(_ name: String) -> URL {
        url.appending(path: name, directoryHint: .isDirectory)
    }
}
