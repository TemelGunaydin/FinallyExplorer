import Foundation
import Observation

@MainActor @Observable
final class DuplicateFilesModel: Identifiable {
    let id = UUID()
    let rootURL: URL
    var includesHidden = false { didSet { if oldValue != includesHidden { reset() } } }
    var review: DuplicateTrashPlan?
    private(set) var snapshot: DuplicateScanSnapshot?
    private(set) var selection: Set<String> = []
    private(set) var progress: FolderWorkProgress?
    private(set) var isScanning = false
    private(set) var isTrashing = false
    private(set) var isCancelling = false
    private(set) var errorMessage: String?
    private(set) var report: DuplicateTrashReport?
    @ObservationIgnored private let finder: any DuplicateFinding
    @ObservationIgnored private let operations: FileOperationCoordinator
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(rootURL: URL, operations: FileOperationCoordinator, finder: any DuplicateFinding = DuplicateFileService()) {
        self.rootURL = rootURL
        self.operations = operations
        self.finder = finder
    }

    deinit { task?.cancel() }
    var isWorking: Bool { isScanning || isTrashing }
    var canScan: Bool { isWorking == false && operations.isPerforming == false }
    var canReview: Bool { canScan && selection.isEmpty == false && snapshot != nil }

    @discardableResult
    func scan() -> Task<Void, Never>? {
        guard canScan else { return nil }
        reset()
        isScanning = true
        progress = FolderWorkProgress(phase: "Reading folder…", relativePath: rootURL.path)
        let current = generation, hidden = includesHidden, root = rootURL
        task = Task { [weak self, finder] in
            do {
                let snapshot = try await finder.scan(rootURL: root, includesHidden: hidden) { [weak self] progress in
                    await self?.receive(progress, generation: current)
                }
                try Task.checkCancellation()
                guard let self, generation == current else { return }
                self.snapshot = snapshot
                finishScan()
            } catch {
                guard let self, generation == current else { return }
                if Task.isCancelled == false { errorMessage = FileToolsError.message(for: error) }
                finishScan()
            }
        }
        return task
    }

    func toggle(_ file: ComparedFolderEntry, in group: DuplicateGroup) {
        guard canScan, snapshot?.groups.contains(where: { $0.id == group.id }) == true,
              group.files.contains(where: { $0.relativePath == file.relativePath }) else { return }
        if selection.contains(file.relativePath) { selection.remove(file.relativePath) }
        else if group.files.count(where: { selection.contains($0.relativePath) }) < group.files.count - 1 {
            selection.insert(file.relativePath)
        }
        review = nil
    }

    func clearSelection() { guard isWorking == false else { return }; selection = []; review = nil }

    func reviewTrash() {
        guard canReview, let snapshot else { return }
        do { review = try DuplicateTrashPlan(snapshot: snapshot, selection: selection) }
        catch { errorMessage = FileToolsError.message(for: error) }
    }

    @discardableResult
    func confirmTrash(_ plan: DuplicateTrashPlan) -> Bool {
        guard canReview, review?.id == plan.id, Set(plan.pairs.map(\.id)) == selection else { return false }
        let started = operations.startDuplicateTrash(plan) { [weak self] in self?.progress = $0 } onCompletion: { [weak self] report in
            guard let self else { return }
            isTrashing = false
            isCancelling = false
            progress = nil
            snapshot = nil
            selection = []
            review = nil
            self.report = report
        }
        if started {
            review = nil
            isTrashing = true
            progress = FolderWorkProgress(phase: "Rechecking approved files…", relativePath: "")
        }
        return started
    }

    func cancel() {
        if isTrashing {
            isCancelling = true
            operations.cancelCurrentOperation()
        } else {
            generation += 1
            task?.cancel()
            finishScan()
        }
    }

    private func reset() {
        guard isTrashing == false else { return }
        cancel()
        snapshot = nil
        selection = []
        review = nil
        report = nil
        errorMessage = nil
    }
    private func finishScan() { isScanning = false; progress = nil; task = nil }
    private func receive(_ value: FolderWorkProgress, generation: Int) {
        guard self.generation == generation, isScanning else { return }
        progress = value
    }
}
