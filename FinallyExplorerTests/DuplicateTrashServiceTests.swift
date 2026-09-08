import Foundation
import Testing
@testable import FinallyExplorer

struct DuplicateTrashServiceTests {
    @Test("Removal plans reject empty, unknown and all-copies selections")
    func selectionValidation() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let snapshot = try await makeDuplicates(fixture)
        for selection: Set<String> in [[], ["Missing.txt"], ["A.txt", "B.txt", "C.txt"]] {
            #expect(throws: FileToolsError.invalidSelection) { try DuplicateTrashPlan(snapshot: snapshot, selection: selection) }
        }
        let plan = try DuplicateTrashPlan(snapshot: snapshot, selection: ["B.txt", "C.txt"])
        #expect(plan.pairs.map(\.id) == ["B.txt", "C.txt"])
        #expect(plan.pairs.allSatisfy { $0.keep.relativePath == "A.txt" })
        #expect(plan.selectedBytes == 8)
    }

    @Test("Approved duplicates go through the recycler while a matching copy and unrelated files remain")
    func approvedRemoval() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Unique.txt", "unique")
        let plan = try DuplicateTrashPlan(snapshot: await makeDuplicates(fixture), selection: ["B.txt", "C.txt"])
        let report = await recycler(fixture).trash(plan)
        #expect(report.trashedPaths == ["B.txt", "C.txt"])
        #expect(report.errorMessage == nil)
        #expect(report.wasCancelled == false)
        #expect(report.changedDirectories == [fixture.source])
        #expect(try String(contentsOf: fixture.source.appending(path: "A.txt"), encoding: .utf8) == "same")
        #expect(try String(contentsOf: fixture.source.appending(path: "Unique.txt"), encoding: .utf8) == "unique")
        #expect(try fixture.destinationNames() == ["B.txt", "C.txt"])
    }

    @Test("Changed retained or selected files invalidate the entire plan before any removal", arguments: ["A.txt", "C.txt"])
    func stalePlan(_ path: String) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let plan = try DuplicateTrashPlan(snapshot: await makeDuplicates(fixture), selection: ["B.txt", "C.txt"])
        try fixture.write(path, "edit")
        let report = await recycler(fixture).trash(plan)
        #expect(report.trashedPaths.isEmpty)
        #expect(report.errorMessage != nil)
        #expect(try fixture.destinationNames().isEmpty)
    }

    @Test("Replacing a duplicate's parent with a link cannot remove outside files")
    func replacedParent() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("A.txt", "same")
        try fixture.write("Nested/B.txt", "same")
        let snapshot = try await DuplicateFileService().scan(rootURL: fixture.source)
        let plan = try DuplicateTrashPlan(snapshot: snapshot, selection: ["Nested/B.txt"])
        let outside = try fixture.write("Outside/B.txt", "same", in: fixture.root)
        try FileManager.default.moveItem(at: fixture.source.appending(path: "Nested"), to: fixture.root.appending(path: "Old Nested"))
        try FileManager.default.createSymbolicLink(at: fixture.source.appending(path: "Nested"), withDestinationURL: outside.deletingLastPathComponent())
        let report = await recycler(fixture).trash(plan)
        #expect(report.trashedPaths.isEmpty)
        #expect(report.errorMessage != nil)
        #expect(try String(contentsOf: outside, encoding: .utf8) == "same")
    }

    @Test("Cancellation during recycling reports the committed item and stops before the next", .timeLimit(.minutes(1)))
    func lateCancellation() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let plan = try DuplicateTrashPlan(snapshot: await makeDuplicates(fixture), selection: ["B.txt", "C.txt"])
        let gate = FolderComparisonTestGate()
        let service = DuplicateTrashService(fileOperations: FileOperationService { urls in
            let source = try #require(urls.first)
            let destination = fixture.destination.appending(path: source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: destination)
            await gate.pause()
            return [source: destination]
        })
        let task = Task { await service.trash(plan) }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.release()
        let report = await task.value
        #expect(report.wasCancelled)
        #expect(report.trashedPaths == ["B.txt"])
        #expect(try fixture.destinationNames() == ["B.txt"])
        #expect(FileManager.default.fileExists(atPath: fixture.source.appending(path: "C.txt").path))
        #expect(FileManager.default.fileExists(atPath: fixture.source.appending(path: "A.txt").path))
    }

    @Test("Keeper is checked again at each removal boundary")
    func keeperChangesBetweenRemovals() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let plan = try DuplicateTrashPlan(snapshot: await makeDuplicates(fixture), selection: ["B.txt", "C.txt"])
        let service = DuplicateTrashService(fileOperations: FileOperationService { urls in
            let source = try #require(urls.first)
            let destination = fixture.destination.appending(path: source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: destination)
            try fixture.write("A.txt", "edit")
            return [source: destination]
        })
        let report = await service.trash(plan)
        #expect(report.trashedPaths == ["B.txt"])
        #expect(report.errorMessage != nil)
        #expect(try String(contentsOf: fixture.source.appending(path: "C.txt"), encoding: .utf8) == "same")
    }

    private func makeDuplicates(_ fixture: FolderComparisonTestFixture) async throws -> DuplicateScanSnapshot {
        for name in ["A.txt", "B.txt", "C.txt"] { try fixture.write(name, "same") }
        return try await DuplicateFileService().scan(rootURL: fixture.source)
    }

    private func recycler(_ fixture: FolderComparisonTestFixture) -> DuplicateTrashService {
        DuplicateTrashService(fileOperations: FileOperationService { urls in
            let source = try #require(urls.first)
            let destination = fixture.destination.appending(path: source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: destination)
            return [source: destination]
        })
    }
}
