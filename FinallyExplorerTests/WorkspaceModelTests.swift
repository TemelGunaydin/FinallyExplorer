//
//  WorkspaceModelTests.swift
//  FinallyExplorerTests
//

import Foundation
import Observation
import Testing
@testable import FinallyExplorer

struct WorkspaceLayoutTests {
    @Test(
        "Every split direction creates the matching stable node",
        arguments: [
            WorkspaceSplitExpectation(
                direction: .right,
                axis: .sideBySide,
                firstID: uuid(1),
                secondID: uuid(2),
                splitID: uuid(3)
            ),
            WorkspaceSplitExpectation(
                direction: .below,
                axis: .stacked,
                firstID: uuid(10),
                secondID: uuid(11),
                splitID: uuid(12)
            )
        ]
    )
    func splitDirectionMapping(_ expectation: WorkspaceSplitExpectation) {
        var layout = WorkspaceLayout(initialPaneID: expectation.firstID)

        let didSplit = layout.split(
            direction: expectation.direction,
            newPaneID: expectation.secondID,
            splitID: expectation.splitID
        )
        #expect(didSplit)
        #expect(
            layout.root == .split(
                id: expectation.splitID,
                axis: expectation.axis,
                first: .pane(id: expectation.firstID),
                second: .pane(id: expectation.secondID)
            )
        )
        #expect(layout.activePaneID == expectation.secondID)
    }

    @Test("Nested splits preserve the identity and position of existing nodes")
    func nestedSplitPreservesExistingTree() {
        let first = uuid(20)
        let second = uuid(21)
        let third = uuid(22)
        let rootSplit = uuid(23)
        let nestedSplit = uuid(24)
        var layout = WorkspaceLayout(initialPaneID: first)

        let didSplitRight = layout.split(
            direction: .right,
            newPaneID: second,
            splitID: rootSplit
        )
        let didSplitBelow = layout.split(
            paneID: first,
            direction: .below,
            newPaneID: third,
            splitID: nestedSplit
        )
        #expect(didSplitRight)
        #expect(didSplitBelow)

        #expect(
            layout.root == .split(
                id: rootSplit,
                axis: .sideBySide,
                first: .split(
                    id: nestedSplit,
                    axis: .stacked,
                    first: .pane(id: first),
                    second: .pane(id: third)
                ),
                second: .pane(id: second)
            )
        )
        #expect(layout.paneIDs == [first, third, second])
    }

    @Test("A workspace never grows beyond four panes")
    func maximumPaneCount() {
        let ids = (30...38).map(uuid)
        var layout = WorkspaceLayout(initialPaneID: ids[0])

        let secondPane = layout.split(
            direction: .right,
            newPaneID: ids[1],
            splitID: ids[2]
        )
        let thirdPane = layout.split(
            direction: .below,
            newPaneID: ids[3],
            splitID: ids[4]
        )
        let fourthPane = layout.split(
            direction: .right,
            newPaneID: ids[5],
            splitID: ids[6]
        )
        #expect(secondPane)
        #expect(thirdPane)
        #expect(fourthPane)
        #expect(layout.paneCount == WorkspaceLayout.maximumPaneCount)
        #expect(layout.canSplit == false)
        let rootAtCapacity = layout.root
        let activePaneAtCapacity = layout.activePaneID
        let fifthPane = layout.split(
            direction: .below,
            newPaneID: ids[7],
            splitID: ids[8]
        )
        #expect(fifthPane == false)
        #expect(layout.paneIDs.contains(ids[7]) == false)
        #expect(layout.root == rootAtCapacity)
        #expect(layout.activePaneID == activePaneAtCapacity)
    }

    @Test("Unknown and colliding identifiers never corrupt the layout")
    func rejectsInvalidIdentifiersWithoutMutation() {
        let first = uuid(90)
        let second = uuid(91)
        let rootSplit = uuid(92)
        let unknown = uuid(93)
        var layout = WorkspaceLayout(initialPaneID: first)
        let initialSplit = layout.split(
            direction: .right,
            newPaneID: second,
            splitID: rootSplit
        )
        #expect(initialSplit)
        let validLayout = layout

        let activatedUnknown = layout.activate(unknown)
        #expect(activatedUnknown == false)
        #expect(layout == validLayout)
        let closedUnknown = layout.close(unknown)
        #expect(closedUnknown == false)
        #expect(layout == validLayout)

        let splitUnknown = layout.split(
            paneID: unknown,
            direction: .below,
            newPaneID: uuid(94),
            splitID: uuid(95)
        )
        #expect(splitUnknown == false)
        #expect(layout == validLayout)

        let reusedPaneID = layout.split(
            paneID: first,
            direction: .below,
            newPaneID: second,
            splitID: uuid(96)
        )
        #expect(reusedPaneID == false)
        #expect(layout == validLayout)

        let reusedSplitID = layout.split(
            paneID: first,
            direction: .below,
            newPaneID: uuid(97),
            splitID: rootSplit
        )
        #expect(reusedSplitID == false)
        #expect(layout == validLayout)

        let reusedID = uuid(98)
        let paneAndSplitIDCollide = layout.split(
            paneID: first,
            direction: .below,
            newPaneID: reusedID,
            splitID: reusedID
        )
        #expect(paneAndSplitIDCollide == false)
        #expect(layout == validLayout)
    }

    @Test("Closing a pane collapses its redundant parent split")
    func closeCollapsesParent() {
        let first = uuid(40)
        let second = uuid(41)
        let third = uuid(42)
        let rootSplit = uuid(43)
        let nestedSplit = uuid(44)
        var layout = WorkspaceLayout(initialPaneID: first)

        let didSplitRight = layout.split(
            direction: .right,
            newPaneID: second,
            splitID: rootSplit
        )
        let didSplitBelow = layout.split(
            paneID: second,
            direction: .below,
            newPaneID: third,
            splitID: nestedSplit
        )
        let didCloseThird = layout.close(third)
        #expect(didSplitRight)
        #expect(didSplitBelow)
        #expect(didCloseThird)

        #expect(
            layout.root == .split(
                id: rootSplit,
                axis: .sideBySide,
                first: .pane(id: first),
                second: .pane(id: second)
            )
        )
        #expect(layout.activePaneID == second)
        let didCloseFirst = layout.close(first)
        #expect(didCloseFirst)
        #expect(layout.root == .pane(id: second))
        #expect(layout.activePaneID == second)
        let didCloseLast = layout.close(second)
        #expect(didCloseLast == false)
        #expect(layout.root == .pane(id: second))
        #expect(layout.activePaneID == second)
    }
}

