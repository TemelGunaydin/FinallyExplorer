//
//  WorkspaceModel.swift
//  FinallyExplorer
//

import Foundation
import Observation

nonisolated enum WorkspaceSplitDirection: Hashable, Sendable {
    case right
    case below

    var axis: WorkspaceSplitAxis {
        switch self {
        case .right:
            .sideBySide
        case .below:
            .stacked
        }
    }
}

nonisolated enum WorkspaceSplitAxis: Hashable, Sendable {
    case sideBySide
    case stacked
}

nonisolated indirect enum WorkspaceLayoutNode: Identifiable, Equatable, Sendable {
    case pane(id: UUID)
    case split(
        id: UUID,
        axis: WorkspaceSplitAxis,
        first: WorkspaceLayoutNode,
        second: WorkspaceLayoutNode
    )

    var id: UUID {
        switch self {
        case let .pane(id):
            id
        case let .split(id, _, _, _):
            id
        }
    }

    var paneIDs: [UUID] {
        switch self {
        case let .pane(id):
            [id]
        case let .split(_, _, first, second):
            first.paneIDs + second.paneIDs
        }
    }

    var nodeIDs: Set<UUID> {
        switch self {
        case let .pane(id):
            [id]
        case let .split(id, _, first, second):
            first.nodeIDs.union(second.nodeIDs).union([id])
        }
    }

    func contains(paneID: UUID) -> Bool {
        switch self {
        case let .pane(id):
            id == paneID
        case let .split(_, _, first, second):
            first.contains(paneID: paneID) || second.contains(paneID: paneID)
        }
    }

    fileprivate func replacingPane(
        id targetID: UUID,
        with replacement: WorkspaceLayoutNode
    ) -> (node: WorkspaceLayoutNode, didReplace: Bool) {
        switch self {
        case let .pane(id):
            guard id == targetID else { return (self, false) }
            return (replacement, true)

        case let .split(id, axis, first, second):
            let firstResult = first.replacingPane(id: targetID, with: replacement)
            if firstResult.didReplace {
                return (
                    .split(
                        id: id,
                        axis: axis,
                        first: firstResult.node,
                        second: second
                    ),
                    true
                )
            }

            let secondResult = second.replacingPane(id: targetID, with: replacement)
            guard secondResult.didReplace else { return (self, false) }
            return (
                .split(
                    id: id,
                    axis: axis,
                    first: first,
                    second: secondResult.node
                ),
                true
            )
        }
    }

    fileprivate func removingPane(id targetID: UUID) -> (
        node: WorkspaceLayoutNode?,
        didRemove: Bool,
        preferredPaneID: UUID?
    ) {
        switch self {
        case let .pane(id):
            guard id == targetID else { return (self, false, nil) }
            return (nil, true, nil)

        case let .split(id, axis, first, second):
            let firstResult = first.removingPane(id: targetID)
            if firstResult.didRemove {
                guard let remainingFirst = firstResult.node else {
                    return (second, true, second.paneIDs.first)
                }

                return (
                    .split(
                        id: id,
                        axis: axis,
                        first: remainingFirst,
                        second: second
                    ),
                    true,
                    firstResult.preferredPaneID
                )
            }

            let secondResult = second.removingPane(id: targetID)
            guard secondResult.didRemove else { return (self, false, nil) }
            guard let remainingSecond = secondResult.node else {
                return (first, true, first.paneIDs.last)
            }

            return (
                .split(
                    id: id,
                    axis: axis,
                    first: first,
                    second: remainingSecond
                ),
                true,
                secondResult.preferredPaneID
            )
        }
    }
}

nonisolated struct WorkspaceLayout: Equatable, Sendable {
    static let maximumPaneCount = 4

    private(set) var root: WorkspaceLayoutNode
    private(set) var activePaneID: UUID

    init(initialPaneID: UUID) {
        root = .pane(id: initialPaneID)
        activePaneID = initialPaneID
    }

    fileprivate init(root: WorkspaceLayoutNode, activePaneID: UUID) {
        precondition(root.contains(paneID: activePaneID))
        self.root = root
        self.activePaneID = activePaneID
    }

    var paneIDs: [UUID] { root.paneIDs }
    var paneCount: Int { paneIDs.count }
    var canSplit: Bool { paneCount < Self.maximumPaneCount }

    @discardableResult
    mutating func activate(_ paneID: UUID) -> Bool {
        guard root.contains(paneID: paneID) else { return false }
        activePaneID = paneID
        return true
    }

    @discardableResult
    mutating func split(
        paneID: UUID? = nil,
        direction: WorkspaceSplitDirection,
        newPaneID: UUID,
        splitID: UUID
    ) -> Bool {
        guard canSplit else { return false }

        let targetPaneID = paneID ?? activePaneID
        guard root.contains(paneID: targetPaneID),
              root.nodeIDs.contains(newPaneID) == false,
              root.nodeIDs.contains(splitID) == false,
              newPaneID != splitID else {
            return false
        }

        let replacement = WorkspaceLayoutNode.split(
            id: splitID,
            axis: direction.axis,
            first: .pane(id: targetPaneID),
            second: .pane(id: newPaneID)
        )
        let result = root.replacingPane(id: targetPaneID, with: replacement)
        guard result.didReplace else { return false }

        root = result.node
        activePaneID = newPaneID
        return true
    }

    @discardableResult
    mutating func close(_ paneID: UUID) -> Bool {
        guard paneCount > 1, root.contains(paneID: paneID) else { return false }

        let result = root.removingPane(id: paneID)
        guard result.didRemove, let newRoot = result.node else { return false }

        root = newRoot
        if root.contains(paneID: activePaneID) == false {
            activePaneID = result.preferredPaneID ?? root.paneIDs[0]
        }
        return true
    }
}

