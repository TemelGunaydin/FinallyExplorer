import Foundation
import Observation

@MainActor
@Observable
final class FolderComparisonModel: Identifiable {
    let id = UUID()
    let locations: [FolderComparisonLocation]
    var sourceID: UUID? { didSet { if oldValue != sourceID { invalidate() } } }
    var destinationID: UUID? { didSet { if oldValue != destinationID { invalidate() } } }
    var includesHidden = false { didSet { if oldValue != includesHidden { invalidate() } } }
    var filter: FolderComparisonFilter = .differences { didSet { updateVisibleRows() } }
    var copyConfirmation: VerifiedCopyPlan?
    private(set) var snapshot: FolderComparisonSnapshot?
    private(set) var visibleRows: [FolderComparisonRow] = []
    private(set) var copyCandidate: VerifiedCopyPlan?
    private(set) var summary = ""
    private(set) var isComparing = false
    private(set) var isCopying = false
    private(set) var isCancelling = false
    private(set) var progress: FolderWorkProgress?
    private(set) var errorMessage: String?
    private(set) var report: VerifiedCopyReport?

    @ObservationIgnored private let comparer: any FolderComparing
    @ObservationIgnored private let operations: FileOperationCoordinator
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(
        locations: [FolderComparisonLocation], preferredSourceID: UUID?,
        operations: FileOperationCoordinator, comparer: any FolderComparing = FolderComparisonService()
    ) {
        self.locations = locations
        self.operations = operations
        self.comparer = comparer
        let source = locations.first { $0.id == preferredSourceID } ?? locations.first
        sourceID = source?.id
        destinationID = locations.first { $0.id != source?.id && $0.url != source?.url }?.id
            ?? locations.first { $0.id != source?.id }?.id
    }

    deinit { task?.cancel() }

    var source: FolderComparisonLocation? { locations.first { $0.id == sourceID } }
    var destination: FolderComparisonLocation? { locations.first { $0.id == destinationID } }
    var isWorking: Bool { isComparing || isCopying }
    var canCompare: Bool {
        guard let source, let destination else { return false }
        return source.id != destination.id && source.url.standardizedFileURL != destination.url.standardizedFileURL
            && isWorking == false && operations.isPerforming == false
    }
    var canReviewCopy: Bool {
        (copyCandidate?.entries.isEmpty == false) && isWorking == false && operations.isPerforming == false
    }

    @discardableResult
    func compare() -> Task<Void, Never>? {
        guard canCompare, let source, let destination else { return nil }
        invalidate()
        isComparing = true
        progress = FolderWorkProgress(phase: "Preparing comparison…", relativePath: "")
        let current = generation, hidden = includesHidden
        task = Task { [weak self, comparer] in
            do {
                let snapshot = try await comparer.compare(source: source.url, destination: destination.url, includesHidden: hidden) { [weak self] progress in
                    await self?.receive(progress, generation: current)
                }
                try Task.checkCancellation()
                guard let self, generation == current else { return }
                let candidate = try VerifiedCopyPlan(snapshot: snapshot)
                self.snapshot = snapshot
                copyCandidate = candidate
                let same = snapshot.rows.count { $0.status == .same }
                let different = snapshot.rows.count { $0.status == .different || $0.status == .conflict }
                let skipped = snapshot.rows.count { $0.status == .skipped }
                summary = "Same: \(same) · Changed/conflicting: \(different) · Files to add: \(candidate.fileCount) · Not compared: \(skipped)"
                updateVisibleRows()
                finishComparison()
            } catch {
                guard let self, generation == current else { return }
                if Task.isCancelled == false { errorMessage = error.localizedDescription }
                finishComparison()
            }
        }
        return task
    }

    func reviewCopy() {
        guard canReviewCopy else { return }
        copyConfirmation = copyCandidate
    }

    @discardableResult
    func confirmCopy(_ approvedPlan: VerifiedCopyPlan) -> Bool {
        guard canReviewCopy, copyConfirmation?.id == approvedPlan.id, copyCandidate?.id == approvedPlan.id else { return false }
        copyConfirmation = nil
        isCopying = true
        report = nil
        errorMessage = nil
        progress = FolderWorkProgress(phase: "Checking approved items…", relativePath: "")
        let started = operations.startVerifiedCopy(approvedPlan) { [weak self] progress in
            self?.progress = progress
        } onCompletion: { [weak self] report in
            guard let self else { return }
            isCopying = false
            isCancelling = false
            progress = nil
            // Even a partially completed operation makes the old comparison stale.
            clearSnapshot()
            self.report = report
        }
        if started == false {
            isCopying = false
            progress = nil
            errorMessage = "Another file operation is running. Try again when it finishes."
        }
        return started
    }

    func cancel() {
        if isCopying {
            isCancelling = true
            operations.cancelCurrentOperation()
        } else {
            generation += 1
            task?.cancel()
            finishComparison()
        }
    }

    private func invalidate() {
        guard isCopying == false else { return }
        cancel()
        clearSnapshot()
        report = nil
        errorMessage = nil
    }

    private func clearSnapshot() {
        snapshot = nil
        visibleRows = []
        copyCandidate = nil
        copyConfirmation = nil
        summary = ""
    }

    private func receive(_ progress: FolderWorkProgress, generation: Int) {
        guard self.generation == generation, isComparing else { return }
        self.progress = progress
    }

    private func finishComparison() {
        isComparing = false
        progress = nil
        task = nil
    }

    private func updateVisibleRows() {
        guard let snapshot else { visibleRows = []; return }
        switch filter {
        case .all: visibleRows = snapshot.rows
        case .differences: visibleRows = snapshot.rows.filter { $0.status != .same && $0.status != .folder }
        case .copyable:
            let paths = Set(copyCandidate?.entries.map(\.relativePath) ?? [])
            visibleRows = snapshot.rows.filter { paths.contains($0.relativePath) }
        }
    }
}