nonisolated struct WorkspaceSplitExpectation: Sendable {
    let direction: WorkspaceSplitDirection
    let axis: WorkspaceSplitAxis
    let firstID: UUID
    let secondID: UUID
    let splitID: UUID
}

@MainActor
struct WorkspaceModelTests {
    @Test("Activating a pane does not invalidate the split structure")
    func activationPreservesSplitStructureObservation() async throws {
        let firstID = uuid(45)
        let secondID = uuid(46)
        let splitID = uuid(47)
        let ids = DeterministicWorkspaceIDSequence([secondID, splitID])
        let model = WorkspaceModel(
            initialPaneID: firstID,
            idGenerator: { ids.next() }
        )
        _ = try #require(model.split(.right))
        let originalRoot = model.layoutRoot

        await confirmation(
            "The recursive split tree must not be invalidated by selection-only state",
            expectedCount: 0
        ) { rootInvalidated in
            withObservationTracking {
                _ = model.layoutRoot
            } onChange: {
                rootInvalidated()
            }

            model.activate(firstID)
        }

        #expect(model.activePaneID == firstID)
        #expect(model.layoutRoot == originalRoot)
    }

    @Test("Splitting clones only place and navigation while preserving pane identity")
    func splitClonesNavigationAndPreservesStateIdentity() throws {
        let firstID = uuid(50)
        let secondID = uuid(51)
        let splitID = uuid(52)
        let ids = DeterministicWorkspaceIDSequence([secondID, splitID])
        let model = WorkspaceModel(
            initialPlace: .documents,
            initialPaneID: firstID,
            idGenerator: { ids.next() }
        )
        let firstPane = try #require(model.activePane)
        let folder = URL(filePath: "/tmp/project", directoryHint: .isDirectory)
        let selected = URL(filePath: "/tmp/project/selected.png")
        firstPane.navigation.open(folder)
        firstPane.directoryContents = [
            FileItem(
                url: selected,
                isDirectory: false,
                isImage: true,
                fileSize: 10,
                modificationDate: nil
            )
        ]
        firstPane.isLoading = true
        firstPane.selectedURL = selected
        firstPane.errorMessage = "Keep only in the source pane"
        firstPane.isInspectorPresented = true
        firstPane.showsHiddenItems = true
        firstPane.searchModel.query = "needle"

        let createdID = try #require(model.split(.right))
        let originalAfterSplit = try #require(model.pane(firstID))
        let newPane = try #require(model.pane(createdID))

        #expect(createdID == secondID)
        #expect(originalAfterSplit === firstPane)
        #expect(newPane !== firstPane)
        #expect(newPane.place == .documents)
        #expect(newPane.navigation == firstPane.navigation)
        #expect(newPane.displayedDirectory == folder)
        #expect(newPane.directoryContents.isEmpty)
        #expect(newPane.isLoading == false)
        #expect(newPane.selectedURL == nil)
        #expect(newPane.errorMessage == nil)
        #expect(newPane.isInspectorPresented == false)
        #expect(newPane.showsHiddenItems)
        #expect(newPane.searchModel.query.isEmpty)
        #expect(newPane.searchModel !== firstPane.searchModel)
        #expect(model.activePane === newPane)
        #expect(firstPane.isInspectorPresented == false)

        let deeperFolder = folder.appending(path: "source-only", directoryHint: .isDirectory)
        firstPane.navigation.open(deeperFolder)
        firstPane.searchModel.query = "source-only"
        #expect(newPane.navigation.currentDirectory == folder)
        #expect(newPane.searchModel.query.isEmpty)

        newPane.navigation.goBack()
        newPane.showsHiddenItems = false
        newPane.searchModel.query = "new-pane-only"
        #expect(firstPane.navigation.currentDirectory == deeperFolder)
        #expect(firstPane.showsHiddenItems)
        #expect(firstPane.searchModel.query == "source-only")

        #expect(model.close(createdID))
        #expect(model.pane(createdID) == nil)
        #expect(model.activePane === firstPane)
        #expect(model.paneCount == 1)
    }

