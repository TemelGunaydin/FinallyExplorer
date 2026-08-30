//
//  FinallyExplorerApp.swift
//  FinallyExplorer
//
//  Created by temel gunaydin on 14.11.2025.
//

import Foundation
import SwiftUI

@main
@MainActor
struct FinallyExplorerApp: App {
    private let launchConfiguration: ExplorerLaunchConfiguration

    @State private var workspace: WorkspaceModel
    @State private var fileOperations: FileOperationCoordinator
    @State private var terminalApplications: TerminalApplicationCoordinator
    @State private var sidebar: SidebarModel
    @State private var themeController: ExplorerThemeController

    init() {
        self.init(launchConfiguration: ExplorerLaunchConfiguration())
    }

    init(launchConfiguration: ExplorerLaunchConfiguration) {
        self.launchConfiguration = launchConfiguration
        _workspace = State(
            initialValue: WorkspaceModel(initialPlace: launchConfiguration.initialPlace)
        )
        _fileOperations = State(initialValue: FileOperationCoordinator())
        _terminalApplications = State(
            initialValue: TerminalApplicationCoordinator(
                preferenceStore: Self.terminalPreferenceStore(
                    for: launchConfiguration
                )
            )
        )
        _sidebar = State(
            initialValue: SidebarModel(
                store: Self.sidebarStore(for: launchConfiguration)
            )
        )
        _themeController = State(
            initialValue: ExplorerThemeController(
                store: Self.themeStore(for: launchConfiguration)
            )
        )
    }

    var body: some Scene {
        WindowGroup("Finally Explorer") {
            ContentView(
                workspace: workspace,
                fileOperations: fileOperations,
                terminalApplications: terminalApplications,
                sidebar: sidebar,
                themeController: themeController,
                globalSearchRootURL: launchConfiguration.fixtureRoot
                    ?? URL(filePath: "/", directoryHint: .isDirectory)
            )
        }
        .windowStyle(.titleBar)
        .windowBackgroundDragBehavior(.enabled)
        .commands {
            FileEditCommands()
        }
    }

    private static func sidebarStore(
        for launchConfiguration: ExplorerLaunchConfiguration
    ) -> (any SidebarFavoriteStoring)? {
        guard let suiteName = launchConfiguration.defaultsSuiteName,
              let defaults = UserDefaults(suiteName: suiteName) else {
            return nil
        }

        return UserDefaultsSidebarFavoriteStore(defaults: defaults)
    }

    private static func terminalPreferenceStore(
        for launchConfiguration: ExplorerLaunchConfiguration
    ) -> (any TerminalPreferenceStoring)? {
        guard let defaults = isolatedDefaults(for: launchConfiguration) else {
            return nil
        }

        return UserDefaultsTerminalPreferenceStore(defaults: defaults)
    }

    private static func themeStore(
        for launchConfiguration: ExplorerLaunchConfiguration
    ) -> (any ExplorerThemeStoring)? {
        guard let defaults = isolatedDefaults(for: launchConfiguration) else {
            return nil
        }

        return UserDefaultsExplorerThemeStore(defaults: defaults)
    }

    private static func isolatedDefaults(
        for launchConfiguration: ExplorerLaunchConfiguration
    ) -> UserDefaults? {
        guard let suiteName = launchConfiguration.defaultsSuiteName else {
            return nil
        }

        return UserDefaults(suiteName: suiteName)
    }
}
