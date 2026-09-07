import Foundation
import Testing
@testable import FinallyExplorer

@MainActor
struct FolderComparisonModelTests {
    @Test("Compare and review are read-only; only an approved, current plan can copy")
    func explicitConfirmationAndRefresh() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Report.txt", "report")
        let operations = FileOperationCoordinator()
        let model = makeModel(fixture, operations: operations)
        #expect(model.snapshot == nil)
        await model.compare()?.value
        #expect(model.canReviewCopy)
        #expect(try fixture.destinationNames().isEmpty)
        let candidate = try #require(model.copyCandidate)
        #expect(model.confirmCopy(candidate) == false)
        model.reviewCopy()
        #expect(model.copyConfirmation?.id == candidate.id)
        #expect(try fixture.destinationNames().isEmpty)
        model.copyConfirmation = nil // User dismisses/cancels the review.
        #expect(model.confirmCopy(candidate) == false)
        model.reviewCopy()
        #expect(model.confirmCopy(candidate))
        #expect(model.isCopying)
        #expect(operations.isPerforming)
        await operations.waitForCurrentOperation()
        #expect(model.isWorking == false)
        #expect(operations.isPerforming == false)
        #expect(model.report?.verifiedFiles == ["Report.txt"])
        #expect(model.snapshot == nil)
        #expect(model.copyCandidate == nil)
        #expect(model.canReviewCopy == false)
        #expect(operations.directoryRefreshRevision(for: fixture.destination) > 0)
        #expect(operations.directoryRefreshRevision(for: fixture.source) == 0)
        #expect(try fixture.destinationNames() == ["Report.txt"])
        await model.compare()?.value
        #expect(model.snapshot?.rows.first?.status == .same)
        #expect(model.canReviewCopy == false)
    }

    @Test("Changing the selection or hidden-item scope invalidates the reviewed plan")
    func stalePlan() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("File.txt", "data")
        let model = makeModel(fixture, operations: FileOperationCoordinator())
        await model.compare()?.value
        model.reviewCopy()
        let approved = try #require(model.copyConfirmation)
        model.includesHidden = true
        #expect(model.copyConfirmation == nil)
        #expect(model.canReviewCopy == false)
        #expect(model.confirmCopy(approved) == false)
        await model.compare()?.value
        model.destinationID = model.sourceID
        #expect(model.snapshot == nil)
        #expect(model.canCompare == false)
        #expect(try fixture.destinationNames().isEmpty)
    }

    @Test("Filters distinguish copyable items from conflicts and destination-only data")
    func filtering() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Add.txt", "add")
        try fixture.write("Conflict/File.txt", "child")
        try fixture.write("Conflict", "keep", in: fixture.destination)
        try fixture.write("Same.txt", "same")
        try fixture.write("Same.txt", "same", in: fixture.destination)
        let model = makeModel(fixture, operations: FileOperationCoordinator())
        await model.compare()?.value
        #expect(model.visibleRows.contains { $0.status == .same } == false)
        model.filter = .copyable
        #expect(model.visibleRows.map(\.relativePath) == ["Add.txt"])
        model.filter = .all
        #expect(model.visibleRows.count == 4)
    }

    @Test("A cancelled late comparison cannot restore results or enable copy", .timeLimit(.minutes(1)))
    func lateCompletion() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("File.txt", "data")
        let snapshot = try await fixture.compare()
        let gate = FolderComparisonTestGate()
        let model = makeModel(fixture, operations: FileOperationCoordinator(), comparer: DelayedFolderComparer(snapshot: snapshot, gate: gate))
        let task = try #require(model.compare())
        await gate.waitUntilEntered()
        model.cancel()
        #expect(model.isWorking == false)
        await gate.release()
        await task.value
        #expect(model.snapshot == nil)
        #expect(model.progress == nil)
        #expect(model.canReviewCopy == false)
    }

    @Test("Selection uses the active source panel and works with up to four open panels")
    func locationSelection() {
        let locations = (1...4).map {
            FolderComparisonLocation(id: UUID(), title: "Panel \($0)", url: URL(filePath: "/fixture/\($0)"))
        }
        let model = FolderComparisonModel(locations: locations, preferredSourceID: locations[2].id, operations: FileOperationCoordinator())
        #expect(model.sourceID == locations[2].id)
        #expect(model.destinationID == locations[0].id)
        #expect(model.canCompare)
        model.destinationID = locations[3].id
        #expect(model.canCompare)
        let onePane = FolderComparisonModel(locations: [locations[0]], preferredSourceID: nil, operations: FileOperationCoordinator())
        #expect(onePane.canCompare == false)
        let duplicate = FolderComparisonLocation(id: UUID(), title: "Duplicate", url: locations[0].url)
        let sameFolder = FolderComparisonModel(locations: [locations[0], duplicate], preferredSourceID: nil, operations: FileOperationCoordinator())
        #expect(sameFolder.canCompare == false)
    }

    @Test("Copy failure invalidates the plan and leaves the original destination intact")
    func copyFailure() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("File.txt", "source")
        let operations = FileOperationCoordinator()
        let model = makeModel(fixture, operations: operations)
        await model.compare()?.value
        model.reviewCopy()
        let plan = try #require(model.copyConfirmation)
        try fixture.write("File.txt", "keep", in: fixture.destination)
        #expect(model.confirmCopy(plan))
        await operations.waitForCurrentOperation()
        #expect(model.report?.errorMessage != nil)
        #expect(model.isWorking == false)
        #expect(model.snapshot == nil)
        #expect(model.canReviewCopy == false)
        #expect(operations.completedOperationCount == 0)
        #expect(try String(contentsOf: fixture.destination.appending(path: "File.txt"), encoding: .utf8) == "keep")
    }

    @Test("Verified copying blocks other writes, preserves the clipboard and waits for cancellation cleanup", .timeLimit(.minutes(1)))
    func coordinatorLockAndCancellation() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let source = try fixture.write("File.txt", "data")
        let gate = FolderComparisonTestGate()
        let operations = FileOperationCoordinator(verifiedCopyService: DelayedVerifiedCopyService(gate: gate))
        operations.copy([source])
        let model = makeModel(fixture, operations: operations)
        await model.compare()?.value
        model.reviewCopy()
        #expect(model.confirmCopy(try #require(model.copyConfirmation)))
        await gate.waitUntilEntered()
        #expect(operations.paste(into: fixture.destination) == false)
        #expect(operations.moveToTrash(source) == false)
        #expect(operations.rename(source, to: "Changed.txt") == false)
        #expect(model.canCompare == false)
        model.cancel()
        #expect(model.isCopying)
        #expect(model.isCancelling)
        #expect(operations.isPerforming)
        await gate.release()
        await operations.waitForCurrentOperation()
        #expect(operations.isPerforming == false)
        #expect(model.isWorking == false)
        #expect(model.report?.wasCancelled == true)
        #expect(model.canReviewCopy == false)
        #expect(operations.clipboardURLs == [source])
        #expect(operations.canPaste)
    }

    private func makeModel(
        _ fixture: FolderComparisonTestFixture, operations: FileOperationCoordinator,
        comparer: any FolderComparing = FolderComparisonService()
    ) -> FolderComparisonModel {
        FolderComparisonModel(locations: [
            FolderComparisonLocation(id: UUID(), title: "Panel 1 · Source", url: fixture.source),
            FolderComparisonLocation(id: UUID(), title: "Panel 2 · Destination", url: fixture.destination)
        ], preferredSourceID: nil, operations: operations, comparer: comparer)
    }
}

private nonisolated struct DelayedFolderComparer: FolderComparing {
    let snapshot: FolderComparisonSnapshot
    let gate: FolderComparisonTestGate

    func compare(source: URL, destination: URL, includesHidden: Bool, progress: @escaping @Sendable (FolderWorkProgress) async -> Void) async throws -> FolderComparisonSnapshot {
        await gate.pause()
        // Deliberately ignores cancellation; the model must reject this late result.
        await progress(FolderWorkProgress(phase: "Late progress", relativePath: ""))
        return snapshot
    }
}

private nonisolated struct DelayedVerifiedCopyService: VerifiedCopyServicing {
    let gate: FolderComparisonTestGate

    func copy(_ plan: VerifiedCopyPlan, progress: @escaping @Sendable (FolderWorkProgress) async -> Void) async -> VerifiedCopyReport {
        await progress(FolderWorkProgress(phase: "Preparing", relativePath: "File.txt"))
        await gate.pause()
        return VerifiedCopyReport(destinationURL: plan.snapshot.destinationURL, wasCancelled: Task.isCancelled)
    }
}