    @Test("Reset view keeps the active pane and discards every other pane")
    func resetViewPreservesActivePaneState() throws {
        let firstID = uuid(54)
        let secondID = uuid(55)
        let splitID = uuid(56)
        let ids = DeterministicWorkspaceIDSequence([secondID, splitID])
        let model = WorkspaceModel(
            initialPlace: .downloads,
            initialPaneID: firstID,
            idGenerator: { ids.next() }
        )
        let firstPane = try #require(model.activePane)
        _ = try #require(model.split(.right))
        let activePane = try #require(model.activePane)
        let retainedDirectory = URL(
            filePath: "/tmp/retained-pane",
            directoryHint: .isDirectory
        )
        let retainedSelection = retainedDirectory.appending(path: "selection.txt")

        activePane.place = .desktop
        activePane.navigation.open(retainedDirectory)
        activePane.selectedURL = retainedSelection
        activePane.searchModel.query = "keep this search"

        #expect(model.resetView())
        #expect(model.layoutRoot == .pane(id: secondID))
        #expect(model.activePaneID == secondID)
        #expect(model.activePane === activePane)
        #expect(model.pane(firstID) == nil)
        #expect(model.pane(secondID) === activePane)
        #expect(model.paneCount == 1)
        #expect(firstPane !== activePane)
        #expect(activePane.place == .desktop)
        #expect(activePane.navigation.currentDirectory == retainedDirectory)
        #expect(activePane.selectedURL == retainedSelection)
        #expect(activePane.searchModel.query == "keep this search")

        let resetLayout = model.layout
        #expect(model.resetView() == false)
        #expect(model.layout == resetLayout)
        #expect(model.activePane === activePane)
    }

