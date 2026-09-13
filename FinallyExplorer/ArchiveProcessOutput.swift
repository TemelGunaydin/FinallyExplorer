import Foundation

/// Drain diagnostics while the child is running so a full pipe cannot block it.
/// Keep only a bounded prefix; reading must continue even after that limit.
nonisolated enum ArchiveProcessOutput {
    static func collect(from handle: FileHandle, limit: Int = 16_384) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                defer { try? handle.close() }
                var prefix = Data()
                while let chunk = try? handle.read(upToCount: 65_536), !chunk.isEmpty {
                    let remaining = max(0, limit - prefix.count)
                    if remaining > 0 { prefix.append(chunk.prefix(remaining)) }
                }
                continuation.resume(returning: prefix)
            }
        }
    }
}
