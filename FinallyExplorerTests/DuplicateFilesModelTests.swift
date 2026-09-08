import Foundation
import Testing
@testable import FinallyExplorer

@MainActor
struct DuplicateFilesModelTests {
    @Test("Scanning never selects files; selection must keep one copy, and cancelling review changes nothing")
    func reviewBoundary() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let source = try fixture.write("A.txt", "same")
        try fixture.write("B.txt", "same")
        let operations = FileOperationCoordinator()
        operations.copy([source])
        let model = DuplicateFilesModel(rootURL: fixture.source, operations: operations)
        await model.scan()?.value
        #expect(model.selection.isEmpty)
        #expect(model.canReview == false)
        let group = try #require(model.snapshot?.groups.first)
        model.toggle(group.files[0], in: group)
        model.toggle(group.files[1], in: group)
        #expect(model.selection == ["A.txt"])
        model.reviewTrash()
        let plan = try #require(model.review)
        #expect(plan.pairs.first?.keep.relativePath == "B.txt")
        model.review = nil
        #expect(model.confirmTrash(plan) == false)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(operations.completedOperationCount == 0)
        model.includesHidden = true
        #expect(model.snapshot == nil)
        #expect(model.selection.isEmpty)
    }

    @Test("A cancelled scan cannot publish stale results", .timeLimit(.minutes(1)))
    func staleCompletion() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let snapshot = try await DuplicateFileService().scan(rootURL: fixture.source)
        let gate = FolderComparisonTestGate()
        let model = DuplicateFilesModel(rootURL: fixture.source, operations: FileOperationCoordinator(), finder: DelayedDuplicateFinder(snapshot: snapshot, gate: gate))
        let task = try #require(model.scan())
        await gate.waitUntilEntered()
        model.cancel()
        await gate.release()
        await task.value
        #expect(model.isWorking == false)
        #expect(model.snapshot == nil)
        #expect(model.progress == nil)
        #expect(model.canReview == false)
    }

    @Test("Confirmed removals use the shared write gate, refresh the folder and invalidate the snapshot")
    func coordinatorIntegration() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("A.txt", "same")
        try fixture.write("B.txt", "same")
        let service = DuplicateTrashService(fileOperations: FileOperationService { urls in
            let source = try #require(urls.first)
            let destination = fixture.destination.appending(path: source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: destination)
            return [source: destination]
        })
        let operations = FileOperationCoordinator(duplicateTrashService: service)
        let model = DuplicateFilesModel(rootURL: fixture.source, operations: operations)
        await model.scan()?.value
        let group = try #require(model.snapshot?.groups.first)
        model.toggle(group.files[0], in: group)
        model.reviewTrash()
        let plan = try #require(model.review)
        #expect(model.confirmTrash(plan))
        #expect(operations.isPerforming)
        #expect(model.canScan == false)
        #expect(model.confirmTrash(plan) == false)
        await operations.waitForCurrentOperation()
        #expect(model.report?.trashedPaths == ["A.txt"])
        #expect(model.snapshot == nil)
        #expect(model.selection.isEmpty)
        #expect(operations.isPerforming == false)
        #expect(operations.completedOperationCount == 1)
    }
}

private nonisolated struct DelayedDuplicateFinder: DuplicateFinding {
    let snapshot: DuplicateScanSnapshot
    let gate: FolderComparisonTestGate
    func scan(rootURL: URL, includesHidden: Bool, progress: @escaping @Sendable (FolderWorkProgress) async -> Void) async throws -> DuplicateScanSnapshot {
        await gate.pause()
        await progress(FolderWorkProgress(phase: "Late result", relativePath: ""))
        return snapshot
    }
}
