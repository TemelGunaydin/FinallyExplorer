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
    @State private var sidebar = SidebarModel()
    @State private var isSidebarFolderPickerPresented = false

    init() {}

    init(
        workspace: WorkspaceModel,
        fileOperations: FileOperationCoordinator,
        terminalApplications: TerminalApplicationCoordinator,
        sidebar: SidebarModel? = nil
    ) {
        _workspace = State(initialValue: workspace)
        _fileOperations = State(initialValue: fileOperations)
        _terminalApplications = State(initialValue: terminalApplications)

        if let sidebar {
            _sidebar = State(initialValue: sidebar)
        }
    }

    private var sidebarSelection: Binding<SidebarPlace?> {
        Binding(
            get: { workspace.activePane?.place },
            set: { newPlace in
                guard let newPlace else { return }
                workspace.select(newPlace, in: workspace.activePaneID)
            }
        )
    }

    private var fileCommandContext: FileCommandContext? {
        guard let pane = workspace.activePane else { return nil }

        return FileCommandContext(
            selectedURLs: pane.selectedCommandURLs,
            destinationDirectoryURL: pane.displayedDirectory,
            coordinator: fileOperations
        )
    }

    var body: some View {
        @Bindable var fileOperations = fileOperations
        @Bindable var terminalApplications = terminalApplications

        NavigationSplitView {
            explorerSidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 224)
        } detail: {
            HStack(spacing: 0) {
                WorkspaceRootView(workspace: workspace, sidebar: sidebar)

                if workspace.paneCount == 1 {
                    Divider()
                        .overlay(ExplorerTheme.divider)

                    inspectorContent
                        .frame(width: 340)
                        .frame(maxHeight: .infinity)
                        .background(ExplorerTheme.inspector)
                        .accessibilityLabel("Preview")
                }
            }
            .background(ExplorerTheme.canvas)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .tint(ExplorerTheme.accent)
        .foregroundStyle(ExplorerTheme.textPrimary)
        .background(ExplorerTheme.canvas)
        .environment(fileOperations)
        .environment(terminalApplications)
        .focusedSceneValue(\.fileCommandContext, fileCommandContext)
        .onChange(of: scenePhase, initial: true) {
            guard scenePhase == .active else { return }
            terminalApplications.refresh()
        }
        .onChange(of: focusedPaneID) {
            guard let focusedPaneID else { return }
            workspace.activate(focusedPaneID)
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
    }

    private var explorerSidebar: some View {
        List(selection: sidebarSelection) {
            Section("Favorites") {
                ForEach(SidebarBuiltInPlace.primaryPlaces) { place in
                    sidebarRow(.builtIn(place))
                }

                ForEach(sidebar.favorites) { favorite in
                    sidebarRow(.favorite(favorite))
                }
            }

            Section("Media") {
                ForEach(SidebarBuiltInPlace.mediaPlaces) { place in
                    sidebarRow(.builtIn(place))
                }
            }

            Section("Locations") {
                ForEach(SidebarBuiltInPlace.locationPlaces) { place in
                    sidebarRow(.builtIn(place))
                }
            }
        }
        .listStyle(.sidebar)
        .headerProminence(.increased)
        .scrollContentBackground(.hidden)
        .background(ExplorerTheme.sidebarBackground)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    isSidebarFolderPickerPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(ExplorerToolbarButtonStyle())
                .help("Add Folder to Sidebar")

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(ExplorerTheme.elevatedPanel.opacity(0.82))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(ExplorerTheme.divider)
                    .frame(height: 0.75)
            }
        }
        .fileImporter(
            isPresented: $isSidebarFolderPickerPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(directoryURLs) = result,
                  let directoryURL = directoryURLs.first,
                  let favorite = sidebar.add(directoryURL: directoryURL) else {
                return
            }

            workspace.select(.favorite(favorite), in: workspace.activePaneID)
        }
    }

    @ViewBuilder
    private func sidebarRow(_ place: SidebarPlace) -> some View {
        Label(place.title, systemImage: place.systemImage)
            .font(ExplorerTheme.navigationFont)
            .labelStyle(ExplorerSidebarLabelStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .tag(place)
            .internalFolderDropTarget(
                destinationDirectoryURL: place.url,
                paneID: workspace.activePaneID,
                showsTerminalCommands: true
            )
            .contextMenu {
                if let favorite = place.favorite {
                    Button("Remove from Sidebar", role: .destructive) {
                        sidebar.remove(favorite)
                    }
                }
            }
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
                    terminalApplications: terminalApplications
                )
            } else {
                ImagePreviewInspector(image: selectedItem)
            }
        } else {
            ContentUnavailableView(
                "Nothing to Preview",
                systemImage: "eye.slash"
            )
        }
    }
}

