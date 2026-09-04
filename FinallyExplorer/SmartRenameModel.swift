//
//  SmartRenameModel.swift
//  FinallyExplorer
//

import Foundation
import Observation

@MainActor
@Observable
final class SmartRenameModel {
    private(set) var suggestion: SmartRenameSuggestion?
    private(set) var errorMessage: String?
    private(set) var isLoading = false

    @ObservationIgnored private let service: any SmartRenameServicing
    @ObservationIgnored private var requestGeneration = 0
    @ObservationIgnored private var suggestionTask: Task<Void, Never>?

    init(service: any SmartRenameServicing = FoundationModelsSmartRenameService()) {
        self.service = service
    }

    deinit {
        suggestionTask?.cancel()
    }

    func availability() async -> SmartRenameAvailability {
        await service.availability()
    }

    @discardableResult
    func generateSuggestion(
        for request: SmartRenameRequest
    ) -> Task<Void, Never> {
        requestGeneration += 1
        let generation = requestGeneration

        suggestionTask?.cancel()
        suggestion = nil
        errorMessage = nil
        isLoading = true

        let service = service
        let task = Task { @MainActor [weak self] in
            do {
                let suggestion = try await service.suggestName(for: request)
                try Task.checkCancellation()

                guard let self, generation == requestGeneration else { return }
                self.suggestion = suggestion
                self.isLoading = false
                self.suggestionTask = nil
            } catch is CancellationError {
                guard let self, generation == requestGeneration else { return }
                self.isLoading = false
                self.suggestionTask = nil
            } catch {
                guard let self,
                      generation == requestGeneration,
                      Task.isCancelled == false else {
                    return
                }

                self.errorMessage = error.localizedDescription
                self.isLoading = false
                self.suggestionTask = nil
            }
        }

        suggestionTask = task
        return task
    }

    func cancelSuggestion() {
        requestGeneration += 1
        suggestionTask?.cancel()
        suggestionTask = nil
        isLoading = false
    }

    func clear() {
        cancelSuggestion()
        suggestion = nil
        errorMessage = nil
    }

    /// Lets deterministic tests await the model-owned task without sleeping.
    func awaitCurrentGenerationForTesting() async {
        let task = suggestionTask
        await task?.value
    }
}