    @Test("Selecting a sidebar place resets only the active pane")
    func placeSelectionResetsOnlyActivePane() throws {
        let firstID = uuid(60)
        let secondID = uuid(61)
        let splitID = uuid(62)
        let ids = DeterministicWorkspaceIDSequence([secondID, splitID])
        let model = WorkspaceModel(
            initialPlace: .downloads,
            initialPaneID: firstID,
            idGenerator: { ids.next() }
        )
        let firstPane = try #require(model.activePane)
        firstPane.navigation.open(URL(filePath: "/tmp/downloads-child"))
        _ = try #require(model.split(.below))
        let secondPane = try #require(model.activePane)
        secondPane.selectedURL = URL(filePath: "/tmp/selected.txt")

        model.select(.desktop)

        #expect(secondPane.place == .desktop)
        #expect(secondPane.navigation == DirectoryNavigationState())
        #expect(secondPane.selectedURL == nil)
        #expect(firstPane.place == .downloads)
        #expect(firstPane.navigation.currentDirectory != nil)
    }

    @Test("Ejecting a disk relocates only affected panes and preserves the layout")
    func ejectedVolumeRelocatesAffectedPanes() throws {
        let firstID = uuid(63)
        let secondID = uuid(64)
        let splitID = uuid(66)
        let ids = DeterministicWorkspaceIDSequence([secondID, splitID])
        let volumeURL = URL(
            filePath: "/Volumes/Work USB",
            directoryHint: .isDirectory
        )
        let model = WorkspaceModel(
            initialPlace: .location(
                volumeURL,
                title: "Work USB",
                systemImage: "externaldrive"
            ),
            initialPaneID: firstID,
            idGenerator: { ids.next() }
        )
        let affectedPane = try #require(model.activePane)
        affectedPane.navigation.open(
            volumeURL.appending(path: "Projects", directoryHint: .isDirectory)
        )
        _ = try #require(model.split(.right))
        let unaffectedPane = try #require(model.activePane)
        model.select(.documents)
        let originalLayout = model.layoutRoot

        #expect(model.handleEjectedVolume(at: volumeURL) == 1)
        #expect(affectedPane.place == .home)
        #expect(affectedPane.navigation == DirectoryNavigationState())
        #expect(unaffectedPane.place == .documents)
        #expect(model.layoutRoot == originalLayout)
        #expect(model.paneCount == 2)
    }

    @Test("Selecting the current place returns that pane to its root")
    func selectingCurrentPlaceReturnsToRoot() throws {
        let model = WorkspaceModel(
            initialPlace: .downloads,
            initialPaneID: uuid(65)
        )
        let pane = try #require(model.activePane)
        pane.navigation.open(URL(filePath: "/tmp/downloads-child"))
        pane.searchModel.query = "needle"

        model.select(.downloads)

        #expect(pane.navigation == DirectoryNavigationState())
        #expect(pane.searchModel.query.isEmpty)
        #expect(pane.place == .downloads)
    }

