import Foundation
import Observation

@MainActor
@Observable
final class ExplorerAISettings {
    var isSmartRenameEnabled: Bool {
        didSet { defaults.set(isSmartRenameEnabled, forKey: Self.enabledKey) }
    }
    var usesFileContentsByDefault: Bool {
        didSet { defaults.set(usesFileContentsByDefault, forKey: Self.contentsKey) }
    }
    private(set) var availability: SmartRenameAvailability?
    private(set) var isCheckingAvailability = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let service: any SmartRenameServicing
    @ObservationIgnored private var availabilityGeneration = 0

    private static let enabledKey = "smartRename.enabled"
    private static let contentsKey = "smartRename.useFileContentsByDefault"

    init(
        defaults: UserDefaults = .standard,
        service: any SmartRenameServicing = FoundationModelsSmartRenameService()
    ) {
        self.defaults = defaults
        self.service = service
        isSmartRenameEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        usesFileContentsByDefault = defaults.object(forKey: Self.contentsKey) as? Bool ?? true
    }

    func refreshAvailability() async {
        availabilityGeneration += 1
        let generation = availabilityGeneration
        isCheckingAvailability = true
        let currentAvailability = await service.availability()
        guard generation == availabilityGeneration else { return }
        isCheckingAvailability = false
        guard Task.isCancelled == false else { return }
        availability = currentAvailability
    }
}
