import Darwin
import Foundation

/// Conservative duplicate policy: resource-fork files and hard links are not candidates.
nonisolated enum DuplicateFileVerifier {
    static func open(_ entry: ComparedFolderEntry, root: ScopedFolderDescriptor) throws -> ScopedFolderDescriptor {
        let names = try ScopedFolderDescriptor.components(entry.relativePath)
        let parent = try root.directory(Array(names.dropLast()))
        let file = try parent.openFile(names[names.count - 1])
        guard entry.state.isRegularFile, entry.state.size > 0, entry.state.linkCount == 1,
              try file.state() == entry.state else { throw FolderComparisonError.changed(entry.relativePath) }
        let size = fgetxattr(file.rawValue, XATTR_RESOURCEFORK_NAME, nil, 0, 0, 0)
        guard size == 0 || (size == -1 && errno == ENOATTR) else {
            throw FileToolsError.unsupportedMetadata(entry.relativePath)
        }
        return file
    }

    static func equalData(
        _ left: ComparedFolderEntry, _ right: ComparedFolderEntry, root: ScopedFolderDescriptor
    ) throws -> Bool {
        let a = try open(left, root: root), b = try open(right, root: root)
        let readerA = FileHandle(fileDescriptor: a.rawValue, closeOnDealloc: false)
        let readerB = FileHandle(fileDescriptor: b.rawValue, closeOnDealloc: false)
        var count: Int64 = 0
        while true {
            try Task.checkCancellation()
            let first = try readerA.read(upToCount: 1_048_576) ?? Data()
            let second = try readerB.read(upToCount: 1_048_576) ?? Data()
            guard first == second else { return false }
            if first.isEmpty { break }
            guard count <= left.state.size - Int64(first.count) else { throw FolderComparisonError.changed(left.relativePath) }
            count += Int64(first.count)
        }
        guard try a.state() == left.state, try b.state() == right.state,
              count == left.state.size, count == right.state.size else { throw FolderComparisonError.changed(left.relativePath) }
        return true
    }
}
