import Foundation
import Testing
@testable import FinallyExplorer

@MainActor
struct FolderOrganizationModelTests {
    @Test("Review is read-only and cancelled or invalidated approvals cannot move files")
    func reviewBoundary() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let source = try fixture.write("Report.txt", "data")
        let operations = FileOperationCoordinator()
        let model = FolderOrganizationModel(rootURL: fixture.source, operations: operations)
        #expect(model.canReview == false)
        await model.preview()?.value
        model.reviewMoves()
        let cancelled = try #require(model.review)
        model.review = nil
        #expect(model.confirmMoves(cancelled) == false)
        model.reviewMoves()
        let stale = try #require(model.review)
        model.rule = .modifiedMonth
        #expect(model.review == nil)
        #expect(model.plan == nil)
        #expect(model.confirmMoves(stale) == false)
        await model.preview()?.value
        model.reviewMoves()
        #expect(model.confirmMoves(stale) == false)
        model.includesHidden = true
        #expect(model.review == nil)
        #expect(operations.completedOperationCount == 0)
        #expect(try String(contentsOf: source, encoding: .utf8) == "data")
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.source.path) == ["Report.txt"])
    }

    @Test("Confirmed organization shares the mutation gate, preserves clipboard and refreshes both folders", arguments: ["new", "Documents", "documents"])
    func coordinatorIntegration(_ existingFolder: String) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Report.txt", "data")
        if existingFolder != "new" {
            try FileManager.default.createDirectory(at: fixture.source.appending(path: existingFolder), withIntermediateDirectories: true)
        }
        let clipboard = try fixture.write("Clipboard.txt", "clipboard", in: fixture.destination)
        let operations = FileOperationCoordinator()
        operations.copy([clipboard])
        let model = FolderOrganizationModel(rootURL: fixture.source, operations: operations)
        await model.preview()?.value
        model.reviewMoves()
        let approved = try #require(model.review)
        #expect(model.confirmMoves(approved))
        #expect(model.isApplying)
        #expect(model.canPreview == false)
        #expect(model.confirmMoves(approved) == false)
        #expect(operations.paste(into: fixture.source) == false)
        #expect(operations.rename(clipboard, to: "Changed.txt") == false)
        await operations.waitForCurrentOperation()
        #expect(model.report?.movedFiles.map(\.sourceName) == ["Report.txt"])
        #expect(model.report?.errorMessage == nil)
        #expect(model.plan == nil)
        #expect(model.review == nil)
        #expect(model.progress == nil)
        #expect(model.isWorking == false)
        #expect(model.canReview == false)
        #expect(model.canPreview)
        #expect(operations.isPerforming == false)
        #expect(operations.completedOperationCount == 1)
        #expect(operations.directoryRefreshRevision(for: fixture.source) == 1)
        #expect(operations.directoryRefreshRevision(for: fixture.source.appending(path: "Documents")) == 1)
        if existingFolder == "documents",
           try ScopedFolderDescriptor(rootURL: fixture.source.appending(path: "documents")).state().hasSameIdentity(
            as: ScopedFolderDescriptor(rootURL: fixture.source.appending(path: "Documents")).state()) {
            #expect(operations.directoryRefreshRevision(for: fixture.source.appending(path: "documents")) == 1)
        }
        #expect(operations.directoryRefreshRevision(for: fixture.destination) == 0)
        #expect(operations.clipboardURLs == [clipboard])
        #expect(operations.clipboardOperation == .copy)
        await model.preview()?.value
        #expect(model.report == nil)
        #expect(model.plan?.proposed.isEmpty == true)
    }

    @Test("Cancellation keeps the write gate until unwind, refreshes partial work and invalidates review", .timeLimit(.minutes(1)))
    func cancelApply() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("A.txt", "first")
        try fixture.write("Z.txt", "last")
        let gate = FolderComparisonTestGate()
        let operations = FileOperationCoordinator(organizationService: PausedOrganizationApplier(gate: gate))
        let model = FolderOrganizationModel(rootURL: fixture.source, operations: operations)
        await model.preview()?.value
        model.reviewMoves()
        let approved = try #require(model.review)
        #expect(model.confirmMoves(approved))
        await gate.waitUntilEntered()
        let competing = FolderOrganizationModel(rootURL: fixture.source, operations: operations)
        #expect(competing.preview() == nil)
        model.cancel()
        #expect(model.isCancelling)
        #expect(model.isApplying)
        #expect(operations.isPerforming)
        #expect(model.canPreview == false)
        await gate.release()
        await operations.waitForCurrentOperation()
        #expect(model.report?.wasCancelled == true)
        #expect(model.report?.movedFiles.map(\.sourceName) == ["A.txt"])
        #expect(model.isCancelling == false)
        #expect(model.isWorking == false)
        #expect(model.plan == nil)
        #expect(model.canReview == false)
        #expect(model.canPreview)
        #expect(operations.directoryRefreshRevision(for: fixture.source) == 1)
        #expect(operations.directoryRefreshRevision(for: fixture.source.appending(path: "Documents")) == 1)
        #expect(try String(contentsOf: fixture.source.appending(path: "Z.txt"), encoding: .utf8) == "last")
    }

    @Test("Failed preflight reports the problem without announcing a filesystem change")
    func failedApply() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Report.txt", "data")
        let operations = FileOperationCoordinator()
        let model = FolderOrganizationModel(rootURL: fixture.source, operations: operations)
        await model.preview()?.value
        model.reviewMoves()
        let approved = try #require(model.review)
        try fixture.write("Report.txt", "edit")
        #expect(model.confirmMoves(approved))
        await operations.waitForCurrentOperation()
        #expect(model.report?.errorMessage != nil)
        #expect(model.report?.movedFiles.isEmpty == true)
        #expect(model.plan == nil)
        #expect(operations.completedOperationCount == 0)
        #expect(operations.isPerforming == false)
        #expect(model.canPreview)
    }
}

private nonisolated struct PausedOrganizationApplier: FolderOrganizationApplying {
    let gate: FolderComparisonTestGate
    func apply(_ plan: FolderOrganizationMovePlan,
               progress: @escaping @Sendable (FolderWorkProgress) async -> Void) async -> FolderOrganizationReport {
        await FolderOrganizationApplyService().apply(plan) { value in
            await progress(value)
            if value.phase == "Moving approved files…", value.completedItems == 1 { await gate.pause() }
        }
    }
}
