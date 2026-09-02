//
//  ContentView.swift
//  FinallyExplorer
//
//  Created by temel gunaydin on 14.11.2025.
//

import AppKit
import Foundation
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @FocusedValue(\.explorerPaneID) private var focusedPaneID

    @State private var workspace = WorkspaceModel()
    @State private var fileOperations = FileOperationCoordinator()
    @State private var terminalApplications = TerminalApplicationCoordinator()
    @State private var nearbyTransfers = NearbyTransferCoordinator()
    @State private var sidebar = SidebarModel()
    @State private var themeController = ExplorerThemeController()
    @State private var globalSearch = GlobalSearchModel()
    @State private var isSidebarFolderPickerPresented = false
    @State private var isPreviewVisible = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private let globalSearchRootURL: URL

    init() {
        globalSearchRootURL = SidebarPlace.systemDrive.url
            ?? URL(filePath: "/", directoryHint: .isDirectory)
    }

    init(
        workspace: WorkspaceModel,
        fileOperations: FileOperationCoordinator,
        terminalApplications: TerminalApplicationCoordinator,
        nearbyTransfers: NearbyTransferCoordinator? = nil,
        sidebar: SidebarModel? = nil,
        themeController: ExplorerThemeController? = nil,
        globalSearch: GlobalSearchModel? = nil,
        globalSearchRootURL: URL = URL(
            filePath: "/",
            directoryHint: .isDirectory
        )
    ) {
        self.globalSearchRootURL = globalSearchRootURL
        _workspace = State(initialValue: workspace)
        _fileOperations = State(initialValue: fileOperations)
        _terminalApplications = State(initialValue: terminalApplications)
        if let nearbyTransfers {
            _nearbyTransfers = State(initialValue: nearbyTransfers)
        }

        if let sidebar {
            _sidebar = State(initialValue: sidebar)
        }
        if let themeController {
            _themeController = State(initialValue: themeController)
        }
        if let globalSearch {
            _globalSearch = State(initialValue: globalSearch)
        }
    }

    private var sidebarSelection: Binding<SidebarPlace?> {
        Binding(
            get: { workspace.activePane?.place },
            set: { newPlace in
                guard let newPlace else { return }

                if let favorite = newPlace.favorite,
                   favorite.isDirectory == false {
                    _ = NSWorkspace.shared.open(favorite.directoryURL)
                    return
                }

                workspace.select(newPlace, in: workspace.activePaneID)
            }
        )
    }

    private var protectedColumnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { columnVisibility },
            set: { proposedVisibility in
                guard proposedVisibility != .detailOnly else { return }
                columnVisibility = proposedVisibility
            }
        )
    }

    private var isMountedVolumeEjectFailurePresented: Binding<Bool> {
        Binding(
            get: { sidebar.mountedVolumeMonitor.ejectFailure != nil },
            set: { isPresented in
                if isPresented == false {
                    sidebar.mountedVolumeMonitor.dismissEjectFailure()
                }
            }
        )
    }

    private var isTrashConfirmationPresented: Binding<Bool> {
        Binding(
            get: { fileOperations.trashConfirmationURLs.isEmpty == false },
            set: { isPresented in
                if isPresented == false {
                    fileOperations.cancelTrashConfirmation()
                }
            }
        )
    }

    private var trashConfirmationTitle: String {
        fileOperations.trashConfirmationURLs.count == 1
            ? "Move to Trash?"
            : "Move \(fileOperations.trashConfirmationURLs.count) Items to Trash?"
    }

    private var trashConfirmationMessage: String {
        if let onlyURL = fileOperations.trashConfirmationURLs.first,
           fileOperations.trashConfirmationURLs.count == 1 {
            "“\(onlyURL.lastPathComponent)” will be moved to Trash."
        } else {
            "The selected items will be moved to Trash."
        }
    }

    private var fileCommandContext: FileCommandContext? {
        guard let pane = workspace.activePane else { return nil }

        return FileCommandContext(pane: pane, coordinator: fileOperations)
    }

    var body: some View {
        @Bindable var fileOperations = fileOperations
        @Bindable var terminalApplications = terminalApplications
        @Bindable var nearbyTransfers = nearbyTransfers
        let theme = themeController.activeTheme

        NavigationSplitView(columnVisibility: protectedColumnVisibility) {
            explorerSidebar
                .background {
                    SidebarSplitViewBehaviorInstaller()
                }
                .navigationSplitViewColumnWidth(
                    min: SidebarSplitViewBehaviorInstaller.minimumWidth,
                    ideal: SidebarSplitViewBehaviorInstaller.idealWidth,
                    max: SidebarSplitViewBehaviorInstaller.maximumWidth
                )
                .toolbar(removing: .sidebarToggle)
        } detail: {
            HStack(spacing: 0) {
                WorkspaceRootView(
                    workspace: workspace,
                    sidebar: sidebar,
                    isPreviewVisible: isPreviewVisible,
                    onTogglePreview: togglePreview,
                    onResetView: resetWorkspaceView
                )

                if workspace.paneCount == 1 {
                    inspectorContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(theme.inspector)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 18,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 18,
                                style: .continuous
                            )
                            .stroke(theme.divider, lineWidth: 0.75)
                        }
                        .padding(6)
                        .frame(width: isPreviewVisible ? 340 : 0)
                        .opacity(isPreviewVisible ? 1 : 0)
                        .allowsHitTesting(isPreviewVisible)
                        .accessibilityIdentifier("preview-inspector")
                }
            }
            .background(theme.canvas)
            .clipShape(.rect(topLeadingRadius: 18))
            .animation(nil, value: isPreviewVisible)
            .animation(nil, value: workspace.paneCount)
        }
        .background(theme.sidebarBackground)
        .overlay(alignment: .bottom) {
            if let notice = fileOperations.notice {
                FileOperationToastView(notice: notice)
                    .id(notice.id)
                    .padding(.bottom, 22)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let progress = nearbyTransfers.progress {
                NearbyTransferActivityView(
                    progress: progress,
                    onCancel: nearbyTransfers.cancelActiveTransfer
                )
                .padding(.trailing, 22)
                .padding(.bottom, 22)
            }
        }
        .animation(.easeOut(duration: 0.18), value: fileOperations.notice?.id)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(
                    "Toggle Sidebar",
                    systemImage: "sidebar.leading",
                    action: toggleSidebar
                )
                .labelStyle(.iconOnly)
                .buttonStyle(ExplorerChromeIconButtonStyle())
                .help("Show or hide the sidebar")
                .accessibilityIdentifier("window-sidebar-toggle")
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem(placement: .principal) {
                GlobalSearchToolbar(
                    model: globalSearch,
                    rootURL: globalSearchRootURL,
                    onReveal: revealGlobalSearchResult
                )
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem(placement: .primaryAction) {
                ExplorerThemePicker(controller: themeController)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .toolbarBackground(theme.windowChrome, for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .toolbar(removing: .title)
        .tint(theme.accent)
        .foregroundStyle(theme.textPrimary)
        .background(theme.canvas)
        .background {
            ExplorerWindowBehaviorInstallers(navigateBack: navigateBack)
        }
        .environment(\.explorerTheme, theme)
        .environment(fileOperations)
        .environment(terminalApplications)
        .environment(nearbyTransfers)
        .focusedSceneValue(\.fileCommandContext, fileCommandContext)
        .onChange(of: scenePhase, initial: true) {
            guard scenePhase == .active else { return }
            terminalApplications.refresh()
        }
        .onChange(of: focusedPaneID) {
            guard let focusedPaneID else { return }
            workspace.activate(focusedPaneID)
        }
        .onChange(of: fileOperations.lastRenameResult) {
            guard let result = fileOperations.lastRenameResult else { return }
            sidebar.applyRename(result)
            workspace.applyRename(result)
        }
        .onChange(of: nearbyTransfers.lastCompletion) {
            guard let completion = nearbyTransfers.lastCompletion else { return }
            Task {
                switch completion.direction {
                case .received:
                    if let destination = completion.destinationDirectoryURL {
                        await fileOperations.recordExternalChange(
                            directlyAffecting: destination,
                            message: completion.itemCount == 1
                                ? "Received from \(completion.peerName)"
                                : "Received \(completion.itemCount) items from \(completion.peerName)",
                            systemImage: "arrow.down.circle.fill"
                        )
                    }
                case .sent:
                    fileOperations.presentExternalNotice(
                        message: completion.itemCount == 1
                            ? "Sent to \(completion.peerName)"
                            : "Sent \(completion.itemCount) items to \(completion.peerName)",
                        systemImage: "arrow.up.circle.fill"
                    )
                }
            }
        }
        .alert(
            trashConfirmationTitle,
            isPresented: isTrashConfirmationPresented
        ) {
            Button("Cancel", role: .cancel) {
                fileOperations.cancelTrashConfirmation()
            }
            Button("Move to Trash", role: .destructive) {
                fileOperations.confirmTrash()
            }
        } message: {
            Text(trashConfirmationMessage)
        }
        .alert("File Operation Failed", isPresented: $fileOperations.isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(fileOperations.errorMessage)
        }
        .alert(
            "Unable to Open Terminal",
            isPresented: $terminalApplications.isErrorPresented
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(terminalApplications.errorMessage)
        }
        .alert("Nearby Transfer Failed", isPresented: $nearbyTransfers.isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(nearbyTransfers.errorMessage)
        }
        .alert(
            "Couldn’t Eject Disk",
            isPresented: isMountedVolumeEjectFailurePresented,
            presenting: sidebar.mountedVolumeMonitor.ejectFailure
        ) { failure in
            Button("Try Again") {
                ejectMountedVolume(failure.volume)
            }
            Button("Cancel", role: .cancel) {}
        } message: { failure in
            Text(
                "“\(failure.volume.title)” could not be ejected.\n\n"
                    + failure.message
            )
        }
        .sheet(item: $fileOperations.renameRequest) { request in
            FileRenameSheet(
                request: request,
                coordinator: fileOperations
            )
            .environment(\.explorerTheme, theme)
        }
        .sheet(item: $nearbyTransfers.presentation) { presentation in
            NearbyTransferSheet(
                presentation: presentation,
                coordinator: nearbyTransfers,
                defaultDestinationURL: workspace.activePane?.displayedDirectory
                    ?? FileManager.default.urls(
                        for: .downloadsDirectory,
                        in: .userDomainMask
                    ).first
                    ?? URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            )
            .environment(\.explorerTheme, theme)
            .interactiveDismissDisabled()
        }
    }

    private func toggleSidebar() {
        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
    }

    private func togglePreview() {
        isPreviewVisible.toggle()
    }

    private func resetWorkspaceView() {
        _ = workspace.resetView()
    }

    private func navigateBack() -> Bool {
        workspace.goBack()
    }

    private func revealGlobalSearchResult(_ result: ExplorerSearchResult) {
        workspace.reveal(result.item)
    }

    private func ejectMountedVolume(_ volume: MountedVolume) {
        Task {
            let didEject = await sidebar.mountedVolumeMonitor.eject(volume)
            if didEject {
                workspace.handleEjectedVolume(at: volume.url)
            }
        }
    }

    private var explorerSidebar: some View {
        List(selection: sidebarSelection) {
            if sidebar.visiblePrimaryPlaces.isEmpty == false
                || sidebar.favorites.isEmpty == false {
                Section {
                    ForEach(sidebar.visiblePrimaryPlaces) { place in
                        sidebarRow(.builtIn(place))
                    }

                    ForEach(sidebar.favorites) { favorite in
                        sidebarRow(.favorite(favorite))
                    }
                } header: {
                    sidebarSectionHeader("Favorites")
                }
            }

            if sidebar.visibleMediaPlaces.isEmpty == false {
                Section {
                    ForEach(sidebar.visibleMediaPlaces) { place in
                        sidebarRow(.builtIn(place))
                    }
                } header: {
                    sidebarSectionHeader("Media")
                }
            }

            if sidebar.visibleLocationPlaces.isEmpty == false
                || sidebar.mountedVolumeMonitor.volumes.isEmpty == false {
                Section {
                    ForEach(sidebar.visibleLocationPlaces) { place in
                        sidebarRow(.builtIn(place))
                    }

                    ForEach(sidebar.mountedVolumeMonitor.volumes) { volume in
                        mountedVolumeSidebarRow(volume)
                    }
                } header: {
                    sidebarSectionHeader("Locations")
                }
            }
        }
        .listStyle(.sidebar)
        .headerProminence(.increased)
        .scrollContentBackground(.hidden)
        .background(themeController.activeTheme.sidebarBackground)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Button {
                    isSidebarFolderPickerPresented = true
                } label: {
                    Label("Add Folder", systemImage: "plus.circle.fill")
                }
                .buttonStyle(ExplorerSidebarActionButtonStyle())
                .help("Add Folder to Sidebar")

                if sidebar.hiddenBuiltInPlaces.isEmpty == false {
                    SidebarRestoreButton(
                        hiddenPlaces: sidebar.hiddenBuiltInPlacesInDefaultOrder,
                        onRestore: sidebar.restoreBuiltInPlace,
                        onRestoreAll: sidebar.restoreAllBuiltInPlaces
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(themeController.activeTheme.sidebarFooter)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(themeController.activeTheme.chromeDivider)
                    .frame(height: 0.75)
            }
        }
        .fileImporter(
            isPresented: $isSidebarFolderPickerPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(directoryURLs) = result,
                  let directoryURL = directoryURLs.first else {
                return
            }

            if let restoredPlace = sidebar.restoreBuiltInPlace(
                for: directoryURL
            ) {
                workspace.select(restoredPlace, in: workspace.activePaneID)
                return
            }

            guard let favorite = sidebar.add(directoryURL: directoryURL) else {
                return
            }

            workspace.select(.favorite(favorite), in: workspace.activePaneID)
        }
    }

    private func mountedVolumeSidebarRow(_ volume: MountedVolume) -> some View {
        let place = volume.sidebarPlace

        return MountedVolumeSidebarRow(
            volume: volume,
            isEjecting: sidebar.mountedVolumeMonitor.isEjecting(volume),
            onOpen: {
                workspace.select(place, in: workspace.activePaneID)
            },
            onEject: {
                ejectMountedVolume(volume)
            }
        )
        .tag(place)
        .internalFolderDropTarget(
            destinationDirectoryURL: volume.url,
            paneID: workspace.activePaneID,
            showsTerminalCommands: true
        )
    }

    @ViewBuilder
    private func sidebarRow(_ place: SidebarPlace) -> some View {
        Label(place.title, systemImage: place.systemImage)
            .font(ExplorerTheme.sidebarNavigationFont)
            .labelStyle(ExplorerSidebarLabelStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .tag(place)
            .accessibilityIdentifier(sidebarIdentifier(for: place))
            .internalFolderDropTarget(
                destinationDirectoryURL: place.isDirectory ? place.url : nil,
                paneID: workspace.activePaneID,
                showsTerminalCommands: place.isDirectory
            )
            .contextMenu {
                if place.canRemoveFromSidebar {
                    Button(
                        "Remove from Sidebar",
                        systemImage: "minus.circle"
                    ) {
                        sidebar.removeFromSidebar(place)
                    }
                }
            }
    }

    private func sidebarIdentifier(for place: SidebarPlace) -> String {
        switch place.id {
        case let .builtIn(builtInPlace):
            "sidebar-built-in-\(builtInPlace.rawValue)"
        case let .favorite(identifier):
            "sidebar-favorite-\(identifier.uuidString)"
        case let .location(url):
            "sidebar-location-\(url.path(percentEncoded: false))"
        }
    }

    private func sidebarSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(.caption, design: .rounded).bold())
            .tracking(0.7)
            .foregroundStyle(themeController.activeTheme.chromeSecondaryText)
            .padding(.top, 4)
    }

    @ViewBuilder
    private var inspectorContent: some View {
        if let pane = workspace.activePane,
           pane.isInspectorPresented,
           let selectedItem = pane.selectedInspectorItem {
            if selectedItem.isDirectory {
                FolderContentsInspector(
                    folder: selectedItem,
                    paneID: pane.id,
                    fileOperations: fileOperations,
                    terminalApplications: terminalApplications,
                    sidebar: sidebar
                )
            } else {
                ImagePreviewInspector(image: selectedItem)
            }
        } else {
            EmptyPreviewInspector()
        }
    }
}

private struct WorkspaceRootView: View {
    @Environment(\.explorerTheme) private var theme

    let workspace: WorkspaceModel
    let sidebar: SidebarModel
    let isPreviewVisible: Bool
    let onTogglePreview: () -> Void
    let onResetView: () -> Void

    var body: some View {
        WorkspaceNodeView(
            node: workspace.layoutRoot,
            workspace: workspace,
            sidebar: sidebar,
            isPreviewVisible: isPreviewVisible,
            onTogglePreview: onTogglePreview,
            onResetView: onResetView
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.canvas)
    }
}

private struct WorkspaceNodeView: View {
    let node: WorkspaceLayoutNode
    let workspace: WorkspaceModel
    let sidebar: SidebarModel
    let isPreviewVisible: Bool
    let onTogglePreview: () -> Void
    let onResetView: () -> Void

    @ViewBuilder
    var body: some View {
        switch node {
        case let .pane(paneID):
            if let pane = workspace.pane(paneID) {
                DestinationView(
                    pane: pane,
                    workspace: workspace,
                    sidebar: sidebar,
                    isPreviewVisible: isPreviewVisible,
                    onTogglePreview: onTogglePreview,
                    onResetView: onResetView
                )
                    .id(paneID)
            }

        case let .split(splitID, axis, first, second):
            WorkspaceSplitContainer(axis: axis) {
                workspaceNode(first)
            } second: {
                workspaceNode(second)
            }
            .id(splitID)
        }
    }

    private func workspaceNode(_ node: WorkspaceLayoutNode) -> WorkspaceNodeView {
        WorkspaceNodeView(
            node: node,
            workspace: workspace,
            sidebar: sidebar,
            isPreviewVisible: isPreviewVisible,
            onTogglePreview: onTogglePreview,
            onResetView: onResetView
        )
    }
}

private nonisolated struct DirectoryLoadRequest: Hashable {
    let directoryURL: URL?
    let operationRevision: Int
    let includesHiddenItems: Bool
    let retryGeneration: Int
}

private nonisolated struct SearchLoadRequest: Hashable {
    let request: ExplorerSearchRequest
    let operationRevision: Int
}

private struct DestinationView: View {
    @Environment(FileOperationCoordinator.self) private var fileOperations
    @Environment(\.explorerTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let pane: WorkspacePaneState
    let workspace: WorkspaceModel
    let sidebar: SidebarModel
    let isPreviewVisible: Bool
    let onTogglePreview: () -> Void
    let onResetView: () -> Void

    @FocusState private var isDirectoryListFocused: Bool
    @State private var directoryRetryGeneration = 0

    private var directoryLoadRequest: DirectoryLoadRequest {
        DirectoryLoadRequest(
            directoryURL: pane.displayedDirectory,
            operationRevision: fileOperations.directoryRefreshRevision(
                for: pane.displayedDirectory
            ),
            includesHiddenItems: pane.showsHiddenItems,
            retryGeneration: directoryRetryGeneration
        )
    }

    private var searchLoadRequest: SearchLoadRequest {
        SearchLoadRequest(
            request: pane.searchModel.request(in: pane.displayedDirectory),
            operationRevision: fileOperations.recursiveRefreshRevision(
                for: pane.displayedDirectory
            )
        )
    }

    private var fileCommandContext: FileCommandContext {
        FileCommandContext(pane: pane, coordinator: fileOperations)
    }

    var body: some View {
        @Bindable var pane = pane
        @Bindable var searchModel = pane.searchModel

        VStack(alignment: .leading, spacing: 10) {
            paneToolbar

            if let displayedDirectory = pane.displayedDirectory {
                if pane.searchModel.isSearchActive {
                    ExplorerSearchControlBar(
                        scope: $searchModel.scope,
                        contentMode: $searchModel.contentMode,
                        isSearching: pane.searchModel.isSearching,
                        resultCount: pane.searchModel.results.count
                    )
                }

                Divider()
                    .overlay(theme.divider)
                ZStack {
                    theme.panel

                    directoryBody
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                    .overlay(alignment: .topTrailing) {
                        fileOperationStatus
                            .padding(10)
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("pane-directory-body")
                    .internalFolderDropTarget(
                        destinationDirectoryURL: displayedDirectory,
                        paneID: pane.id,
                        showsNewFolderCommand: true,
                        onCreateFolder: createFolder
                    )
            } else {
                ContentUnavailableView(
                    "Folder Unavailable",
                    systemImage: "folder.badge.questionmark"
                )
            }
        }
        .padding(12)
        .frame(
            minWidth: 280,
            maxWidth: .infinity,
            minHeight: 220,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(
            theme.panel,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    workspace.paneCount > 1 && workspace.activePaneID == pane.id
                        ? theme.accent.opacity(0.055)
                        : Color.clear
                )
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    workspace.paneCount > 1 && workspace.activePaneID == pane.id
                        ? theme.accent
                        : theme.divider,
                    lineWidth: workspace.paneCount > 1
                        && workspace.activePaneID == pane.id ? 1.5 : 0.75
                )
                .allowsHitTesting(false)
        }
        .padding(6)
        .background(theme.canvas)
        .contentShape(Rectangle())
        .focusedValue(\.explorerPaneID, pane.id)
        .focusedValue(\.fileCommandContext, fileCommandContext)
        .simultaneousGesture(
            TapGesture().onEnded {
                workspace.activate(pane.id)
            }
        )
        .task(id: directoryLoadRequest) {
            let request = directoryLoadRequest
            await loadDirectoryContents(request)
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active,
                  let accessError = pane.directoryAccessError,
                  case .permissionDenied = accessError else {
                return
            }

            directoryRetryGeneration += 1
        }
        .task(id: searchLoadRequest) {
            let request = searchLoadRequest

            if request.operationRevision > 0 {
                await pane.searchModel.filesDidChange(in: request.request.rootURL)
            } else {
                await pane.searchModel.search(in: request.request.rootURL)
            }
        }
        .onChange(of: pane.selectedURLs) {
            if pane.selectedURLs.isEmpty == false {
                workspace.activate(pane.id)
            }
            updatePreviewPresentation()
        }
        .onChange(of: pane.selectedSearchResultIDs) {
            guard pane.searchModel.isSearchActive else { return }

            if pane.selectedSearchResultIDs.isEmpty == false {
                workspace.activate(pane.id)
            }
            pane.selectedURL = pane.searchModel.results
                .first(where: { $0.id == pane.selectedSearchResultID })?
                .item.url
            updatePreviewPresentation()
        }
        .onChange(of: pane.searchModel.request(in: pane.displayedDirectory)) {
            oldRequest,
            newRequest in
            // Folder navigation owns its selection reset. Clearing here as well
            // races a global-search reveal: the directory load selects the hit,
            // then this observer can erase that selection a frame later.
            guard oldRequest.rootURL == newRequest.rootURL else { return }
            pane.selectedSearchResultID = nil
            pane.selectedURL = nil
        }
        .onChange(of: fileOperations.lastCreatedFolderURL) {
            guard let createdFolderURL = fileOperations.lastCreatedFolderURL,
                  workspace.activePaneID == pane.id,
                  let displayedDirectory = pane.displayedDirectory,
                  urlsReferToSameItem(
                      createdFolderURL.deletingLastPathComponent(),
                      displayedDirectory
                  ) else {
                return
            }

            pane.pendingRevealURL = createdFolderURL
            pane.selectedSearchResultID = nil
            pane.selectedURL = createdFolderURL
            pane.isInspectorPresented = false
        }
        .modifier(
            WorkspacePaneAccessibilityModifier(
                pane: pane,
                workspace: workspace
            )
        )
    }

    private var paneToolbar: some View {
        @Bindable var searchModel = pane.searchModel

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                if pane.navigation.canGoBack {
                    Button("Back", systemImage: "chevron.left") {
                        _ = workspace.goBack(in: pane.id)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(
                        ExplorerPanePrimaryButtonStyle(
                            isCompact: true,
                            usesAccentForeground: true
                        )
                    )
                    .explorerTooltip(
                        "Go back",
                        alignment: .topLeading
                    )
                }

                PaneLocationMenu(
                    selectedPlace: pane.place,
                    places: sidebar.allPlaces,
                    isCompact: workspace.paneCount > 1
                ) { place in
                    workspace.select(place, in: pane.id)
                }
                .help("Choose the folder shown in this pane")

                Spacer(minLength: 4)

                if workspace.paneCount == 1 {
                    Button("New Folder", systemImage: "folder.badge.plus") {
                        createFolder()
                    }
                    .buttonStyle(
                        ExplorerPanePrimaryButtonStyle(isCompact: false)
                    )
                    .disabled(
                        pane.displayedDirectory == nil
                            || fileOperations.isPerforming
                    )
                    .help("Create a new folder in this pane")

                } else {
                    Button("New Folder", systemImage: "folder.badge.plus") {
                        createFolder()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(
                        ExplorerPanePrimaryButtonStyle(isCompact: true)
                    )
                    .disabled(
                        pane.displayedDirectory == nil
                            || fileOperations.isPerforming
                    )
                    .explorerTooltip(
                        "Create a new folder",
                        alignment: .topLeading
                    )

                }

                TerminalToolbarButton(directoryURL: pane.displayedDirectory)

                NearbyTransferToolbarButton(sourceURLs: pane.selectedCommandURLs)

                Button(
                    pane.showsHiddenItems ? "Hide Hidden Items" : "Show Hidden Items",
                    systemImage: pane.showsHiddenItems ? "eye.slash" : "eye"
                ) {
                    toggleHiddenItems()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(ExplorerPaneUtilityButtonStyle())
                .explorerTooltip(
                    pane.showsHiddenItems
                        ? "Hide hidden items"
                        : "Show hidden items"
                )

                Button("Split Right", systemImage: "rectangle.split.2x1") {
                    _ = workspace.split(paneID: pane.id, direction: .right)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(ExplorerPaneUtilityButtonStyle())
                .disabled(workspace.canSplit == false)
                .explorerTooltip("Add a pane on the right")

                Button("Split Below", systemImage: "rectangle.split.1x2") {
                    _ = workspace.split(paneID: pane.id, direction: .below)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(ExplorerPaneUtilityButtonStyle())
                .disabled(workspace.canSplit == false)
                .explorerTooltip("Add a pane below")

                if workspace.paneCount > 1 {
                    if workspace.activePaneID == pane.id {
                        Button(
                            "Reset View",
                            systemImage: "rectangle",
                            action: onResetView
                        )
                        .labelStyle(.iconOnly)
                        .buttonStyle(ExplorerPaneUtilityButtonStyle())
                        .explorerTooltip(
                            "Close the other panes",
                            alignment: .topTrailing
                        )
                    }

                    Button("Close Pane", systemImage: "xmark") {
                        _ = workspace.close(pane.id)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(ExplorerPaneUtilityButtonStyle())
                    .explorerTooltip(
                        "Close this pane",
                        alignment: .topTrailing
                    )
                }

                if workspace.paneCount == 1 {
                    Button(
                        isPreviewVisible ? "Hide Preview" : "Show Preview",
                        systemImage: "sidebar.trailing",
                        action: onTogglePreview
                    )
                    .labelStyle(.iconOnly)
                    .buttonStyle(ExplorerPaneUtilityButtonStyle())
                    .explorerTooltip(
                        isPreviewVisible
                            ? "Hide preview"
                            : "Show preview",
                        alignment: .topTrailing
                    )
                }
            }
            .padding(7)
            .background(
                theme.elevatedPanel,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(theme.divider, lineWidth: 0.75)
            }
            .shadow(
                color: theme.imperialPrimer.opacity(0.06),
                radius: 5,
                x: 0,
                y: 2
            )
            .zIndex(1)

            if let displayedDirectory = pane.displayedDirectory {
                PaneCurrentPathView(directoryURL: displayedDirectory)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.textSecondary)

                TextField("Search this folder", text: $searchModel.query)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search in \(pane.place.title)")
                    .accessibilityIdentifier("pane-search-field")

                if searchModel.isSearchActive {
                    Button(
                        "Clear Search",
                        systemImage: "xmark.circle.fill",
                        action: searchModel.clear
                    )
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.textSecondary)
                    .help("Clear this folder search")
                    .accessibilityIdentifier("pane-search-clear-button")
                }
            }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                    theme.control,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(theme.divider, lineWidth: 0.75)
                }
                .help("Search file names or contents in this pane")
        }
    }

    private func createFolder() {
        workspace.activate(pane.id)
        fileOperations.createFolder(
            in: pane.displayedDirectory,
            suggestedName: FileRenameNameValidator.suggestedNewFolderName(
                existingNames: pane.directoryContents.map(\.name)
            )
        )
    }

    private func toggleHiddenItems() {
        workspace.activate(pane.id)
        pane.showsHiddenItems.toggle()
        pane.selectedURL = nil
        pane.selectedSearchResultID = nil
        pane.isInspectorPresented = false
    }

    @ViewBuilder
    private var fileOperationStatus: some View {
        if fileOperations.isPerforming {
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(fileOperations.statusMessage ?? "Working")

                if let statusMessage = fileOperations.statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                theme.elevatedPanel,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(theme.divider, lineWidth: 0.75)
            }
            .shadow(
                color: theme.imperialPrimer.opacity(0.08),
                radius: 4,
                y: 2
            )
            .accessibilityIdentifier("pane-file-operation-status")
        }
    }

    @ViewBuilder
    private var directoryBody: some View {
        @Bindable var pane = pane

        if pane.searchModel.isSearchActive {
            ExplorerSearchResultsView(
                paneID: pane.id,
                sidebar: sidebar,
                query: pane.searchModel.query,
                results: pane.searchModel.results,
                isSearching: pane.searchModel.isSearching,
                errorMessage: pane.searchModel.errorMessage,
                selection: $pane.selectedSearchResultIDs,
                onOpen: openSearchResult,
                onDelete: requestTrashSelection
            )
        } else if pane.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let accessError = pane.directoryAccessError {
            DirectoryAccessUnavailableView(
                error: accessError,
                openPrivacySettings: {
                    SystemPrivacySettingsOpener.openFilesAndFolders()
                }
            )
        } else if let errorMessage = pane.errorMessage {
            ContentUnavailableView(
                "Unable to Access Folder",
                systemImage: "exclamationmark.triangle.fill",
                description: Text(errorMessage)
            )
        } else {
            ZStack {
                List(pane.directoryContents, selection: $pane.selectedURLs) { item in
                    FileRowView(
                        item: item,
                        sidebar: sidebar,
                        onOpen: {
                            open(item)
                        }
                    )
                    .tag(item.url)
                    .background(
                        ExplorerRowBackground(
                            isSelected: pane.selectedURLs.contains(item.url)
                        )
                    )
                    .listRowBackground(theme.row)
                    .internalFileInteraction(
                        for: item,
                        paneID: pane.id,
                        sidebar: sidebar
                    )
                    .accessibilityIdentifier("file-row-\(pane.id)-\(item.name)")
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(theme.panel)
                .listRowSeparatorTint(theme.divider)
                .focused($isDirectoryListFocused)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if NSApp.currentEvent?.type == .leftMouseUp {
                            isDirectoryListFocused = true
                        }
                    }
                )
                .onDeleteCommand(perform: requestTrashSelection)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.18),
                    value: pane.directoryContents.map(\.id)
                )

                if pane.directoryContents.isEmpty {
                    ContentUnavailableView(
                        "Folder Is Empty",
                        systemImage: "folder"
                    )
                    .accessibilityIdentifier("pane-empty-folder-state")
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private func open(_ item: FileItem) {
        workspace.activate(pane.id)

        if item.isDirectory {
            pane.navigation.open(item.url)
            pane.selectedURL = nil
            pane.selectedSearchResultID = nil
            pane.isInspectorPresented = false
        } else {
            _ = NSWorkspace.shared.open(item.url)
        }
    }

    private func updatePreviewPresentation() {
        let shouldPresent = workspace.paneCount == 1
            && pane.selectedInspectorItem != nil
        guard pane.isInspectorPresented != shouldPresent else { return }

        pane.isInspectorPresented = shouldPresent
    }

    private func openSearchResult(_ result: ExplorerSearchResult) {
        workspace.activate(pane.id)

        if result.item.isDirectory {
            pane.searchModel.query = ""
            pane.navigation.open(result.item.url)
            pane.selectedSearchResultID = nil
            pane.selectedURL = nil
            pane.isInspectorPresented = false
        } else {
            _ = NSWorkspace.shared.open(result.item.url)
        }
    }

    private func loadDirectoryContents(_ request: DirectoryLoadRequest) async {
        let requestedURL = request.directoryURL
        guard let requestedURL else {
            pane.directoryContents = []
            pane.loadedDirectoryURL = nil
            pane.directoryAccessError = .invalidURL
            pane.errorMessage = nil
            pane.isLoading = false
            return
        }

        let isInPlaceRefresh = pane.loadedDirectoryURL.map {
            urlsReferToSameItem($0, requestedURL)
        } == true
        if isInPlaceRefresh == false {
            pane.isLoading = true
        }
        pane.directoryAccessError = nil
        pane.errorMessage = nil

        do {
            let contents = try await FileSystemService().contents(
                of: requestedURL,
                folderTitle: pane.place.title,
                includingHiddenItems: pane.showsHiddenItems
            )
            try Task.checkCancellation()
            guard requestedURL == pane.displayedDirectory else { return }

            if isInPlaceRefresh {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                    pane.reconcileSelection(with: contents)
                    pane.directoryContents = contents
                }
            } else {
                pane.reconcileSelection(with: contents)
                pane.directoryContents = contents
            }
            pane.loadedDirectoryURL = requestedURL

            if let pendingRevealURL = pane.pendingRevealURL,
               let revealedItem = contents.first(where: {
                   urlsReferToSameItem($0.url, pendingRevealURL)
               }) {
                pane.pendingRevealURL = nil
                pane.selectedURL = revealedItem.url
            }

            // Publish the loading transition last. The macOS List must enter
            // the hierarchy with its selection and rows already consistent;
            // otherwise its initial empty selection can overwrite the reveal.
            pane.isLoading = false
        } catch is CancellationError {
            guard requestedURL == pane.displayedDirectory else { return }
            pane.isLoading = false
        } catch let error as DirectoryAccessError {
            guard Task.isCancelled == false,
                  requestedURL == pane.displayedDirectory else { return }
            if isInPlaceRefresh {
                fileOperations.presentExternalNotice(
                    message: "Couldn’t refresh folder",
                    systemImage: "exclamationmark.triangle.fill"
                )
                pane.isLoading = false
                return
            }
            pane.directoryContents = []
            pane.loadedDirectoryURL = nil
            pane.directoryAccessError = error
            pane.errorMessage = nil
            pane.isLoading = false
        } catch {
            guard Task.isCancelled == false,
                  requestedURL == pane.displayedDirectory else { return }
            if isInPlaceRefresh {
                fileOperations.presentExternalNotice(
                    message: "Couldn’t refresh folder",
                    systemImage: "exclamationmark.triangle.fill"
                )
                pane.isLoading = false
                return
            }
            pane.directoryContents = []
            pane.loadedDirectoryURL = nil
            pane.directoryAccessError = nil
            pane.errorMessage = "An unexpected error occurred: \(error.localizedDescription)\n\nPath: \(requestedURL.path)"
            pane.isLoading = false
        }
    }

    private func urlsReferToSameItem(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath()
            == rhs.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func requestTrashSelection() {
        let selectedURLs = pane.selectedCommandURLs
        guard selectedURLs.isEmpty == false,
              fileOperations.isPerforming == false else {
            return
        }

        workspace.activate(pane.id)
        fileOperations.requestTrashConfirmation(for: selectedURLs)
    }
}

private struct WorkspacePaneAccessibilityModifier: ViewModifier {
    let pane: WorkspacePaneState
    let workspace: WorkspaceModel

    private var isActive: Bool {
        workspace.activePaneID == pane.id
    }

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("workspace-pane-\(pane.id)")
            .accessibilityLabel("\(pane.place.title) file pane")
            .accessibilityValue(isActive ? "Active pane" : "Inactive pane")
            .accessibilityAddTraits(isActive ? .isSelected : [])
            .accessibilityAction(named: "Activate Pane") {
                workspace.activate(pane.id)
            }
    }
}

struct FolderContentsInspector: View {
    @Environment(\.explorerTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let folder: FileItem
    let paneID: UUID
    let fileOperations: FileOperationCoordinator
    let terminalApplications: TerminalApplicationCoordinator
    let sidebar: SidebarModel

    @State private var directoryContents: [FileItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loadedFolderURL: URL?

    private var directoryLoadRequest: DirectoryLoadRequest {
        DirectoryLoadRequest(
            directoryURL: folder.url,
            operationRevision: fileOperations.directoryRefreshRevision(
                for: folder.url
            ),
            includesHiddenItems: false,
            retryGeneration: 0
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            InspectorHeader(item: folder, systemImage: "folder.fill")

            Divider()
                .overlay(theme.divider)

            inspectorBody
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .internalFolderDropTarget(
                    destinationDirectoryURL: folder.url,
                    paneID: paneID
                )
        }
        .task(id: directoryLoadRequest) {
            let request = directoryLoadRequest
            await loadDirectoryContents(request)
        }
        .environment(fileOperations)
        .environment(terminalApplications)
    }

    @ViewBuilder
    private var inspectorBody: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView(
                "Unable to Preview Folder",
                systemImage: "exclamationmark.triangle.fill",
                description: Text(errorMessage)
            )
        } else {
            ZStack {
                List(directoryContents) { item in
                    HStack(spacing: 2) {
                        FavoriteToggleButton(item: item, sidebar: sidebar)

                        FileRowContent(item: item)
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .listRowBackground(theme.row)
                        .internalFileInteraction(
                            for: item,
                            paneID: paneID,
                            sidebar: sidebar
                        )
                        .accessibilityIdentifier("file-row-\(paneID)-\(item.name)")
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(theme.inspector)
                .listRowSeparatorTint(theme.divider)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.18),
                    value: directoryContents.map(\.id)
                )

                if directoryContents.isEmpty {
                    ContentUnavailableView(
                        "Folder Is Empty",
                        systemImage: "folder"
                    )
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private func loadDirectoryContents(_ request: DirectoryLoadRequest) async {
        let isInPlaceRefresh = loadedFolderURL == folder.url
        if isInPlaceRefresh == false {
            isLoading = true
        }
        errorMessage = nil

        do {
            let contents = try await FileSystemService().contents(
                of: folder.url,
                folderTitle: folder.name
            )
            try Task.checkCancellation()

            if isInPlaceRefresh {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                    directoryContents = contents
                }
            } else {
                directoryContents = contents
            }
            loadedFolderURL = folder.url
            isLoading = false
        } catch is CancellationError {
            return
        } catch let error as DirectoryAccessError {
            guard Task.isCancelled == false else { return }
            if isInPlaceRefresh {
                fileOperations.presentExternalNotice(
                    message: "Couldn’t refresh folder",
                    systemImage: "exclamationmark.triangle.fill"
                )
                isLoading = false
                return
            }
            errorMessage = error.localizedDescription
            isLoading = false
        } catch {
            guard Task.isCancelled == false else { return }
            if isInPlaceRefresh {
                fileOperations.presentExternalNotice(
                    message: "Couldn’t refresh folder",
                    systemImage: "exclamationmark.triangle.fill"
                )
                isLoading = false
                return
            }
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

private struct ImagePreviewInspector: View {
    @Environment(\.explorerTheme) private var theme

    let image: FileItem

    var body: some View {
        VStack(spacing: 0) {
            InspectorHeader(item: image, systemImage: "photo.fill")

            Divider()
                .overlay(theme.divider)

            QuickLookPreview(url: image.url)
                .accessibilityLabel("Preview of \(image.name)")
        }
    }
}

private struct InspectorHeader: View {
    @Environment(\.explorerTheme) private var theme

    let item: FileItem
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(item.name, systemImage: systemImage)
                .font(ExplorerTheme.paneTitleFont)
                .foregroundStyle(theme.textPrimary)

            Text(item.url.path(percentEncoded: false))
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(theme.elevatedPanel)
    }
}

private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> QLPreviewView {
        let previewView = QLPreviewView(frame: .zero, style: .compact)!
        previewView.autostarts = false
        previewView.shouldCloseWithWindow = false
        return previewView
    }

    func updateNSView(_ previewView: QLPreviewView, context: Context) {
        guard context.coordinator.previewedURL != url else { return }

        context.coordinator.previewedURL = url
        previewView.previewItem = url as NSURL
    }

    static func dismantleNSView(_ previewView: QLPreviewView, coordinator: Coordinator) {
        coordinator.previewedURL = nil
        previewView.previewItem = nil
    }

    final class Coordinator {
        var previewedURL: URL?
    }
}

private struct FileRowView: View {
    let item: FileItem
    let sidebar: SidebarModel
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            FavoriteToggleButton(item: item, sidebar: sidebar)

            FileRowContent(item: item)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { onOpen() }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.name)
        .accessibilityHint(
            item.isDirectory
                ? "Double-click to open folder"
                : "Double-click to open file"
        )
        .accessibilityAction(named: "Open", onOpen)
    }
}

private struct FileRowContent: View {
    @Environment(\.explorerTheme) private var theme

    let item: FileItem

    var body: some View {
        HStack(spacing: 10) {
            FileItemIconView(item: item)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(ExplorerTheme.fileNameFont)
                    .foregroundStyle(theme.textPrimary)

                if let modificationDate = item.modificationDate {
                    Text(
                        "Modified: \(modificationDate.formatted(date: .abbreviated, time: .shortened))"
                        )
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(theme.textSecondary)
                }
            }

            Spacer()

            FileSizeLabel(item: item)
                .frame(minWidth: 72, alignment: .trailing)

            TrashItemButton(item: item)
        }
    }

}

private struct TrashItemButton: View {
    @Environment(FileOperationCoordinator.self) private var fileOperations
    @Environment(\.explorerTheme) private var theme

    let item: FileItem

    var body: some View {
        Button {
            fileOperations.requestTrashConfirmation(for: [item.url])
        } label: {
            Image(systemName: "trash")
                .symbolRenderingMode(.hierarchical)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.textSecondary)
        .disabled(fileOperations.isPerforming)
        .help("Move \(item.name) to Trash")
        .accessibilityLabel("Move \(item.name) to Trash")
        .accessibilityIdentifier("trash-item-\(item.name)")
    }
}

struct FileSizeLabel: View {
    @Environment(FileOperationCoordinator.self) private var fileOperations
    @Environment(\.explorerTheme) private var theme

    let item: FileItem

    @State private var folderSize: Int64?
    @State private var isCalculatingFolderSize = false

    private var displayedSize: Int64? {
        item.isDirectory ? folderSize : item.fileSize
    }

    private var folderSizeLoadRequest: FolderSizeLoadRequest {
        FolderSizeLoadRequest(
            directoryURL: item.url,
            operationRevision: fileOperations.recursiveRefreshRevision(for: item.url)
        )
    }

    var body: some View {
        Group {
            if let displayedSize {
                Text(ByteCountFormatter.string(fromByteCount: displayedSize, countStyle: .file))
                    .monospacedDigit()
            } else if isCalculatingFolderSize {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Calculating folder size")
            } else {
                Text("—")
            }
        }
        .font(.system(.caption, design: .rounded))
        .foregroundStyle(theme.textSecondary)
        .task(id: folderSizeLoadRequest) {
            folderSize = nil
            isCalculatingFolderSize = item.isDirectory

            guard item.isDirectory else { return }

            do {
                let size = try await FolderSizeCache.shared.size(of: item.url)
                try Task.checkCancellation()

                folderSize = size
                isCalculatingFolderSize = false
            } catch is CancellationError {
                return
            } catch {
                guard Task.isCancelled == false else { return }
                isCalculatingFolderSize = false
            }
        }
    }
}

private nonisolated struct FolderSizeLoadRequest: Hashable {
    let directoryURL: URL
    let operationRevision: Int
}

#Preview {
    ContentView()
}
