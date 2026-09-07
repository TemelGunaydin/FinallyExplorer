import Darwin
import Foundation

/// Descriptor-relative traversal never follows a child symlink. Instances stay
/// local to a background operation; ownership closes each descriptor exactly once.
nonisolated final class ScopedFolderDescriptor {
    let rawValue: Int32

    init(taking rawValue: Int32, path: String) throws {
        guard rawValue >= 0 else { throw FolderComparisonError.fileSystem(path, errno) }
        self.rawValue = rawValue
    }

    convenience init(rootURL: URL) throws {
        guard rootURL.isFileURL, rootURL.host == nil || rootURL.host == "" || rootURL.host == "localhost" else {
            throw FolderComparisonError.invalidFolders
        }
        try self.init(taking: Darwin.open(rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC), path: rootURL.path)
    }

    deinit { Darwin.close(rawValue) }

    func state() throws -> ComparedFileState {
        var value = stat()
        guard fstat(rawValue, &value) == 0 else { throw FolderComparisonError.fileSystem("Open file", errno) }
        return ComparedFileState(value)
    }

    func state(of name: String) throws -> ComparedFileState? {
        try Self.validateComponent(name)
        var value = stat()
        if fstatat(rawValue, name, &value, AT_SYMLINK_NOFOLLOW) == 0 { return ComparedFileState(value) }
        if errno == ENOENT { return nil }
        throw FolderComparisonError.fileSystem(name, errno)
    }

    func openFile(_ name: String) throws -> ScopedFolderDescriptor {
        try Self.validateComponent(name)
        let file = try ScopedFolderDescriptor(taking: openat(rawValue, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC), path: name)
        let value = try file.state()
        guard value.isRegularFile, value.isPlaceholder == false else { throw FolderComparisonError.changed(name) }
        return file
    }

    func directory(_ components: [String]) throws -> ScopedFolderDescriptor {
        var result = try ScopedFolderDescriptor(taking: dup(rawValue), path: "Folder")
        for name in components {
            try Task.checkCancellation()
            try Self.validateComponent(name)
            result = try ScopedFolderDescriptor(taking: openat(result.rawValue, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC), path: name)
        }
        return result
    }

    /// Identity-based ancestry also catches case aliases and alternate mount paths.
    /// This traversal is read-only; user-supplied relative components still reject `..`.
    func containsDirectory(_ other: ScopedFolderDescriptor) throws -> Bool {
        let target = try state()
        var current = try other.directory([])
        for _ in 0..<256 {
            try Task.checkCancellation()
            let identity = try current.state()
            if identity.hasSameIdentity(as: target) { return true }
            let parent = try ScopedFolderDescriptor(
                taking: openat(current.rawValue, "..", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC), path: "Parent folder"
            )
            if try parent.state().hasSameIdentity(as: identity) { return false }
            current = parent
        }
        throw FolderComparisonError.limitExceeded
    }

    func names(limit: Int) throws -> [String] {
        let duplicate = dup(rawValue)
        guard duplicate >= 0 else { throw FolderComparisonError.fileSystem("Folder", errno) }
        guard let directory = fdopendir(duplicate) else {
            let code = errno
            Darwin.close(duplicate)
            throw FolderComparisonError.fileSystem("Folder", code)
        }
        defer { closedir(directory) }
        rewinddir(directory)
        var result: [String] = []
        while true {
            try Task.checkCancellation()
            errno = 0
            guard let entry = readdir(directory) else {
                if errno != 0 { throw FolderComparisonError.fileSystem("Folder", errno) }
                break
            }
            let capacity = Int(entry.pointee.d_namlen) + 1
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(validatingCString: $0) }
            }
            guard let name else { throw FolderComparisonError.changed("A filename cannot be represented safely.") }
            if name == "." || name == ".." { continue }
            guard result.count < limit else { throw FolderComparisonError.limitExceeded }
            result.append(name)
        }
        return result.sorted()
    }

    static func components(_ relativePath: String) throws -> [String] {
        let names = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard names.count <= 64 else { throw FolderComparisonError.limitExceeded }
        for name in names { try validateComponent(name) }
        return names
    }

    private static func validateComponent(_ name: String) throws {
        guard name.isEmpty == false, name != ".", name != "..", name.contains("/") == false,
              name.utf8.contains(0) == false else { throw FolderComparisonError.invalidFolders }
    }
}
