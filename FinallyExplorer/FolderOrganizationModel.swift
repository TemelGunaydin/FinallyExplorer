import Foundation
import Observation

@MainActor @Observable
final class FolderOrganizationModel: Identifiable {
    let id = UUID()
    let rootURL: URL
    var rule: FolderOrganizationRule = .fileType { didSet { if rule != oldValue { reset() } } }
    var includesHidden = false { didSet { if includesHidden != oldValue { reset() } } }
    var review: FolderOrganizationMovePlan?
    private(set) var plan: FolderOrganizationPlan?
    private(set) var report: FolderOrganizationReport?
    private(set) var progress: FolderWorkProgress?
    private(set) var isPreviewing = false
    private(set) var isApplying = false
    private(set) var isCancelling = false
    private(set) var errorMessage: String?
    @ObservationIgnored private let planner: any FolderOrganizationPlanning
    @ObservationIgnored private let operations: FileOperationCoordinator
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(rootURL: URL, operations: FileOperationCoordinator? = nil,
         planner: any FolderOrganizationPlanning = FolderOrganizationService()) {
        self.rootURL = rootURL
        self.operations = operations ?? FileOperationCoordinator()
        self.planner = planner
    }

    deinit { task?.cancel() }
    var isWorking: Bool { isPreviewing || isApplying }
    var canPreview: Bool { isWorking == false && operations.isPerforming == false }
    var canReview: Bool { canPreview && plan?.proposed.isEmpty == false }

    @discardableResult
    func preview() -> Task<Void, Never>? {
        guard canPreview else { return nil }
        reset()
        isPreviewing = true
        progress = FolderWorkProgress(phase: "Planning folder layout…", relativePath: rootURL.path)
        let current = generation, root = rootURL, rule = rule, hidden = includesHidden
        task = Task { [weak self, planner] in
            do {
                let plan = try await planner.preview(rootURL: root, rule: rule, includesHidden: hidden) { [weak self] value in
                    await self?.receive(value, generation: current)
                }
                try Task.checkCancellation()
                guard let self, generation == current else { return }
                self.plan = plan
                finish()
            } catch {
                guard let self, generation == current else { return }
                if Task.isCancelled == false { errorMessage = FolderOrganizationError.message(for: error) }
                finish()
            }
        }
        return task
    }

    func reviewMoves() {
        guard canReview, let plan else { return }
        do { review = try FolderOrganizationMovePlan(snapshot: plan) }
        catch { errorMessage = FolderOrganizationError.message(for: error) }
    }

    @discardableResult
    func confirmMoves(_ approved: FolderOrganizationMovePlan) -> Bool {
        guard canReview, review?.id == approved.id, plan?.id == approved.snapshot.id else { return false }
        let started = operations.startOrganization(approved) { [weak self] in self?.progress = $0 } onCompletion: { [weak self] report in
            guard let self else { return }
            isApplying = false
            isCancelling = false
            progress = nil
            plan = nil
            review = nil
            self.report = report
        }
        if started {
            review = nil
            isApplying = true
            progress = FolderWorkProgress(phase: "Checking approved moves…", relativePath: "")
        }
        return started
    }

    func cancel() {
        if isApplying { isCancelling = true; operations.cancelCurrentOperation() }
        else { generation += 1; task?.cancel(); finish() }
    }
    private func finish() { task = nil; progress = nil; isPreviewing = false }
    private func reset() {
        guard isApplying == false else { return }
        cancel(); plan = nil; review = nil; report = nil; errorMessage = nil
    }
    private func receive(_ value: FolderWorkProgress, generation: Int) {
        guard self.generation == generation, isPreviewing else { return }
        progress = value
    }
}
