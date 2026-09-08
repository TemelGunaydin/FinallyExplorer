import Foundation

nonisolated struct DuplicateTrashPlan: Identifiable, Sendable {
    let id = UUID()
    let snapshot: DuplicateScanSnapshot
    let pairs: [DuplicateTrashPair]
    let selectedBytes: Int64

    init(snapshot: DuplicateScanSnapshot, selection: Set<String>) throws {
        guard selection.isEmpty == false else { throw FileToolsError.invalidSelection }
        var pairs: [DuplicateTrashPair] = []
        for group in snapshot.groups {
            let chosen = group.files.filter { selection.contains($0.relativePath) }
            guard chosen.isEmpty == false else { continue }
            guard let keep = group.files.first(where: { selection.contains($0.relativePath) == false }) else {
                throw FileToolsError.invalidSelection
            }
            pairs += chosen.map { DuplicateTrashPair(remove: $0, keep: keep) }
        }
        guard Set(pairs.map(\.id)) == selection else { throw FileToolsError.invalidSelection }
        self.snapshot = snapshot
        self.pairs = pairs.sorted { $0.id < $1.id }
        selectedBytes = pairs.reduce(0) { $0 + $1.remove.state.size }
    }
}
