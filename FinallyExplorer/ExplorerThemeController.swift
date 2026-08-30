//
//  ExplorerThemeController.swift
//  FinallyExplorer
//

import Foundation
import Observation

@MainActor
protocol ExplorerThemeStoring {
    func loadTheme() -> ExplorerThemeChoice?
    func saveTheme(_ theme: ExplorerThemeChoice)
}

@MainActor
struct UserDefaultsExplorerThemeStore: ExplorerThemeStoring {
    private static let storageKey = "explorer-theme-v1"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadTheme() -> ExplorerThemeChoice? {
        guard let rawValue = defaults.string(forKey: Self.storageKey) else {
            return nil
        }

        return ExplorerThemeChoice(rawValue: rawValue)
    }

    func saveTheme(_ theme: ExplorerThemeChoice) {
        defaults.set(theme.rawValue, forKey: Self.storageKey)
    }
}

@MainActor
@Observable
final class ExplorerThemeController {
    private(set) var selectedChoice: ExplorerThemeChoice
    private(set) var previewedChoice: ExplorerThemeChoice?

    @ObservationIgnored private let store: any ExplorerThemeStoring

    init(store: (any ExplorerThemeStoring)? = nil) {
        let store = store ?? UserDefaultsExplorerThemeStore()
        self.store = store
        selectedChoice = store.loadTheme() ?? .mesa
    }

    var activeChoice: ExplorerThemeChoice {
        previewedChoice ?? selectedChoice
    }

    var activeTheme: ExplorerTheme {
        ExplorerTheme.palette(for: activeChoice)
    }

    func preview(_ choice: ExplorerThemeChoice) {
        guard previewedChoice != choice else { return }
        previewedChoice = choice
    }

    func endPreview() {
        previewedChoice = nil
    }

    func select(_ choice: ExplorerThemeChoice) {
        selectedChoice = choice
        previewedChoice = nil
        store.saveTheme(choice)
    }
}
