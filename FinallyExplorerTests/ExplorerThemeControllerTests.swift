//
//  ExplorerThemeControllerTests.swift
//  FinallyExplorerTests
//

import Foundation
import Testing
@testable import FinallyExplorer

@MainActor
struct ExplorerThemeControllerTests {
    @Test("Hover preview is reversible and never persists a temporary theme")
    func previewIsTemporary() {
        let store = ExplorerThemeStoreMock(theme: .ocean)
        let controller = ExplorerThemeController(store: store)

        #expect(controller.selectedChoice == .ocean)
        #expect(controller.activeChoice == .ocean)

        controller.preview(.midnight)
        #expect(controller.selectedChoice == .ocean)
        #expect(controller.activeChoice == .midnight)
        #expect(store.savedThemes.isEmpty)

        controller.endPreview()
        #expect(controller.activeChoice == .ocean)
        #expect(store.savedThemes.isEmpty)
    }

    @Test("Clicking a theme commits it and clears an in-flight hover preview")
    func selectionPersists() {
        let store = ExplorerThemeStoreMock(theme: .mesa)
        let controller = ExplorerThemeController(store: store)

        controller.preview(.forest)
        controller.select(.graphite)

        #expect(controller.selectedChoice == .graphite)
        #expect(controller.activeChoice == .graphite)
        #expect(controller.previewedChoice == nil)
        #expect(store.savedThemes == [.graphite])
    }

    @Test("Malformed persisted theme values safely fall back to Mesa")
    func malformedStoredThemeFallsBack() throws {
        let suiteName = "FinallyExplorer.ThemeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("not-a-theme", forKey: "explorer-theme-v1")

        let store = UserDefaultsExplorerThemeStore(defaults: defaults)
        let controller = ExplorerThemeController(store: store)

        #expect(store.loadTheme() == nil)
        #expect(controller.selectedChoice == .mesa)
    }
}

@MainActor
private final class ExplorerThemeStoreMock: ExplorerThemeStoring {
    private let theme: ExplorerThemeChoice?
    private(set) var savedThemes: [ExplorerThemeChoice] = []

    init(theme: ExplorerThemeChoice?) {
        self.theme = theme
    }

    func loadTheme() -> ExplorerThemeChoice? {
        theme
    }

    func saveTheme(_ theme: ExplorerThemeChoice) {
        savedThemes.append(theme)
    }
}
