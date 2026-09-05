import Foundation
import Testing
@testable import FinallyExplorer

@MainActor
struct ExplorerAISettingsTests {
    @Test("Smart Rename preferences persist across app sessions")
    func persistsPreferences() throws {
        let suite = "FinallyExplorer.AISettingsTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ExplorerAISettings(defaults: defaults)
        settings.isSmartRenameEnabled = false
        settings.usesFileContentsByDefault = false
        settings.isSmartSearchEnabled = false

        let reopened = ExplorerAISettings(defaults: defaults)
        #expect(reopened.isSmartRenameEnabled == false)
        #expect(reopened.usesFileContentsByDefault == false)
        #expect(reopened.isSmartSearchEnabled == false)
    }

    @Test("Smart Search and Smart Rename have independent switches")
    func independentFeatures() throws {
        let suite = "FinallyExplorer.AISettingsTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ExplorerAISettings(defaults: defaults)
        #expect(settings.isSmartSearchEnabled)
        settings.isSmartRenameEnabled = false
        #expect(settings.isSmartSearchEnabled)
        settings.isSmartRenameEnabled = true
        settings.isSmartSearchEnabled = false
        #expect(settings.isSmartRenameEnabled)
    }

    @Test("Availability refresh does not run a name generation")
    func checksAvailabilityWithoutGenerating() async throws {
        let suite = "FinallyExplorer.AISettingsTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ExplorerAISettings(defaults: defaults, service: SettingsTestRenameService())
        await settings.refreshAvailability()
        #expect(settings.availability == .modelNotReady)
        #expect(settings.isCheckingAvailability == false)
    }
}

private struct SettingsTestRenameService: SmartRenameServicing {
    func availability() async -> SmartRenameAvailability { .modelNotReady }
    func suggestName(for request: SmartRenameRequest) async throws -> SmartRenameSuggestion {
        Issue.record("Opening AI settings must not generate suggestions or read file content.")
        throw SmartRenameServiceError.unavailable(.modelNotReady)
    }
}