private struct WorkspaceRootView: View {
    let workspace: WorkspaceModel
    let sidebar: SidebarModel

    var body: some View {
        WorkspaceNodeView(
            node: workspace.layoutRoot,
            workspace: workspace,
            sidebar: sidebar
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ExplorerTheme.canvas)
    }
}

private struct WorkspaceNodeView: View {
    let node: WorkspaceLayoutNode
    let workspace: WorkspaceModel
    let sidebar: SidebarModel

    @ViewBuilder
    var body: some View {
        switch node {
        case let .pane(paneID):
            if let pane = workspace.pane(paneID) {
                DestinationView(pane: pane, workspace: workspace, sidebar: sidebar)
                    .id(paneID)
            }

        case let .split(splitID, axis, first, second):
            switch axis {
            case .sideBySide:
                HSplitView {
                    WorkspaceNodeView(node: first, workspace: workspace, sidebar: sidebar)
                    WorkspaceNodeView(node: second, workspace: workspace, sidebar: sidebar)
                }
                .id(splitID)

            case .stacked:
                VSplitView {
                    WorkspaceNodeView(node: first, workspace: workspace, sidebar: sidebar)
                    WorkspaceNodeView(node: second, workspace: workspace, sidebar: sidebar)
                }
                .id(splitID)
            }
        }
    }
}

private nonisolated struct DirectoryLoadRequest: Hashable {
    let directoryURL: URL?
    let operationRevision: Int
}

private nonisolated struct SearchLoadRequest: Hashable {
    let request: ExplorerSearchRequest
    let operationRevision: Int
}

private struct DestinationView: View {
    @Environment(FileOperationCoordinator.self) private var fileOperations

    let pane: WorkspacePaneState
    let workspace: WorkspaceModel
    let sidebar: SidebarModel

    @State private var assistantModel = ExplorerAssistantModel()
    @State private var isAssistantPresented = false

    private var directoryLoadRequest: DirectoryLoadRequest {
        DirectoryLoadRequest(
            directoryURL: pane.displayedDirectory,
            operationRevision: fileOperations.directoryRefreshRevision(
                for: pane.displayedDirectory
            )
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
        FileCommandContext(
            selectedURLs: pane.selectedCommandURLs,
            destinationDirectoryURL: pane.displayedDirectory,
            coordinator: fileOperations
        )
    }

    var body: some View {
        @Bindable var pane = pane
        @Bindable var searchModel = pane.searchModel

        VStack(alignment: .leading, spacing: 10) {
            paneToolbar

            if let displayedDirectory = pane.displayedDirectory {
                directoryPathHeader(displayedDirectory)

                if pane.searchModel.isSearchActive {
                    ExplorerSearchControlBar(
                        scope: $searchModel.scope,
                        contentMode: $searchModel.contentMode,
                        isSearching: pane.searchModel.isSearching,
                        resultCount: pane.searchModel.results.count
                    )
                }

                Divider()
                    .overlay(ExplorerTheme.divider)
                ZStack(alignment: .topLeading) {
                    ExplorerTheme.panel
                    directoryBody
                }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                    .internalFolderDropTarget(
                        destinationDirectoryURL: displayedDirectory,
                        paneID: pane.id,
                        showsNewFolderCommand: true
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
            ExplorerTheme.panel,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    workspace.activePaneID == pane.id
                        ? ExplorerTheme.accent.opacity(0.055)
                        : Color.clear
                )
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    workspace.activePaneID == pane.id
                        ? ExplorerTheme.accent
                        : ExplorerTheme.divider,
                    lineWidth: workspace.activePaneID == pane.id ? 2 : 0.75
                )
                .allowsHitTesting(false)
        }
        .padding(6)
        .background(ExplorerTheme.canvas)
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
            await loadDirectoryContents(from: request.directoryURL)
        }
        .task(id: searchLoadRequest) {
            let request = searchLoadRequest

            if request.operationRevision > 0 {
                await pane.searchModel.filesDidChange(in: request.request.rootURL)
            } else {
                await pane.searchModel.search(in: request.request.rootURL)
            }
        }
        .onChange(of: pane.selectedURL) {
            if pane.selectedURL != nil {
                workspace.activate(pane.id)
            }
            updatePreviewPresentation()
        }
        .onChange(of: pane.selectedSearchResultID) {
            guard pane.searchModel.isSearchActive else { return }

            if pane.selectedSearchResultID != nil {
                workspace.activate(pane.id)
            }
            pane.selectedURL = pane.searchModel.results
                .first(where: { $0.id == pane.selectedSearchResultID })?
                .item.url
            updatePreviewPresentation()
        }
        .onChange(of: pane.searchModel.request(in: pane.displayedDirectory)) {
            pane.selectedSearchResultID = nil
            pane.selectedURL = nil
        }
        .onChange(of: pane.displayedDirectory) {
            assistantModel.reset()
        }
        .onChange(of: directoryLoadRequest.operationRevision) {
            guard directoryLoadRequest.operationRevision > 0 else { return }
            pane.selectedSearchResultID = nil
            pane.selectedURL = nil
            pane.isInspectorPresented = false
        }
        .modifier(
            WorkspacePaneAccessibilityModifier(
                pane: pane,
                workspace: workspace
            )
        )
        .sheet(isPresented: $isAssistantPresented) {
            if let displayedDirectory = pane.displayedDirectory {
                ExplorerAssistantSheet(
                    folderURL: displayedDirectory,
                    items: pane.directoryContents,
                    model: assistantModel
                )
            }
        }
    }

