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

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @FocusedValue(\.explorerPaneID) private var focusedPaneID

    @State private var workspace = WorkspaceModel()
    @State private var fileOperations = FileOperationCoordinator()
    @State private var terminalApplications = TerminalApplicationCoordinator()

    init() {}

    init(
        workspace: WorkspaceModel,
        fileOperations: FileOperationCoordinator,
        terminalApplications: TerminalApplicationCoordinator
    ) {
        _workspace = State(initialValue: workspace)
        _fileOperations = State(initialValue: fileOperations)
        _terminalApplications = State(initialValue: terminalApplications)
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
            List(SidebarPlace.allCases, selection: sidebarSelection) { place in
                Label(place.title, systemImage: place.systemImage)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .tag(place)
                    .internalFolderDropTarget(
                        destinationDirectoryURL: place.url,
                        paneID: workspace.activePaneID,
                        showsTerminalCommands: true
                    )
            }
            .listStyle(.sidebar)
        } detail: {
            HStack(spacing: 0) {
                WorkspaceRootView(workspace: workspace)

                if workspace.paneCount == 1 {
                    Divider()

                    inspectorContent
                        .frame(width: 340)
                        .frame(maxHeight: .infinity)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .accessibilityLabel("Preview")
                }
            }
            .transaction { transaction in
                transaction.animation = nil
            }
        }
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

    var body: some View {
        WorkspaceNodeView(node: workspace.layoutRoot, workspace: workspace)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WorkspaceNodeView: View {
    let node: WorkspaceLayoutNode
    let workspace: WorkspaceModel

    @ViewBuilder
    var body: some View {
        switch node {
        case let .pane(paneID):
            if let pane = workspace.pane(paneID) {
                DestinationView(pane: pane, workspace: workspace)
                    .id(paneID)
            }

        case let .split(splitID, axis, first, second):
            switch axis {
            case .sideBySide:
                HSplitView {
                    WorkspaceNodeView(node: first, workspace: workspace)
                    WorkspaceNodeView(node: second, workspace: workspace)
                }
                .id(splitID)

            case .stacked:
                VSplitView {
                    WorkspaceNodeView(node: first, workspace: workspace)
                    WorkspaceNodeView(node: second, workspace: workspace)
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

private struct DestinationView: View {
    @Environment(FileOperationCoordinator.self) private var fileOperations

    let pane: WorkspacePaneState
    let workspace: WorkspaceModel

    private var directoryLoadRequest: DirectoryLoadRequest {
        DirectoryLoadRequest(
            directoryURL: pane.displayedDirectory,
            operationRevision: fileOperations.completedOperationCount
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

        VStack(alignment: .leading, spacing: 8) {
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
                directoryBody
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
        .padding(10)
        .frame(
            minWidth: 280,
            maxWidth: .infinity,
            minHeight: 220,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(
            workspace.activePaneID == pane.id
                ? Color.accentColor.opacity(0.035)
                : Color.clear
        )
        .overlay {
            Rectangle()
                .stroke(
                    workspace.activePaneID == pane.id ? Color.accentColor : .clear,
                    lineWidth: 2
                )
                .allowsHitTesting(false)
        }
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

            if request.operationRevision > 0 {
                await pane.searchModel.filesDidChange(in: request.directoryURL)
            }
        }
        .task(id: pane.searchModel.request(in: pane.displayedDirectory)) {
            await pane.searchModel.search(in: pane.displayedDirectory)
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
        .onChange(of: fileOperations.completedOperationCount) {
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
    }

    private var paneToolbar: some View {
        @Bindable var searchModel = pane.searchModel

        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(SidebarPlace.allCases) { place in
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
                        .font(.headline)
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
                .buttonStyle(.borderless)
                .disabled(
                    pane.displayedDirectory == nil || fileOperations.isPerforming
                )
                .help("Create a new folder in this pane")

                Button("Split Right", systemImage: "rectangle.split.2x1") {
                    _ = workspace.split(paneID: pane.id, direction: .right)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(workspace.canSplit == false)
                .help("Split this pane to the right")

                Button("Split Below", systemImage: "rectangle.split.1x2") {
                    _ = workspace.split(paneID: pane.id, direction: .below)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(workspace.canSplit == false)
                .help("Split this pane below")

                if workspace.paneCount > 1 {
                    Button("Close Pane", systemImage: "xmark") {
                        _ = workspace.close(pane.id)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Close this pane")
                }
            }

            TextField("Search this folder", text: $searchModel.query)
                .textFieldStyle(.roundedBorder)
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
                .help("Go to the previous folder")
            }

            Text(url.path(percentEncoded: false))
                .font(.caption)
                .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
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
                    onOpen: {
                        open(item)
                    }
                )
                .tag(item.url)
                .internalFileInteraction(for: item, paneID: pane.id)
            }
            .listStyle(.plain)
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
                operationRevision: fileOperations.completedOperationCount
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
                    .internalFileInteraction(for: item, paneID: paneID)
            }
            .listStyle(.plain)
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
                .font(.headline)

            Text(item.url.path(percentEncoded: false))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
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
    let onOpen: () -> Void

    var body: some View {
        FileRowContent(item: item)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
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
                .foregroundStyle(item.isDirectory ? .blue : .gray)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)

                if let modificationDate = item.modificationDate {
                    Text(modificationDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            FileSizeLabel(item: item)
                .frame(minWidth: 72, alignment: .trailing)
        }
    }
}

struct FileSizeLabel: View {
    let item: FileItem

    @State private var folderSize: Int64?
    @State private var isCalculatingFolderSize = false

    private var displayedSize: Int64? {
        item.isDirectory ? folderSize : item.fileSize
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
        .foregroundStyle(.secondary)
        .task(id: item.url) {
            folderSize = nil
            isCalculatingFolderSize = item.isDirectory

            guard item.isDirectory else { return }

            do {
                let size = try await FileSystemService().size(of: item.url)
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

#Preview {
    ContentView()
}
