import CryptoKit
import Foundation

nonisolated enum ComparedFileHasher {
    /// At most one MiB of file data is buffered. No whole-file Data allocation.
    static func digest(
        _ file: ScopedFolderDescriptor,
        expected: ComparedFileState,
        path: String,
        copyingTo destination: ScopedFolderDescriptor? = nil,
        progress: @Sendable (Int64) async -> Void = { _ in }
    ) async throws -> Data {
        try Task.checkCancellation()
        guard expected.isRegularFile, expected.isPlaceholder == false,
              try file.state() == expected else { throw FolderComparisonError.changed(path) }
        let reader = FileHandle(fileDescriptor: file.rawValue, closeOnDealloc: false)
        let writer = destination.map { FileHandle(fileDescriptor: $0.rawValue, closeOnDealloc: false) }
        try reader.seek(toOffset: 0)
        var hasher = SHA256()
        var bytes: Int64 = 0
        var lastUpdate = ContinuousClock.now
        while true {
            try Task.checkCancellation()
            guard let data = try reader.read(upToCount: 1_048_576), data.isEmpty == false else { break }
            guard bytes <= expected.size - Int64(data.count) else { throw FolderComparisonError.changed(path) }
            bytes += Int64(data.count)
            hasher.update(data: data)
            try writer?.write(contentsOf: data)
            if lastUpdate.duration(to: .now) >= .milliseconds(100) {
                await progress(bytes)
                lastUpdate = .now
            }
        }
        try Task.checkCancellation()
        guard bytes == expected.size, try file.state() == expected else { throw FolderComparisonError.changed(path) }
        await progress(bytes)
        return Data(hasher.finalize())
    }
}
