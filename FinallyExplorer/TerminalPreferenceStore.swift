//
//  TerminalPreferenceStore.swift
//  FinallyExplorer
//

import Foundation

@MainActor
protocol TerminalPreferenceStoring {
    func loadPreferredApplicationID() -> String?
    func savePreferredApplicationID(_ applicationID: String?)
}

@MainActor
struct UserDefaultsTerminalPreferenceStore: TerminalPreferenceStoring {
    private static let storageKey = "preferred-terminal-application-v1"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadPreferredApplicationID() -> String? {
        guard let value = defaults.string(forKey: Self.storageKey) else {
            return nil
        }

        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedValue.isEmpty ? nil : normalizedValue
    }

    func savePreferredApplicationID(_ applicationID: String?) {
        if let applicationID {
            defaults.set(applicationID, forKey: Self.storageKey)
        } else {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }
}