    private var paneToolbar: some View {
        @Bindable var searchModel = pane.searchModel

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(sidebar.allPlaces) { place in
                        Button {
                            workspace.select(place, in: pane.id)
                        } label: {
                            if pane.place == place {
                                Label(place.title, systemImage: "checkmark")
                            } else {
                                Text(place.title)
                            }
                        }
                    }
                } label: {
                    Label(pane.place.title, systemImage: pane.place.systemImage)
                        .font(ExplorerTheme.paneTitleFont)
                        .foregroundStyle(ExplorerTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(
                            ExplorerTheme.accentSoft,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Choose the folder shown in this pane")

                Spacer(minLength: 4)

                Button("New Folder", systemImage: "folder.badge.plus") {
                    workspace.activate(pane.id)
                    fileOperations.createFolder(in: pane.displayedDirectory)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(ExplorerToolbarButtonStyle())
                .disabled(
                    pane.displayedDirectory == nil || fileOperations.isPerforming
                )
                .help("Create a new folder in this pane")

                Button("Ask Explorer", systemImage: "sparkles") {
                    workspace.activate(pane.id)
                    isAssistantPresented = true
                }
                .labelStyle(.iconOnly)
                .buttonStyle(ExplorerToolbarButtonStyle())
                .disabled(pane.displayedDirectory == nil)
                .help("Ask on-device AI about this folder")

                Button("Split Right", systemImage: "rectangle.split.2x1") {
                    _ = workspace.split(paneID: pane.id, direction: .right)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(ExplorerToolbarButtonStyle())
                .disabled(workspace.canSplit == false)
                .help("Split this pane to the right")

                Button("Split Below", systemImage: "rectangle.split.1x2") {
                    _ = workspace.split(paneID: pane.id, direction: .below)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(ExplorerToolbarButtonStyle())
                .disabled(workspace.canSplit == false)
                .help("Split this pane below")

                if workspace.paneCount > 1 {
                    Button("Close Pane", systemImage: "xmark") {
                        _ = workspace.close(pane.id)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(ExplorerToolbarButtonStyle())
                    .help("Close this pane")
                }
            }
            .padding(6)
            .background(
                ExplorerTheme.elevatedPanel,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(ExplorerTheme.divider, lineWidth: 0.75)
            }

            TextField("Search this folder", text: $searchModel.query)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    ExplorerTheme.control,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(ExplorerTheme.divider, lineWidth: 0.75)
                }
                .accessibilityLabel("Search in \(pane.place.title)")
                .help("Search file names or contents in this pane")
        }
    }

    private func directoryPathHeader(_ url: URL) -> some View {
        HStack {
            if pane.navigation.canGoBack {
                Button("Back", systemImage: "chevron.left") {
                    workspace.activate(pane.id)
                    pane.navigation.goBack()
                    pane.selectedURL = nil
                }
                .buttonStyle(.borderless)
                .foregroundStyle(ExplorerTheme.accent)
                .help("Go to the previous folder")
            }

            Text(url.path(percentEncoded: false))
                .font(.caption)
                .foregroundStyle(ExplorerTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer()

            if fileOperations.isPerforming {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(fileOperations.statusMessage ?? "Working")

                if let statusMessage = fileOperations.statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(ExplorerTheme.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var directoryBody: some View {
        @Bindable var pane = pane

        if pane.searchModel.isSearchActive {
            ExplorerSearchResultsView(
                paneID: pane.id,
                query: pane.searchModel.query,
                results: pane.searchModel.results,
                isSearching: pane.searchModel.isSearching,
                errorMessage: pane.searchModel.errorMessage,
                selection: $pane.selectedSearchResultID,
                onSelect: selectSearchResult,
                onOpen: openSearchResult
            )
        } else if pane.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = pane.errorMessage {
            ContentUnavailableView(
                "Unable to Access Folder",
                systemImage: "exclamationmark.triangle.fill",
                description: Text(errorMessage)
            )
        } else if pane.directoryContents.isEmpty {
            ContentUnavailableView(
                "Folder Is Empty",
                systemImage: "folder"
            )
        } else {
            List(pane.directoryContents, selection: $pane.selectedURL) { item in
                FileRowView(
                    item: item,
                    onSelect: {
                        select(item)
                    },
                    onOpen: {
                        open(item)
                    }
                )
                .tag(item.url)
                .listRowBackground(ExplorerTheme.row)
                .internalFileInteraction(for: item, paneID: pane.id)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(ExplorerTheme.panel)
            .listRowSeparatorTint(ExplorerTheme.divider)
        }
    }

    private func select(_ item: FileItem) {
        workspace.activate(pane.id)

        if pane.selectedURL != item.url {
            pane.selectedURL = item.url
        } else {
            updatePreviewPresentation()
        }
    }

    private func open(_ item: FileItem) {
        workspace.activate(pane.id)

        if item.isDirectory {
            pane.navigation.open(item.url)
            pane.selectedURL = nil
            pane.isInspectorPresented = false
        } else {
            _ = NSWorkspace.shared.open(item.url)
        }
    }

    private func selectSearchResult(_ result: ExplorerSearchResult) {
        workspace.activate(pane.id)
        pane.selectedSearchResultID = result.id
        pane.selectedURL = result.item.url
        updatePreviewPresentation()
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

    private func loadDirectoryContents(from requestedURL: URL?) async {
        guard let requestedURL else {
            pane.directoryContents = []
            pane.errorMessage = DirectoryAccessError.invalidURL.localizedDescription
            pane.isLoading = false
            return
        }

        pane.isLoading = true
        pane.errorMessage = nil

        do {
            let contents = try await FileSystemService().contents(
                of: requestedURL,
                folderTitle: pane.place.title
            )
            try Task.checkCancellation()
            guard requestedURL == pane.displayedDirectory else { return }

            pane.directoryContents = contents
            pane.isLoading = false
        } catch is CancellationError {
            guard requestedURL == pane.displayedDirectory else { return }
            pane.isLoading = false
        } catch let error as DirectoryAccessError {
            guard Task.isCancelled == false,
                  requestedURL == pane.displayedDirectory else { return }
            pane.directoryContents = []
            pane.errorMessage = error.localizedDescription
            pane.isLoading = false
        } catch {
            guard Task.isCancelled == false,
                  requestedURL == pane.displayedDirectory else { return }
            pane.directoryContents = []
            pane.errorMessage = "An unexpected error occurred: \(error.localizedDescription)\n\nPath: \(requestedURL.path)"
            pane.isLoading = false
        }
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
            .accessibilityLabel("\(pane.place.title) file pane")
            .accessibilityValue(isActive ? "Active pane" : "Inactive pane")
            .accessibilityAddTraits(isActive ? .isSelected : [])
            .accessibilityAction(named: "Activate Pane") {
                workspace.activate(pane.id)
            }
    }
}

struct FolderContentsInspector: View {
    let folder: FileItem
    let paneID: UUID
    let fileOperations: FileOperationCoordinator
    let terminalApplications: TerminalApplicationCoordinator

    @State private var directoryContents: [FileItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            InspectorHeader(item: folder, systemImage: "folder.fill")

            Divider()
                .overlay(ExplorerTheme.divider)

            inspectorBody
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .internalFolderDropTarget(
                    destinationDirectoryURL: folder.url,
                    paneID: paneID
                )
        }
        .task(
            id: DirectoryLoadRequest(
                directoryURL: folder.url,
                operationRevision: fileOperations.directoryRefreshRevision(
                    for: folder.url
                )
            )
        ) {
            await loadDirectoryContents()
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
        } else if directoryContents.isEmpty {
            ContentUnavailableView(
                "Folder Is Empty",
                systemImage: "folder"
            )
        } else {
            List(directoryContents) { item in
                FileRowContent(item: item)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .listRowBackground(ExplorerTheme.row)
                    .internalFileInteraction(for: item, paneID: paneID)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(ExplorerTheme.inspector)
            .listRowSeparatorTint(ExplorerTheme.divider)
        }
    }

    private func loadDirectoryContents() async {
        isLoading = true
        errorMessage = nil
        directoryContents = []

        do {
            let contents = try await FileSystemService().contents(
                of: folder.url,
                folderTitle: folder.name
            )
            try Task.checkCancellation()

            directoryContents = contents
            isLoading = false
        } catch is CancellationError {
            return
        } catch let error as DirectoryAccessError {
            guard Task.isCancelled == false else { return }
            errorMessage = error.localizedDescription
            isLoading = false
        } catch {
            guard Task.isCancelled == false else { return }
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

private struct ImagePreviewInspector: View {
    let image: FileItem

    var body: some View {
        VStack(spacing: 0) {
            InspectorHeader(item: image, systemImage: "photo.fill")

            Divider()
                .overlay(ExplorerTheme.divider)

            QuickLookPreview(url: image.url)
                .accessibilityLabel("Preview of \(image.name)")
        }
    }
}

private struct InspectorHeader: View {
    let item: FileItem
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(item.name, systemImage: systemImage)
                .font(ExplorerTheme.paneTitleFont)
                .foregroundStyle(ExplorerTheme.textPrimary)

            Text(item.url.path(percentEncoded: false))
                .font(.caption)
                .foregroundStyle(ExplorerTheme.textSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(ExplorerTheme.elevatedPanel)
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
    let onSelect: () -> Void
    let onOpen: () -> Void

    var body: some View {
        FileRowContent(item: item)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture(count: 1)
                    .onEnded { onSelect() }
            )
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded { onOpen() }
            )
            .accessibilityElement(children: .combine)
            .accessibilityHint(item.isDirectory ? "Double-click to open folder" : "Double-click to open file")
            .accessibilityAction(named: "Open", onOpen)
    }
}

private struct FileRowContent: View {
    let item: FileItem

    var body: some View {
        HStack(spacing: 10) {
            Image(
                systemName: item.isDirectory
                    ? "folder.fill"
                    : (item.isImage ? "photo.fill" : "doc.fill")
            )
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .foregroundStyle(ExplorerTheme.textPrimary)

                if let modificationDate = item.modificationDate {
                    Text(
                        "Modified: \(modificationDate.formatted(date: .abbreviated, time: .shortened))"
                        )
                        .font(.caption)
                        .foregroundStyle(ExplorerTheme.textSecondary)
                }
            }

            Spacer()

            FileSizeLabel(item: item)
                .frame(minWidth: 72, alignment: .trailing)
        }
    }

    private var iconColor: Color {
        if item.isDirectory {
            ExplorerTheme.folderIcon
        } else if item.isImage {
            ExplorerTheme.imageIcon
        } else {
            ExplorerTheme.documentIcon
        }
    }
}

struct FileSizeLabel: View {
    @Environment(FileOperationCoordinator.self) private var fileOperations

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
        .font(.caption)
        .foregroundStyle(ExplorerTheme.textSecondary)
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