    @Test("Reselecting the current root preserves its loaded contents")
    func reselectingCurrentRootPreservesLoadedState() throws {
        let rootURL = URL(
            filePath: "/tmp/Current Root",
            directoryHint: .isDirectory
        )
        let place = SidebarPlace.location(rootURL, title: "Current Root")
        let model = WorkspaceModel(
            initialPlace: place,
            initialPaneID: uuid(67)
        )
        let pane = try #require(model.activePane)
        let item = FileItem(
            url: rootURL.appending(path: "Existing.pdf"),
            isDirectory: false,
            isImage: false,
            fileSize: 128,
            modificationDate: nil
        )
        pane.directoryContents = [item]
        pane.loadedDirectoryURL = rootURL
        pane.selectedURL = item.url
        pane.searchModel.query = "keep this search"

        model.select(place)

        #expect(pane.place == place)
        #expect(pane.displayedDirectory == rootURL)
        #expect(pane.directoryContents == [item])
        #expect(pane.loadedDirectoryURL == rootURL)
        #expect(pane.selectedURL == item.url)
        #expect(pane.searchModel.query == "keep this search")
    }

    @Test("Activating or directly selecting another pane dismisses the previous inspector")
    func activationKeepsOneInspector() throws {
        let firstID = uuid(70)
        let secondID = uuid(71)
        let splitID = uuid(72)
        let ids = DeterministicWorkspaceIDSequence([secondID, splitID])
        let model = WorkspaceModel(
            initialPlace: .downloads,
            initialPaneID: firstID,
            idGenerator: { ids.next() }
        )
        let firstPane = try #require(model.activePane)
        _ = try #require(model.split(.right))
        let secondPane = try #require(model.activePane)

        secondPane.isInspectorPresented = true
        model.activate(firstID)
        #expect(secondPane.isInspectorPresented == false)
        #expect(model.activePane === firstPane)

        firstPane.isInspectorPresented = true
        secondPane.navigation.open(URL(filePath: "/tmp/child"))
        model.select(.documents, in: secondID)

        #expect(firstPane.isInspectorPresented == false)
        #expect(model.activePane === secondPane)
        #expect(secondPane.place == .documents)
        #expect(secondPane.navigation == DirectoryNavigationState())
    }

    @Test("Invalid pane commands leave model state unchanged")
    func invalidPaneCommandsAreNoOps() throws {
        let firstID = uuid(80)
        let invalidID = uuid(81)
        let model = WorkspaceModel(
            initialPlace: .downloads,
            initialPaneID: firstID
        )
        let firstPane = try #require(model.activePane)
        firstPane.navigation.open(URL(filePath: "/tmp/keep-me"))
        let originalLayout = model.layout

        model.activate(invalidID)
        model.select(.desktop, in: invalidID)
        #expect(model.split(paneID: invalidID, direction: .right) == nil)
        #expect(model.close(invalidID) == false)

        #expect(model.layout == originalLayout)
        #expect(model.activePane === firstPane)
        #expect(firstPane.place == .downloads)
        #expect(firstPane.navigation.currentDirectory == URL(filePath: "/tmp/keep-me"))
    }

