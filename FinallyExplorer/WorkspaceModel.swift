//
//  WorkspaceModel.swift
//  FinallyExplorer
//

import Foundation
import Observation

nonisolated enum SidebarPlace: String, CaseIterable, Identifiable, Hashable, Sendable {
    case downloads
    case desktop
    case documents

    var id: Self { self }

    var title: String {
        switch self {
        case .downloads:
            "Downloads"
        case .desktop:
            "Desktop"
        case .documents:
            "Documents"
        }
    }

    var systemImage: String {
        switch self {
        case .downloads:
            "arrow.down.circle"
        case .desktop:
            "desktopcomputer"
        case .documents:
            "doc"
        }
    }

    var url: URL? {
        switch self {
        case .downloads:
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        case .desktop:
            FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        case .documents:
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        }
    }
}

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
    var isLoading: Bool
    var errorMessage: String?
    var navigation: DirectoryNavigationState
    var selectedURL: URL?
    var selectedSearchResultID: ExplorerSearchResult.ID?
    var isInspectorPresented: Bool
    var searchModel: ExplorerSearchModel

    init(
        id: UUID,
        place: SidebarPlace,
        navigation: DirectoryNavigationState = DirectoryNavigationState(),
        directoryContents: [FileItem] = [],
        isLoading: Bool = false,
        errorMessage: String? = nil,
        selectedURL: URL? = nil,
        selectedSearchResultID: ExplorerSearchResult.ID? = nil,
        isInspectorPresented: Bool = false,
        searchModel: ExplorerSearchModel? = nil
    ) {
        self.id = id
        self.place = place
        self.navigation = navigation
        self.directoryContents = directoryContents
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.selectedURL = selectedURL
        self.selectedSearchResultID = selectedSearchResultID
        self.isInspectorPresented = isInspectorPresented
        self.searchModel = searchModel ?? ExplorerSearchModel()
    }

    var displayedDirectory: URL? {
        navigation.currentDirectory ?? place.url
    }

    var selectedCommandURLs: [URL] {
        if searchModel.isSearchActive {
            guard let selectedSearchResultID,
                  let result = searchModel.results.first(where: {
                      $0.id == selectedSearchResultID
                  }) else {
                return []
            }

            return [result.item.url]
        }

        return selectedURL.map { [$0] } ?? []
    }

    var selectedInspectorItem: FileItem? {
        if searchModel.isSearchActive {
            guard let selectedSearchResultID,
                  let result = searchModel.results.first(where: {
                      $0.id == selectedSearchResultID
                  }),
                  result.item.isDirectory || result.item.isImage else {
                return nil
            }

            return result.item
        }

        guard let selectedURL else { return nil }
        return directoryContents.first {
            $0.url == selectedURL && ($0.isDirectory || $0.isImage)
        }
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
        isLoading = false
        errorMessage = nil
        navigation = DirectoryNavigationState()
        selectedURL = nil
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
            navigation: sourcePane.navigation
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
}