@MainActor
@Observable
final class WorkspacePaneState: Identifiable {
    let id: UUID

    var place: SidebarPlace
    var directoryContents: [FileItem]
    var loadedDirectoryURL: URL?
    var isLoading: Bool
    var errorMessage: String?
    var navigation: DirectoryNavigationState
    var selectedURLs: Set<URL> {
        didSet {
            if let currentPrimary = primarySelectedURL,
               selectedURLs.contains(currentPrimary) {
                return
            }

            primarySelectedURL = directoryContents.first(where: {
                selectedURLs.contains($0.url)
            })?.url ?? selectedURLs.first
        }
    }
    var pendingRevealURL: URL?
    var selectedSearchResultIDs: Set<ExplorerSearchResult.ID>
    var isInspectorPresented: Bool
    var showsHiddenItems: Bool
    var searchModel: ExplorerSearchModel

    private var primarySelectedURL: URL?

    init(
        id: UUID,
        place: SidebarPlace,
        navigation: DirectoryNavigationState = DirectoryNavigationState(),
        directoryContents: [FileItem] = [],
        loadedDirectoryURL: URL? = nil,
        isLoading: Bool = false,
        errorMessage: String? = nil,
        selectedURL: URL? = nil,
        pendingRevealURL: URL? = nil,
        selectedSearchResultID: ExplorerSearchResult.ID? = nil,
        isInspectorPresented: Bool = false,
        showsHiddenItems: Bool = false,
        searchModel: ExplorerSearchModel? = nil
    ) {
        self.id = id
        self.place = place
        self.navigation = navigation
        self.directoryContents = directoryContents
        self.loadedDirectoryURL = loadedDirectoryURL
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        selectedURLs = selectedURL.map { [$0] } ?? []
        primarySelectedURL = selectedURL
        self.pendingRevealURL = pendingRevealURL
        selectedSearchResultIDs = selectedSearchResultID.map { [$0] } ?? []
        self.isInspectorPresented = isInspectorPresented
        self.showsHiddenItems = showsHiddenItems
        self.searchModel = searchModel ?? ExplorerSearchModel()
    }

    var displayedDirectory: URL? {
        navigation.currentDirectory ?? place.url
    }

    /// The primary item is retained for preview and compatibility with
    /// single-item actions. Assigning it deliberately replaces the selection.
    var selectedURL: URL? {
        get { primarySelectedURL }
        set {
            replaceSelection(
                with: newValue.map { [$0] } ?? [],
                primaryURL: newValue
            )
        }
    }

    var selectedSearchResultID: ExplorerSearchResult.ID? {
        get {
            guard selectedSearchResultIDs.count == 1 else { return nil }
            return selectedSearchResultIDs.first
        }
        set {
            selectedSearchResultIDs = newValue.map { [$0] } ?? []
        }
    }

    var selectedCommandURLs: [URL] {
        if searchModel.isSearchActive {
            return searchModel.results.compactMap { result in
                selectedSearchResultIDs.contains(result.id)
                    ? result.item.url
                    : nil
            }
        }

        let visibleSelection = directoryContents.compactMap { item in
            selectedURLs.contains(item.url) ? item.url : nil
        }
        let visibleURLs = Set(visibleSelection)
        let remainingSelection = selectedURLs
            .subtracting(visibleURLs)
            .sorted {
                $0.path(percentEncoded: false)
                    < $1.path(percentEncoded: false)
            }
        return visibleSelection + remainingSelection
    }

    var selectedInspectorItem: FileItem? {
        if searchModel.isSearchActive {
            guard selectedSearchResultIDs.count == 1,
                  let selectedSearchResultID,
                  let result = searchModel.results.first(where: {
                      $0.id == selectedSearchResultID
                  }),
                  result.item.isDirectory || result.item.isImage else {
                return nil
            }

            return result.item
        }

        guard selectedURLs.count == 1, let selectedURL else { return nil }
        return directoryContents.first {
            $0.url == selectedURL && ($0.isDirectory || $0.isImage)
        }
    }

