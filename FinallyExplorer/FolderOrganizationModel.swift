import Foundation
import Observation

@MainActor @Observable
final class FolderOrganizationModel: Identifiable {
    let id = UUID()
    let rootURL: URL
    var rule: FolderOrganizationRule = .fileType { didSet { if rule != oldValue { reset() } } }
    var includesHidden = false { didSet { if includesHidden != oldValue { reset() } } }
    private(set) var plan: FolderOrganizationPlan?
    private(set) var progress: FolderWorkProgress?
    private(set) var isWorking = false
    private(set) var errorMessage: String?
    @ObservationIgnored private let planner: any FolderOrganizationPlanning
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(rootURL: URL, planner: any FolderOrganizationPlanning = FolderOrganizationService()) {
        self.rootURL = rootURL
        self.planner = planner
    }

    deinit { task?.cancel() }

    @discardableResult
    func preview() -> Task<Void, Never>? {
        guard isWorking == false else { return nil }
        reset()
        isWorking = true
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
                if Task.isCancelled == false { errorMessage = FileToolsError.message(for: error) }
                finish()
            }
        }
        return task
    }

    func cancel() { generation += 1; task?.cancel(); finish() }
    private func finish() { task = nil; progress = nil; isWorking = false }
    private func reset() { cancel(); plan = nil; errorMessage = nil }
    private func receive(_ value: FolderWorkProgress, generation: Int) {
        guard self.generation == generation, isWorking else { return }
        progress = value
    }
}
