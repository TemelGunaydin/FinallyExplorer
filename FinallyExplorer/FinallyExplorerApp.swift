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

    init() {
        self.init(launchConfiguration: ExplorerLaunchConfiguration())
    }

    init(launchConfiguration: ExplorerLaunchConfiguration) {
        self.launchConfiguration = launchConfiguration
        _workspace = State(
            initialValue: WorkspaceModel(initialPlace: launchConfiguration.initialPlace)
        )
        _fileOperations = State(initialValue: FileOperationCoordinator())
        _terminalApplications = State(initialValue: TerminalApplicationCoordinator())
        _sidebar = State(
            initialValue: SidebarModel(
                store: Self.sidebarStore(for: launchConfiguration)
            )
        )
    }

    var body: some Scene {
        WindowGroup("Finally Explorer") {
            ContentView(
                workspace: workspace,
                fileOperations: fileOperations,
                terminalApplications: terminalApplications,
                sidebar: sidebar
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
}