    func replaceSelection(
        with urls: Set<URL>,
        primaryURL: URL? = nil
    ) {
        primarySelectedURL = primaryURL.flatMap { urls.contains($0) ? $0 : nil }
            ?? directoryContents.first(where: { urls.contains($0.url) })?.url
            ?? urls.first
        selectedURLs = urls
    }

    /// Keeps surviving rows selected during an in-place directory refresh.
    func reconcileSelection(with contents: [FileItem]) {
        let availableURLs = Set(contents.map(\.url))
        let retainedSelection = selectedURLs.intersection(availableURLs)
        guard retainedSelection != selectedURLs else { return }

        replaceSelection(
            with: retainedSelection,
            primaryURL: primarySelectedURL
        )
    }

    func select(_ place: SidebarPlace) {
        self.place = place
        reset()
    }

    func select(place: SidebarPlace) {
        select(place)
    }

    func reset() {
        directoryContents = []
        loadedDirectoryURL = nil
        isLoading = false
        errorMessage = nil
        navigation = DirectoryNavigationState()
        selectedURL = nil
        pendingRevealURL = nil
        selectedSearchResultID = nil
        isInspectorPresented = false
        searchModel.query = ""
        searchModel.scope = .names
        searchModel.contentMode = .plain
    }
}

@MainActor
@Observable
final class WorkspaceModel {
    static let maximumIDGenerationAttempts = 64

    private(set) var layoutRoot: WorkspaceLayoutNode
    private(set) var activePaneID: UUID
    private var panes: [UUID: WorkspacePaneState]

    @ObservationIgnored private let makeID: @MainActor () -> UUID

    init(
        initialPlace: SidebarPlace = .downloads,
        initialPaneID: UUID = UUID(),
        idGenerator: @escaping @MainActor () -> UUID = { UUID() }
    ) {
        layoutRoot = .pane(id: initialPaneID)
        activePaneID = initialPaneID
        panes = [
            initialPaneID: WorkspacePaneState(id: initialPaneID, place: initialPlace)
        ]
        makeID = idGenerator
    }

    var layout: WorkspaceLayout {
        WorkspaceLayout(root: layoutRoot, activePaneID: activePaneID)
    }

    var activePane: WorkspacePaneState? { panes[activePaneID] }
    var paneCount: Int { layoutRoot.paneIDs.count }
    var canSplit: Bool { paneCount < WorkspaceLayout.maximumPaneCount }

    func pane(_ id: UUID) -> WorkspacePaneState? {
        panes[id]
    }

    func activate(_ paneID: UUID) {
        guard panes[paneID] != nil,
              layoutRoot.contains(paneID: paneID),
              paneID != activePaneID else {
            return
        }

        let previouslyActivePane = activePane
        activePaneID = paneID
        previouslyActivePane?.isInspectorPresented = false
    }

    func select(_ place: SidebarPlace) {
        activePane?.select(place)
    }

    func select(place: SidebarPlace) {
        select(place)
    }

    func select(_ place: SidebarPlace, in paneID: UUID) {
        guard let targetPane = panes[paneID] else { return }
        activate(paneID)
        targetPane.select(place)
    }

    /// Reveals a global-search hit in its containing folder without adding a
    /// transient location to the user's sidebar favorites.
    func reveal(_ item: FileItem, in paneID: UUID? = nil) {
        let targetPaneID = paneID ?? activePaneID
        guard let targetPane = panes[targetPaneID] else { return }

        let containingDirectory = item.url.deletingLastPathComponent()
        activate(targetPaneID)
        targetPane.select(.location(containingDirectory))
        targetPane.pendingRevealURL = item.url
    }