    @Test("A broken ID generator cannot spin forever or partially create a pane")
    func idCollisionExhaustionIsBoundedAndAtomic() throws {
        let firstID = uuid(82)
        let repeatedID = uuid(83)
        var generationCount = 0
        let model = WorkspaceModel(
            initialPaneID: firstID,
            idGenerator: {
                generationCount += 1
                return repeatedID
            }
        )
        let initialPane = try #require(model.activePane)
        let originalLayout = model.layout

        #expect(model.split(.right) == nil)

        #expect(
            generationCount == WorkspaceModel.maximumIDGenerationAttempts + 1,
            "The pane ID is accepted once; split-ID collisions must then stop at the bound."
        )
        #expect(model.layout == originalLayout)
        #expect(model.paneCount == 1)
        #expect(model.pane(repeatedID) == nil)
        #expect(model.activePane === initialPane)
    }

    @Test("Search mode never falls back to a stale directory selection")
    func activeSearchRejectsStaleDirectorySelection() throws {
        let model = WorkspaceModel(initialPaneID: uuid(84))
        let pane = try #require(model.activePane)
        let staleURL = URL(filePath: "/tmp/stale.png")
        let staleItem = FileItem(
            url: staleURL,
            isDirectory: false,
            isImage: true,
            fileSize: 1,
            modificationDate: nil
        )
        pane.directoryContents = [staleItem]
        pane.selectedURL = staleURL
        pane.selectedSearchResultID = "missing-search-result"
        pane.searchModel.query = "needle"

        #expect(pane.selectedCommandURLs.isEmpty)
        #expect(pane.selectedInspectorItem == nil)

        pane.searchModel.query = ""
        #expect(pane.selectedCommandURLs == [staleURL])
        #expect(pane.selectedInspectorItem == staleItem)
    }

    @Test("Directory multi-selection stays ordered and retains surviving rows")
    func multiSelectionReconcilesWithoutClearingSurvivors() throws {
        let model = WorkspaceModel(initialPaneID: uuid(86))
        let pane = try #require(model.activePane)
        let folderURL = URL(filePath: "/tmp/A Folder", directoryHint: .isDirectory)
        let removedURL = URL(filePath: "/tmp/B Removed.txt")
        let remainingURL = URL(filePath: "/tmp/C Remaining.txt")
        let folder = FileItem(
            url: folderURL,
            isDirectory: true,
            isImage: false,
            fileSize: nil,
            modificationDate: nil
        )
        let removed = FileItem(
            url: removedURL,
            isDirectory: false,
            isImage: false,
            fileSize: 1,
            modificationDate: nil
        )
        let remaining = FileItem(
            url: remainingURL,
            isDirectory: false,
            isImage: false,
            fileSize: 1,
            modificationDate: nil
        )
        pane.directoryContents = [folder, removed, remaining]
        pane.replaceSelection(
            with: [remainingURL, folderURL, removedURL],
            primaryURL: folderURL
        )

        #expect(
            pane.selectedCommandURLs == [folderURL, removedURL, remainingURL]
        )
        #expect(pane.selectedInspectorItem == nil)

        pane.reconcileSelection(with: [folder, remaining])

        #expect(pane.selectedURLs == [folderURL, remainingURL])
        #expect(pane.selectedURL == folderURL)
        #expect(pane.selectedCommandURLs == [folderURL, remainingURL])

        pane.reconcileSelection(with: [folder])

        #expect(pane.selectedURLs == [folderURL])
        #expect(pane.selectedInspectorItem == folder)
    }

    @Test("Global search reveal activates the target pane and selects the item in its parent")
    func revealGlobalResultUsesTransientLocation() throws {
        let firstID = uuid(90)
        let secondID = uuid(91)
        let splitID = uuid(92)
        let ids = DeterministicWorkspaceIDSequence([secondID, splitID])
        let model = WorkspaceModel(
            initialPlace: .downloads,
            initialPaneID: firstID,
            idGenerator: { ids.next() }
        )
        let firstPane = try #require(model.activePane)
        firstPane.searchModel.query = "stale"
        _ = try #require(model.split(.right))

        let itemURL = URL(filePath: "/Projects/App/ContentView.swift")
        let item = FileItem(
            url: itemURL,
            isDirectory: false,
            isImage: false,
            fileSize: 12,
            modificationDate: nil
        )

        model.reveal(item, in: firstID)

        #expect(model.activePaneID == firstID)
        #expect(model.activePane === firstPane)
        #expect(firstPane.displayedDirectory == itemURL.deletingLastPathComponent())
        #expect(firstPane.place.favorite == nil)
        #expect(firstPane.place.title == "App")
        #expect(firstPane.selectedURL == nil)
        #expect(firstPane.pendingRevealURL == itemURL)
        #expect(firstPane.searchModel.query.isEmpty)
    }
}

@MainActor
private final class DeterministicWorkspaceIDSequence {
    private var ids: [UUID]

    init(_ ids: [UUID]) {
        self.ids = ids
    }

    func next() -> UUID {
        ids.removeFirst()
    }
}

private func uuid(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", value))!
}
