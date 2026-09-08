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
    @State private var fileOpenApplications: FileOpenApplicationCoordinator
    @State private var terminalApplications: TerminalApplicationCoordinator
    @State private var nearbyTransfers: NearbyTransferCoordinator
    @State private var sidebar: SidebarModel
    @State private var themeController: ExplorerThemeController
    @State private var aiSettings: ExplorerAISettings
    @State private var offlineCatalogStore: OfflineCatalogStore
    private let offlineVolumes: LocalOfflineVolumeAccess

    init() {
        self.init(launchConfiguration: ExplorerLaunchConfiguration())
    }

    init(launchConfiguration: ExplorerLaunchConfiguration) {
        self.launchConfiguration = launchConfiguration
        let catalogRoot = (launchConfiguration.fixtureRoot ?? URL.temporaryDirectory.appending(path: "FinallyExplorer-UI-\(UUID())"))
            .appending(path: ".offline-catalog-storage")
        _offlineCatalogStore = State(initialValue: launchConfiguration.isUITesting ? OfflineCatalogStore(rootURL: catalogRoot) : .shared)
        offlineVolumes = LocalOfflineVolumeAccess(fixtureVolumes: launchConfiguration.isUITesting
            ? launchConfiguration.mountedVolumeFixture.map { [OfflineCatalogVolume(
                id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)), name: "UI Test Disk", rootURL: $0
            )] } ?? [] : nil)
        let applicationUninstallPolicy = Self.applicationUninstallPolicy(
            for: launchConfiguration
        )
        _workspace = State(
            initialValue: WorkspaceModel(initialPlace: launchConfiguration.initialPlace)
        )
        _fileOperations = State(
            initialValue: Self.fileOperationCoordinator(
                for: launchConfiguration,
                applicationUninstallPolicy: applicationUninstallPolicy
            )
        )
        _fileOpenApplications = State(
            initialValue: Self.fileOpenApplicationCoordinator(
                for: launchConfiguration
            )
        )
        _terminalApplications = State(
            initialValue: TerminalApplicationCoordinator(
                preferenceStore: Self.terminalPreferenceStore(
                    for: launchConfiguration
                )
            )
        )
        _nearbyTransfers = State(
            initialValue: Self.nearbyTransferCoordinator(for: launchConfiguration)
        )
        _sidebar = State(
            initialValue: SidebarModel(
                store: Self.sidebarStore(for: launchConfiguration),
                visibilityStore: Self.sidebarVisibilityStore(
                    for: launchConfiguration
                ),
                mountedVolumeMonitor: Self.mountedVolumeMonitor(
                    for: launchConfiguration
                )
            )
        )
        _themeController = State(
            initialValue: ExplorerThemeController(
                store: Self.themeStore(for: launchConfiguration)
            )
        )
        _aiSettings = State(initialValue: ExplorerAISettings(
            defaults: Self.isolatedDefaults(for: launchConfiguration) ?? .standard
        ))
    }

    var body: some Scene {
        WindowGroup("Finally Explorer") {
            ContentView(
                workspace: workspace,
                fileOperations: fileOperations,
                fileOpenApplications: fileOpenApplications,
                terminalApplications: terminalApplications,
                nearbyTransfers: nearbyTransfers,
                sidebar: sidebar,
                themeController: themeController,
                aiSettings: aiSettings,
                offlineCatalogStore: offlineCatalogStore,
                offlineVolumes: offlineVolumes,
                globalSearchRootURL: launchConfiguration.fixtureRoot
                    ?? URL(filePath: "/", directoryHint: .isDirectory)
            )
        }
        .windowStyle(.titleBar)
        .windowBackgroundDragBehavior(.enabled)
        .commands {
            FileEditCommands()
        }

        Settings {
            ExplorerAISettingsView(settings: aiSettings)
                .environment(\.explorerTheme, themeController.activeTheme)
        }
        .windowResizability(.contentSize)
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

    private static func fileOpenApplicationCoordinator(
        for launchConfiguration: ExplorerLaunchConfiguration
    ) -> FileOpenApplicationCoordinator {
        guard launchConfiguration.isUITesting else {
            return FileOpenApplicationCoordinator()
        }

        return FileOpenApplicationCoordinator(
            applicationLoader: { _ in
                [
                    FileOpenApplication(
                        name: "Fixture Viewer",
                        applicationURL: URL(
                            filePath: "/Applications/Fixture Viewer.app",
                            directoryHint: .isDirectory
                        )
                    )
                ]
            },
            fileOpener: { _, _ in }
        )
    }

    private static func sidebarVisibilityStore(
        for launchConfiguration: ExplorerLaunchConfiguration
    ) -> (any SidebarVisibilityStoring)? {
        guard let suiteName = launchConfiguration.defaultsSuiteName,
              let defaults = UserDefaults(suiteName: suiteName) else {
            return nil
        }

        return UserDefaultsSidebarVisibilityStore(defaults: defaults)
    }

    private static func fileOperationCoordinator(
        for launchConfiguration: ExplorerLaunchConfiguration,
        applicationUninstallPolicy: ApplicationUninstallPolicy
    ) -> FileOperationCoordinator {
        guard launchConfiguration.isUITesting else {
            return FileOperationCoordinator(
                applicationUninstallPolicy: applicationUninstallPolicy
            )
        }

        return FileOperationCoordinator(
            noticeDelay: {
                try await Task.sleep(for: .seconds(8))
            },
            applicationUninstallPolicy: applicationUninstallPolicy
        )
    }

    private static func applicationUninstallPolicy(
        for launchConfiguration: ExplorerLaunchConfiguration
    ) -> ApplicationUninstallPolicy {
        .live(
            additionalApplicationDirectoryURLs: launchConfiguration.fixtureRoot.map {
                [$0]
            } ?? []
        )
    }

    private static func mountedVolumeMonitor(
        for launchConfiguration: ExplorerLaunchConfiguration
    ) -> MountedVolumeMonitor? {
        guard launchConfiguration.isUITesting else {
            return nil
        }

        return MountedVolumeMonitor(
            loadVolumes: {
                guard let fixtureURL = launchConfiguration.mountedVolumeFixture else { return [] }
                return [
                    MountedVolume(
                        url: fixtureURL,
                        title: fixtureURL.lastPathComponent,
                        isInternal: false,
                        isRemovable: true,
                        isEjectable: true,
                        isBrowsable: true
                    )
                ]
            },
            ejector: UITestMountedVolumeEjector(),
            observesWorkspaceChanges: false
        )
    }

    private static func terminalPreferenceStore(
        for launchConfiguration: ExplorerLaunchConfiguration
    ) -> (any TerminalPreferenceStoring)? {
        guard let defaults = isolatedDefaults(for: launchConfiguration) else {
            return nil
        }

        return UserDefaultsTerminalPreferenceStore(defaults: defaults)
    }

    private static func nearbyTransferCoordinator(
        for launchConfiguration: ExplorerLaunchConfiguration
    ) -> NearbyTransferCoordinator {
        guard ExplorerFeatureFlags.nearbyTransferEnabled else {
            return NearbyTransferCoordinator(
                service: DisabledNearbyTransferService()
            )
        }
        guard let peerName = launchConfiguration.nearbyPeerName else {
            return NearbyTransferCoordinator()
        }
        return NearbyTransferCoordinator(
            service: UITestNearbyTransferService(peerName: peerName)
        )
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