    func applyRename(_ result: FileRenameResult) {
        for pane in panes.values {
            if let favorite = pane.place.favorite,
               let relocatedURL = FileURLRelocation.rebase(
                   favorite.directoryURL,
                   from: result.sourceURL,
                   to: result.destinationURL
               ) {
                let usedAutomaticTitle = favorite.title
                    == result.sourceURL.lastPathComponent
                pane.place = .favorite(
                    SidebarFavorite(
                        id: favorite.id,
                        itemURL: relocatedURL,
                        isDirectory: favorite.isDirectory,
                        title: usedAutomaticTitle
                            ? result.destinationURL.lastPathComponent
                            : favorite.title
                    )
                )
            } else if pane.place.favorite == nil,
                      let placeURL = pane.place.url,
                      let relocatedURL = FileURLRelocation.rebase(
                          placeURL,
                          from: result.sourceURL,
                          to: result.destinationURL
                      ) {
                pane.place = .location(
                    relocatedURL,
                    title: relocatedURL.lastPathComponent,
                    systemImage: pane.place.systemImage
                )
            }

            pane.navigation.applyRename(result)
            let relocatedSelection = Set(pane.selectedURLs.map { selectedURL in
                FileURLRelocation.rebase(
                    selectedURL,
                    from: result.sourceURL,
                    to: result.destinationURL
                ) ?? selectedURL
            })
            let relocatedPrimarySelection = pane.selectedURL.map { selectedURL in
                FileURLRelocation.rebase(
                    selectedURL,
                    from: result.sourceURL,
                    to: result.destinationURL
                ) ?? selectedURL
            }
            if relocatedSelection != pane.selectedURLs {
                pane.replaceSelection(
                    with: relocatedSelection,
                    primaryURL: relocatedPrimarySelection
                )

                if let relocatedPrimarySelection {
                    // Directory reloads can briefly clear a List selection while
                    // the renamed row is being replaced. Reveal it again once the
                    // destination entry is present so focus is never lost.
                    pane.pendingRevealURL = relocatedPrimarySelection
                }
            }
            pane.pendingRevealURL = pane.pendingRevealURL.flatMap { pendingURL in
                FileURLRelocation.rebase(
                    pendingURL,
                    from: result.sourceURL,
                    to: result.destinationURL
                ) ?? pendingURL
            }
        }
    }

    /// Moves panes away from a disk after macOS confirms that it was ejected.
    /// The split layout is preserved; only panes whose current directory was on
    /// that volume return to Home.
    @discardableResult
    func handleEjectedVolume(at volumeURL: URL) -> Int {
        let normalizedVolumeURL = volumeURL.standardizedFileURL
        guard normalizedVolumeURL.isFileURL,
              normalizedVolumeURL.path(percentEncoded: false) != "/" else {
            return 0
        }

        var relocatedPaneCount = 0
        for pane in panes.values {
            guard let directoryURL = pane.displayedDirectory,
                  Self.isSameOrDescendant(
                      directoryURL,
                      of: normalizedVolumeURL
                  ) else {
                continue
            }

            pane.select(.home)
            relocatedPaneCount += 1
        }
        return relocatedPaneCount
    }

    @discardableResult
    func split(_ direction: WorkspaceSplitDirection) -> UUID? {
        split(paneID: activePaneID, direction: direction)
    }

    @discardableResult
    func split(
        paneID: UUID,
        direction: WorkspaceSplitDirection
    ) -> UUID? {
        guard canSplit, let sourcePane = panes[paneID] else { return nil }

        let previouslyActivePane = activePane
        guard let newPaneID = makeUniqueID(),
              let splitID = makeUniqueID(excluding: [newPaneID]) else {
            return nil
        }
        let newPane = WorkspacePaneState(
            id: newPaneID,
            place: sourcePane.place,
            navigation: sourcePane.navigation,
            showsHiddenItems: sourcePane.showsHiddenItems
        )

        var updatedLayout = layout
        guard updatedLayout.split(
            paneID: paneID,
            direction: direction,
            newPaneID: newPaneID,
            splitID: splitID
        ) else {
            return nil
        }

        layoutRoot = updatedLayout.root
        activePaneID = updatedLayout.activePaneID
        panes[newPaneID] = newPane
        previouslyActivePane?.isInspectorPresented = false
        sourcePane.isInspectorPresented = false
        return newPaneID
    }

    @discardableResult
    func close(_ paneID: UUID) -> Bool {
        var updatedLayout = layout
        guard updatedLayout.close(paneID) else { return false }

        activePaneID = updatedLayout.activePaneID
        layoutRoot = updatedLayout.root
        panes[paneID] = nil
        return true
    }

    @discardableResult
    func resetView() -> Bool {
        guard paneCount > 1, let activePane else { return false }

        layoutRoot = .pane(id: activePaneID)
        panes = [activePaneID: activePane]
        return true
    }

    private func makeUniqueID(excluding additionalIDs: Set<UUID> = []) -> UUID? {
        for _ in 0..<Self.maximumIDGenerationAttempts {
            let id = makeID()
            if layoutRoot.nodeIDs.contains(id) == false,
               additionalIDs.contains(id) == false {
                return id
            }
        }

        return nil
    }

    private nonisolated static func isSameOrDescendant(
        _ candidateURL: URL,
        of ancestorURL: URL
    ) -> Bool {
        let candidateURL = candidateURL.standardizedFileURL
        let ancestorURL = ancestorURL.standardizedFileURL
        let candidateComponents = candidateURL.pathComponents
        let ancestorComponents = ancestorURL.pathComponents

        return candidateURL.isFileURL
            && ancestorURL.isFileURL
            && candidateComponents.count >= ancestorComponents.count
            && candidateComponents.prefix(ancestorComponents.count)
                .elementsEqual(ancestorComponents)
    }
}
