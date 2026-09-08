import Darwin
import Foundation

/// An identity/change token, not a claim that two files contain the same bytes.
nonisolated struct ComparedFileState: Equatable, Sendable {
    let device: Int32
    let inode: UInt64
    let mode: UInt16
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64
    let flags: UInt32
    let linkCount: UInt16

    init(_ value: stat) {
        device = value.st_dev
        inode = value.st_ino
        mode = value.st_mode
        size = value.st_size
        modifiedSeconds = Int64(value.st_mtimespec.tv_sec)
        modifiedNanoseconds = Int64(value.st_mtimespec.tv_nsec)
        changedSeconds = Int64(value.st_ctimespec.tv_sec)
        changedNanoseconds = Int64(value.st_ctimespec.tv_nsec)
        flags = value.st_flags
        linkCount = value.st_nlink
    }

    var isDirectory: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFDIR) }
    var isRegularFile: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFREG) }
    var isPlaceholder: Bool { flags & UInt32(SF_DATALESS) != 0 }
    var isHidden: Bool { flags & UInt32(UF_HIDDEN) != 0 }

    func hasSameIdentity(as other: Self) -> Bool {
        device == other.device && inode == other.inode
            && mode & UInt16(S_IFMT) == other.mode & UInt16(S_IFMT)
    }
}
