//
//  FinallyExplorerUITests.swift
//  FinallyExplorerUITests
//

import XCTest

final class FinallyExplorerUITests: XCTestCase {
    private var app: XCUIApplication!
    private var fixtureRootURL: URL!
    private var mountedVolumeURL: URL!
    private var defaultsSuiteName: String!

    override func setUpWithError() throws {
        continueAfterFailure = false

        fixtureRootURL = FileManager.default.temporaryDirectory
            .appending(
                path: "FinallyExplorerUITests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defaultsSuiteName = "FinallyExplorer.UITests.\(UUID().uuidString)"
        mountedVolumeURL = FileManager.default.temporaryDirectory
            .appending(
                path: "FinallyExplorerUITests-USB-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )

        try FileManager.default.createDirectory(
            at: fixtureRootURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: mountedVolumeURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: destinationFolderURL,
            withIntermediateDirectories: false
        )
        try FileManager.default.createDirectory(
            at: globalSearchFolderURL,
            withIntermediateDirectories: false
        )
        try Data("Finally Explorer cross-pane drag regression fixture.".utf8)
            .write(to: sourceFileURL, options: .atomic)
        try Data("A grep-only-phrase lives inside this fixture.".utf8)
            .write(to: globalSearchAlphaURL, options: .atomic)
        try Data("A second keyboard-navigation result.".utf8)
            .write(to: globalSearchBetaURL, options: .atomic)

        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment = [
            "FINALLY_EXPLORER_UI_FIXTURE_ROOT": fixtureRootURL.path(),
            "FINALLY_EXPLORER_UI_MOUNTED_VOLUME": mountedVolumeURL.path(),
            "FINALLY_EXPLORER_UI_DEFAULTS_SUITE": defaultsSuiteName,
            "FINALLY_EXPLORER_UI_NEARBY_PEER": "UI Test Mac",
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()

        if let defaultsSuiteName {
            UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName)
        }

        if let fixtureRootURL {
            try? FileManager.default.removeItem(at: fixtureRootURL)
        }
        if let mountedVolumeURL {
            try? FileManager.default.removeItem(at: mountedVolumeURL)
        }

        app = nil
        fixtureRootURL = nil
        mountedVolumeURL = nil
        defaultsSuiteName = nil
    }

    func testFullRowSelectionAndCrossPaneDrag() throws {
        let sourceRows = rows(named: "Source Item.txt")
        let destinationRows = rows(named: "Destination")

        XCTAssertTrue(
            sourceRows.firstMatch.waitForExistence(timeout: 10),
            "The file fixture did not appear after launch"
        )
        XCTAssertTrue(destinationRows.firstMatch.waitForExistence(timeout: 10))

        let initialSource = sourceRows.firstMatch
        initialSource.coordinate(
            withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5)
        ).click()
        let selectedSourceCell = try XCTUnwrap(containingCell(for: initialSource))
        XCTAssertTrue(
            selectedSourceCell.isSelected,
            "Clicking the open area of a row must select its containing cell"
        )

        let splitRightButton = app.buttons["Split Right"]
        XCTAssertTrue(splitRightButton.waitForExistence(timeout: 3))
        splitRightButton.click()

        XCTAssertTrue(waitForElementCount(sourceRows, toEqual: 2, timeout: 5))
        XCTAssertTrue(waitForElementCount(destinationRows, toEqual: 2, timeout: 5))
        XCTAssertTrue(app.buttons["Reset View"].waitForExistence(timeout: 3))

        let visibleSources = existingElements(in: sourceRows).sorted(by: leftToRight)
        let visibleDestinations = existingElements(in: destinationRows).sorted(by: leftToRight)
        let leftSource = try XCTUnwrap(visibleSources.first)
        let rightDestination = try XCTUnwrap(visibleDestinations.last)
        let leftSourceCell = try XCTUnwrap(containingCell(for: leftSource))
        let rightDestinationCell = try XCTUnwrap(containingCell(for: rightDestination))

        XCTAssertLessThan(leftSource.frame.midX, rightDestination.frame.midX)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: copiedFileURL.path(percentEncoded: false)
            )
        )

        rightDestinationCell
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .doubleClick()
        let emptyDestination = app.staticTexts["Folder Is Empty"]
        XCTAssertTrue(emptyDestination.waitForExistence(timeout: 5))

        let dragOrigin = leftSourceCell.coordinate(
            withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)
        )
        let dragDestination = emptyDestination.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        )
        dragOrigin.click(
            forDuration: 0.5,
            thenDragTo: dragDestination,
            withVelocity: .slow,
            thenHoldForDuration: 0.8
        )

        XCTAssertTrue(
            waitForElementCount(sourceRows, toEqual: 2, timeout: 10),
            "Dragging from one pane to a folder in another pane must copy the file. "
                + "Destination contents: \(destinationContents())"
        )
        XCTAssertEqual(
            try Data(contentsOf: copiedFileURL),
            try Data(contentsOf: sourceFileURL)
        )
    }

    func testCopyAndPasteShowTransientBottomFeedback() throws {
        let sourceRow = rows(named: "Source Item.txt").firstMatch
        let destinationRow = rows(named: "Destination").firstMatch
        XCTAssertTrue(sourceRow.waitForExistence(timeout: 10))
        XCTAssertTrue(destinationRow.waitForExistence(timeout: 5))

        sourceRow.coordinate(
            withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)
        ).click()
        XCTAssertTrue(try XCTUnwrap(containingCell(for: sourceRow)).isSelected)

        try rightClickRow(sourceRow)
        let copyCommand = sourceRow.menuItems["Copy"]
        XCTAssertTrue(copyCommand.waitForExistence(timeout: 3))
        XCTAssertTrue(copyCommand.isEnabled)
        copyCommand.click()

        let toast = app.descendants(matching: .any)["file-operation-toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertEqual(toast.value as? String, "Copied")
        XCTAssertGreaterThan(
            toast.frame.midY,
            app.windows.firstMatch.frame.midY,
            "File-operation feedback must appear in the bottom half of the window"
        )

        try rightClickRow(destinationRow)
        let pasteCommand = app.menuItems["Paste Into Folder"]
        XCTAssertTrue(pasteCommand.waitForExistence(timeout: 3))
        XCTAssertTrue(pasteCommand.isEnabled)
        pasteCommand.click()

        XCTAssertTrue(waitForValue("Pasted", on: toast, timeout: 5))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: copiedFileURL.path(percentEncoded: false)
            ),
            "Paste feedback must correspond to a completed copy. "
                + "Destination: \(destinationContents()); "
                + "fixture root: \(fixtureContents())"
        )
        XCTAssertTrue(toast.waitForNonExistence(timeout: 10))
    }

    func testSidebarToolbarButtonAlignsWithSidebarAndOmitsRetiredControls() {
        XCTAssertTrue(
            rows(named: "Source Item.txt").firstMatch.waitForExistence(timeout: 10)
        )

        let sidebarToggle = app.buttons["window-sidebar-toggle"]
        XCTAssertTrue(
            sidebarToggle.waitForExistence(timeout: 5),
            "The sidebar control must remain in the native window toolbar"
        )
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
        let sidebarToggleLeadingOffset = sidebarToggle.frame.minX - window.frame.minX
        XCTAssertGreaterThan(
            sidebarToggleLeadingOffset,
            180,
            "The sidebar control must align with the sidebar's trailing edge"
        )
        XCTAssertLessThan(
            sidebarToggleLeadingOffset,
            360,
            "The sidebar control must not drift into the content toolbar"
        )
        XCTAssertFalse(app.buttons["Ask Explorer"].exists)
        XCTAssertFalse(app.staticTexts["Your files. Your workspace."].exists)

        let hidePreview = app.buttons["Hide Preview"]
        XCTAssertTrue(hidePreview.waitForExistence(timeout: 5))
        let splitRight = app.buttons["Split Right"]
        let splitBelow = app.buttons["Split Below"]
        XCTAssertTrue(splitRight.waitForExistence(timeout: 5))
        XCTAssertTrue(splitBelow.waitForExistence(timeout: 5))
        XCTAssertLessThan(
            splitRight.frame.maxX,
            splitBelow.frame.minX,
            "Horizontal and vertical split controls must stay adjacent and ordered"
        )
        XCTAssertLessThan(
            splitBelow.frame.maxX,
            hidePreview.frame.minX,
            "The preview toggle belongs at the trailing edge of the pane toolbar"
        )
        XCTAssertGreaterThan(
            hidePreview.frame.midY,
            sidebarToggle.frame.midY + 30,
            "Preview controls belong in the pane toolbar, not the window titlebar"
        )
        hidePreview.click()
        let showPreview = app.buttons["Show Preview"]
        XCTAssertTrue(showPreview.waitForExistence(timeout: 5))
        showPreview.click()
        XCTAssertTrue(hidePreview.waitForExistence(timeout: 5))

        let favoritesHeader = app.staticTexts["FAVORITES"]
        XCTAssertTrue(favoritesHeader.waitForExistence(timeout: 5))

        sidebarToggle.click()
        XCTAssertTrue(favoritesHeader.waitForNonExistence(timeout: 5))

        sidebarToggle.click()
        XCTAssertTrue(favoritesHeader.waitForExistence(timeout: 5))
    }

    func testResetViewCollapsesSplitPane() throws {
        let sourceRows = rows(named: "Source Item.txt")
        XCTAssertTrue(
            sourceRows.firstMatch.waitForExistence(timeout: 10),
            "The file fixture did not appear after launch"
        )

        let workspacePanes = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "workspace-pane-")
        )
        XCTAssertTrue(waitForElementCount(workspacePanes, toEqual: 1, timeout: 5))
        let initialPane = try XCTUnwrap(existingElements(in: workspacePanes).first)
        let initialWorkspaceFrame = initialPane.frame

        let splitRightButton = app.buttons["Split Right"]
        XCTAssertTrue(splitRightButton.waitForExistence(timeout: 3))
        splitRightButton.click()
        XCTAssertTrue(waitForElementCount(sourceRows, toEqual: 2, timeout: 5))
        XCTAssertTrue(waitForElementCount(workspacePanes, toEqual: 2, timeout: 5))

        let rightSplitPanes = existingElements(in: workspacePanes)
        let rightSplitFrame = unionFrame(of: rightSplitPanes)
        assertSplitFrame(
            rightSplitFrame,
            keepsLeadingAndVerticalEdgesOf: initialWorkspaceFrame
        )
        XCTAssertGreaterThan(
            rightSplitFrame.maxX,
            initialWorkspaceFrame.maxX,
            "A grid should use the space released by the single-pane preview"
        )

        let splitBelowButtons = app.buttons.matching(identifier: "Split Below")
        let rightmostSplitBelow = try XCTUnwrap(
            existingElements(in: splitBelowButtons).max(by: leftToRight)
        )
        rightmostSplitBelow.click()
        XCTAssertTrue(waitForElementCount(sourceRows, toEqual: 3, timeout: 5))
        XCTAssertTrue(waitForElementCount(workspacePanes, toEqual: 3, timeout: 5))

        let mixedGridFrame = unionFrame(of: existingElements(in: workspacePanes))
        XCTAssertEqual(mixedGridFrame.minX, rightSplitFrame.minX, accuracy: 2)
        XCTAssertEqual(mixedGridFrame.minY, rightSplitFrame.minY, accuracy: 2)
        XCTAssertEqual(mixedGridFrame.maxX, rightSplitFrame.maxX, accuracy: 2)
        XCTAssertEqual(mixedGridFrame.maxY, rightSplitFrame.maxY, accuracy: 2)

        let locationMenus = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@", "pane-location-menu")
        )
        XCTAssertTrue(waitForElementCount(locationMenus, toEqual: 3, timeout: 5))
        let globalSearchField = app.descendants(matching: .any)[
            "global-search-text-field"
        ]
        XCTAssertTrue(globalSearchField.waitForExistence(timeout: 5))
        let visibleMenus = existingElements(in: locationMenus).sorted(by: leftToRight)
        let visiblePanes = existingElements(in: workspacePanes).sorted(by: leftToRight)
        XCTAssertEqual(visibleMenus.count, visiblePanes.count)

        for (locationMenu, workspacePane) in zip(visibleMenus, visiblePanes) {
            XCTAssertGreaterThan(
                locationMenu.frame.minY,
                globalSearchField.frame.maxY,
                "Split pane headers must remain below the unified window toolbar"
            )
            XCTAssertGreaterThanOrEqual(
                locationMenu.frame.minX,
                workspacePane.frame.minX,
                "Split pane headers must not slide underneath the sidebar"
            )
            XCTAssertLessThanOrEqual(
                locationMenu.frame.maxX,
                workspacePane.frame.maxX,
                "Split pane headers must remain inside their pane"
            )
        }

        let resetView = app.buttons["Reset View"]
        XCTAssertTrue(resetView.waitForExistence(timeout: 3))
        resetView.click()
        XCTAssertTrue(
            waitForElementCount(rows(named: "Source Item.txt"), toEqual: 1, timeout: 10)
        )
    }

    func testEmptyFolderStateIsCenteredInPane() throws {
        let destinationRow = rows(named: "Destination").firstMatch
        XCTAssertTrue(destinationRow.waitForExistence(timeout: 10))

        let destinationCell = try XCTUnwrap(containingCell(for: destinationRow))
        destinationCell
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .doubleClick()

        let directoryBody = app.descendants(matching: .any)["pane-directory-body"]
        let emptyState = app.descendants(matching: .any)["pane-empty-folder-state"]
        XCTAssertTrue(directoryBody.waitForExistence(timeout: 5))
        XCTAssertTrue(emptyState.waitForExistence(timeout: 5))

        XCTAssertEqual(
            emptyState.frame.midX,
            directoryBody.frame.midX,
            accuracy: max(24, directoryBody.frame.width * 0.05),
            "The empty-folder state should remain horizontally centered"
        )
        XCTAssertEqual(
            emptyState.frame.midY,
            directoryBody.frame.midY,
            accuracy: max(40, directoryBody.frame.height * 0.08),
            "The empty-folder state should remain vertically centered"
        )
    }

    func testSearchControlsStaySingleLineAndLocationAppearsInHeader() throws {
        XCTAssertTrue(
            rows(named: "Source Item.txt").firstMatch.waitForExistence(timeout: 10)
        )

        let locationMenu = app.descendants(matching: .any)["pane-location-menu"]
        let locationPath = app.staticTexts["pane-location-path"]
        let searchField = app.textFields["pane-search-field"]
        XCTAssertTrue(locationMenu.waitForExistence(timeout: 5))
        XCTAssertTrue(locationPath.waitForExistence(timeout: 5))
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        XCTAssertLessThan(
            locationPath.frame.midY,
            searchField.frame.midY,
            "The current path belongs in the folder header above search"
        )
        XCTAssertGreaterThanOrEqual(
            locationPath.frame.height,
            15,
            "The current folder path must remain readable at normal window scale"
        )

        searchField.click()
        searchField.typeText("Source")

        let clearSearch = app.buttons["pane-search-clear-button"]
        XCTAssertTrue(clearSearch.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(
            clearSearch.frame.midX,
            searchField.frame.midX,
            "The clear control must stay at the trailing edge of the search field"
        )

        let searchInLabel = app.staticTexts["Search in"]
        XCTAssertTrue(searchInLabel.waitForExistence(timeout: 5))
        XCTAssertLessThan(
            searchInLabel.frame.height,
            24,
            "The Search in label must remain on one line"
        )
        XCTAssertGreaterThan(
            searchInLabel.frame.width,
            searchInLabel.frame.height * 2,
            "The Search in label must not collapse vertically"
        )

        let matchingRows = rows(named: "Source Item.txt")
        XCTAssertTrue(matchingRows.firstMatch.waitForExistence(timeout: 5))
        let matchingRow = matchingRows.firstMatch
        matchingRow.coordinate(
            withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)
        ).click()
        XCTAssertTrue(
            try XCTUnwrap(containingCell(for: matchingRow)).isSelected,
            "Clicking a search result must visibly select its row"
        )

        clearSearch.click()
        XCTAssertTrue(clearSearch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(searchField.value as? String, "")
    }

    func testFolderCanBeAddedAndRemovedUsingSidebarFavoriteMenu() throws {
        let destinationRows = rows(named: "Destination")
        XCTAssertTrue(destinationRows.firstMatch.waitForExistence(timeout: 10))

        let addFavorite = app.buttons["Add Destination to Favorites"]
        XCTAssertTrue(addFavorite.waitForExistence(timeout: 3))
        addFavorite.click()
        XCTAssertTrue(
            app.buttons["Remove Destination from Favorites"]
                .waitForExistence(timeout: 3)
        )

        let sidebarFavorites = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "sidebar-favorite-"
            )
        )
        XCTAssertTrue(
            waitForElementCount(sidebarFavorites, toEqual: 1, timeout: 5)
        )

        try rightClickRow(sidebarFavorites.firstMatch)
        let removeFavorite = app.menuItems["Remove from Favorites"]
        XCTAssertTrue(removeFavorite.waitForExistence(timeout: 3))
        removeFavorite.click()
        XCTAssertTrue(
            waitForElementCount(sidebarFavorites, toEqual: 0, timeout: 5)
        )

        try rightClickRow(destinationRows.firstMatch)
        XCTAssertTrue(app.menuItems["Add to Favorites"].waitForExistence(timeout: 3))
    }

    func testFileContextMenuOffersSharingAndInformation() throws {
        let sourceRows = rows(named: "Source Item.txt")
        XCTAssertTrue(sourceRows.firstMatch.waitForExistence(timeout: 10))

        try rightClickRow(sourceRows.firstMatch)
        XCTAssertTrue(app.menuItems["Share"].waitForExistence(timeout: 3))

        let getInfo = app.menuItems["Get Info"]
        XCTAssertTrue(getInfo.waitForExistence(timeout: 3))
        getInfo.click()

        let infoPanel = app.descendants(matching: .any)["file-info-panel"]
        XCTAssertTrue(infoPanel.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Source Item.txt"].exists)

        let done = app.buttons["Done"]
        XCTAssertTrue(done.exists)
        done.click()
        XCTAssertTrue(infoPanel.waitForNonExistence(timeout: 5))
    }

    func testFolderInformationCalculatesItsRecursiveSize() throws {
        let folderRow = rows(named: "Global Results").firstMatch
        XCTAssertTrue(folderRow.waitForExistence(timeout: 10))

        try rightClickRow(folderRow)
        let getInfo = app.menuItems["Get Info"]
        XCTAssertTrue(getInfo.waitForExistence(timeout: 3))
        getInfo.click()

        let sizeValue = app.staticTexts["file-info-size-value"]
        XCTAssertTrue(sizeValue.waitForExistence(timeout: 5))
        let expectedSize = try folderContentsByteCount(at: globalSearchFolderURL)
        let expectedText = ByteCountFormatter.string(
            fromByteCount: expectedSize,
            countStyle: .file
        )
        XCTAssertTrue(
            waitForLabel(expectedText, on: sizeValue, timeout: 10),
            "Folder Get Info should replace the placeholder with its recursive size"
        )
    }

    func testFileCanBeRenamedAndDeleteEditsNameField() throws {
        let sourceRow = rows(named: "Source Item.txt").firstMatch
        XCTAssertTrue(sourceRow.waitForExistence(timeout: 10))

        let sourceCell = try XCTUnwrap(containingCell(for: sourceRow))
        sourceCell.click()
        XCTAssertTrue(waitForSelectedStatus(true, on: sourceCell, timeout: 3))

        let fileMenu = app.menuBars.menuBarItems["File"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 3))
        fileMenu.click()

        let renameCommand = app.menuItems["Rename"]
        XCTAssertTrue(renameCommand.waitForExistence(timeout: 3))
        XCTAssertTrue(renameCommand.isEnabled)
        renameCommand.click()

        let nameField = app.textFields["rename-text-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText("Renamed Item.txtx")
        nameField.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(waitForValue("Renamed Item.txt", on: nameField, timeout: 3))
        XCTAssertFalse(app.staticTexts["Move to Trash?"].exists)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: sourceFileURL.path(percentEncoded: false)
            )
        )

        let confirmButton = app.buttons["rename-confirm-button"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForEnabled(confirmButton, timeout: 3))
        confirmButton.click()

        XCTAssertTrue(rows(named: "Renamed Item.txt").firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(rows(named: "Source Item.txt").firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixtureRootURL
                    .appending(path: "Renamed Item.txt")
                    .path(percentEncoded: false)
            )
        )
        let toast = app.descendants(matching: .any)["file-operation-toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertEqual(toast.value as? String, "Renamed")
    }

    func testNewFolderIsSelectedAndImmediatelyReadyForNaming() throws {
        XCTAssertTrue(
            rows(named: "Source Item.txt").firstMatch.waitForExistence(timeout: 10)
        )

        let newFolderButton = app.buttons["New Folder"]
        XCTAssertTrue(newFolderButton.waitForExistence(timeout: 5))
        newFolderButton.click()

        let nameField = app.textFields["rename-text-field"]
        XCTAssertTrue(
            nameField.waitForExistence(timeout: 5),
            "Creating a folder should immediately enter naming mode"
        )

        // Do not click the field: typing successfully here proves that the
        // automatic naming field owns keyboard focus and selected the default name.
        nameField.typeKey("x", modifierFlags: [])
        XCTAssertTrue(
            waitForValue("x", on: nameField, timeout: 3),
            "The naming field contained \(String(describing: nameField.value))"
        )
        nameField.typeKey(.return, modifierFlags: [])

        let renamedRow = rows(named: "x").firstMatch
        XCTAssertTrue(renamedRow.waitForExistence(timeout: 10))
        let renamedCell = try XCTUnwrap(containingCell(for: renamedRow))
        XCTAssertTrue(
            waitForSelectedStatus(true, on: renamedCell, timeout: 5),
            "The newly created and named folder should remain the active row"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixtureRootURL
                    .appending(path: "x", directoryHint: .isDirectory)
                    .path(percentEncoded: false)
            )
        )
    }

    func testCancelingNewFolderNamingCreatesNothing() {
        XCTAssertTrue(
            rows(named: "Source Item.txt").firstMatch.waitForExistence(timeout: 10)
        )
        let contentsBefore = fixtureContents()

        let newFolderButton = app.buttons["New Folder"]
        XCTAssertTrue(newFolderButton.waitForExistence(timeout: 5))
        newFolderButton.click()

        let nameField = app.textFields["rename-text-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        let proposedName = nameField.value as? String
        XCTAssertNotNil(proposedName)

        let cancelButton = app.sheets.firstMatch.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 3))
        cancelButton.click()

        XCTAssertTrue(nameField.waitForNonExistence(timeout: 3))
        XCTAssertEqual(fixtureContents(), contentsBefore)
        if let proposedName {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: fixtureRootURL.appending(
                        path: proposedName,
                        directoryHint: .isDirectory
                    ).path()
                )
            )
            XCTAssertFalse(rows(named: proposedName).firstMatch.exists)
        }
    }

    func testShiftSelectionAndDeleteMoveEverySelectedItemAfterConfirmation() throws {
        let destinationRow = rows(named: "Destination").firstMatch
        let globalResultsRow = rows(named: "Global Results").firstMatch
        let sourceRow = rows(named: "Source Item.txt").firstMatch
        XCTAssertTrue(destinationRow.waitForExistence(timeout: 10))
        XCTAssertTrue(globalResultsRow.waitForExistence(timeout: 5))
        XCTAssertTrue(sourceRow.waitForExistence(timeout: 5))

        let destinationCell = try XCTUnwrap(containingCell(for: destinationRow))
        let globalResultsCell = try XCTUnwrap(containingCell(for: globalResultsRow))
        let sourceCell = try XCTUnwrap(containingCell(for: sourceRow))
        destinationCell.click()
        XCUIElement.perform(withKeyModifiers: [.shift]) {
            globalResultsCell.click()
        }

        XCTAssertTrue(waitForSelectedStatus(true, on: destinationCell, timeout: 3))
        XCTAssertTrue(waitForSelectedStatus(true, on: globalResultsCell, timeout: 3))
        XCTAssertTrue(waitForSelectedStatus(false, on: sourceCell, timeout: 3))

        globalResultsCell.typeKey(.delete, modifierFlags: [])
        let confirmation = app.staticTexts["Move 2 Items to Trash?"]
        XCTAssertTrue(
            confirmation.waitForExistence(timeout: 5),
            "Delete should request confirmation for both selected items"
        )

        app.sheets.firstMatch.buttons["Cancel"].click()
        XCTAssertTrue(destinationRow.waitForExistence(timeout: 3))
        XCTAssertTrue(globalResultsRow.waitForExistence(timeout: 3))
        XCTAssertTrue(sourceRow.waitForExistence(timeout: 3))

        globalResultsCell.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        app.sheets.firstMatch.buttons["Move to Trash"].click()

        XCTAssertTrue(destinationRow.waitForNonExistence(timeout: 10))
        XCTAssertTrue(globalResultsRow.waitForNonExistence(timeout: 10))
        XCTAssertTrue(sourceRow.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["pane-directory-body"].exists)
        XCTAssertEqual(fixtureContents(), ["Source Item.txt"])
    }

    func testRowTrashButtonRequiresConfirmation() {
        let sourceRow = rows(named: "Source Item.txt").firstMatch
        XCTAssertTrue(sourceRow.waitForExistence(timeout: 10))

        let trashButton = app.buttons["trash-item-Source Item.txt"]
        XCTAssertTrue(trashButton.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(
            trashButton.frame.minX,
            sourceRow.frame.midX,
            "The Trash shortcut should stay at the trailing side of the row"
        )
        trashButton.click()

        let confirmation = app.staticTexts["Move to Trash?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.sheets.firstMatch.buttons["Move to Trash"]
                .waitForExistence(timeout: 3)
        )

        let cancelButton = app.sheets.firstMatch.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 3))
        cancelButton.click()

        XCTAssertTrue(sourceRow.waitForExistence(timeout: 3))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: sourceFileURL.path(percentEncoded: false)
            ),
            "Cancel must preserve the source. Fixture contents: \(fixtureContents())"
        )
    }

    func testMountedUSBVolumeAppearsInLocationsAndCanBeOpened() throws {
        XCTAssertTrue(rows(named: "Source Item.txt").firstMatch.waitForExistence(timeout: 10))
        let identifier = "sidebar-location-\(mountedVolumeURL.path(percentEncoded: false))"
        let mountedVolume = element(withIdentifier: identifier)

        XCTAssertTrue(
            mountedVolume.waitForExistence(timeout: 5),
            "A mounted Type-C/USB filesystem volume must appear in Locations"
        )
        XCTAssertTrue(mountedVolume.label.contains(mountedVolumeURL.lastPathComponent))
        mountedVolume.click()

        let mountedVolumeCell = try XCTUnwrap(containingCell(for: mountedVolume))
        XCTAssertTrue(
            waitForSelectedStatus(true, on: mountedVolumeCell, timeout: 5),
            "A selected mounted volume must use the same List selection state as other sidebar locations"
        )

        let locationPaths = app.staticTexts.matching(
            NSPredicate(format: "identifier == %@", "pane-location-path")
        )
        XCTAssertTrue(locationPaths.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForLabelSuffix(
                mountedVolumeURL.path(percentEncoded: false),
                on: locationPaths.firstMatch,
                timeout: 5
            ),
            "Expected mounted path \(mountedVolumeURL.path(percentEncoded: false)); actual label/value: \(locationPaths.firstMatch.label) / \(String(describing: locationPaths.firstMatch.value))"
        )
    }

    func testMountedUSBVolumeCanBeEjectedWithoutOpeningIt() {
        XCTAssertTrue(rows(named: "Source Item.txt").firstMatch.waitForExistence(timeout: 10))
        let rowIdentifier = "sidebar-location-\(mountedVolumeURL.path(percentEncoded: false))"
        let ejectIdentifier = "sidebar-eject-\(mountedVolumeURL.path(percentEncoded: false))"
        let mountedVolume = element(withIdentifier: rowIdentifier)
        let ejectButton = app.buttons.matching(
            NSPredicate(format: "identifier == %@", ejectIdentifier)
        ).firstMatch
        let locationPath = app.staticTexts["pane-location-path"]

        XCTAssertTrue(mountedVolume.waitForExistence(timeout: 5))
        XCTAssertTrue(ejectButton.waitForExistence(timeout: 5))
        XCTAssertTrue(locationPath.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForLabelSuffix(
                fixtureRootURL.path(percentEncoded: false),
                on: locationPath,
                timeout: 5
            ),
            "Expected fixture path \(fixtureRootURL.path(percentEncoded: false)); actual label/value: \(locationPath.label) / \(String(describing: locationPath.value))"
        )

        ejectButton.click()

        XCTAssertTrue(mountedVolume.waitForNonExistence(timeout: 5))
        XCTAssertTrue(
            waitForLabelSuffix(
                fixtureRootURL.path(percentEncoded: false),
                on: locationPath,
                timeout: 5
            ),
            "Clicking the eject control must not navigate the active pane to the disk"
        )
    }

    func testFolderCanBeHiddenAndRecovered() throws {
        let destinationRows = rows(named: "Destination")
        XCTAssertTrue(destinationRows.firstMatch.waitForExistence(timeout: 10))

        try rightClickRow(destinationRows.firstMatch)
        let hideFolder = app.menuItems["Hide Folder"]
        XCTAssertTrue(hideFolder.waitForExistence(timeout: 3))
        hideFolder.click()

        XCTAssertTrue(waitForElementCount(destinationRows, toEqual: 0, timeout: 5))
        XCTAssertEqual(
            try destinationFolderURL.resourceValues(forKeys: [.isHiddenKey]).isHidden,
            true
        )

        let showHiddenItems = app.buttons["Show Hidden Items"]
        XCTAssertTrue(showHiddenItems.waitForExistence(timeout: 3))
        showHiddenItems.click()
        XCTAssertTrue(destinationRows.firstMatch.waitForExistence(timeout: 5))

        try rightClickRow(destinationRows.firstMatch)
        let unhideFolder = app.menuItems["Unhide Folder"]
        XCTAssertTrue(unhideFolder.waitForExistence(timeout: 3))
        unhideFolder.click()

        XCTAssertTrue(
            waitForHiddenStatus(false, at: destinationFolderURL, timeout: 5)
        )
        let hideHiddenItems = app.buttons["Hide Hidden Items"]
        XCTAssertTrue(hideHiddenItems.waitForExistence(timeout: 3))
        hideHiddenItems.click()
        XCTAssertTrue(destinationRows.firstMatch.waitForExistence(timeout: 5))
    }

    func testGlobalSearchSupportsArrowSelectionAndReturnReveal() throws {
        XCTAssertTrue(
            rows(named: "Source Item.txt").firstMatch.waitForExistence(timeout: 10)
        )

        let globalSearchField = app.descendants(matching: .any)[
            "global-search-text-field"
        ]
        let paneSearchField = app.textFields["pane-search-field"]
        XCTAssertTrue(globalSearchField.waitForExistence(timeout: 5))
        XCTAssertTrue(paneSearchField.waitForExistence(timeout: 5))
        XCTAssertLessThan(
            globalSearchField.frame.midY,
            paneSearchField.frame.midY,
            "The computer-wide search field belongs in the window toolbar"
        )

        globalSearchField.click()
        globalSearchField.typeText("Global Needle")

        let resultRows = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "global-search-result-"
            )
        )
        XCTAssertTrue(waitForElementCount(resultRows, toEqual: 2, timeout: 10))

        let visibleResults = existingElements(in: resultRows).sorted {
            $0.frame.minY < $1.frame.minY
        }
        let firstResult = try XCTUnwrap(visibleResults.first)
        let secondResult = try XCTUnwrap(visibleResults.last)
        XCTAssertEqual(firstResult.value as? String, "Selected")

        globalSearchField.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(
            waitForValue("Selected", on: secondResult, timeout: 3),
            "Down Arrow must move the active global-search result"
        )
        let selectedResultName = secondResult.label
        XCTAssertFalse(selectedResultName.isEmpty)

        globalSearchField.typeKey(.return, modifierFlags: [])
        let revealedRows = rows(named: selectedResultName)
        XCTAssertTrue(revealedRows.firstMatch.waitForExistence(timeout: 10))
        let revealedRow = revealedRows.firstMatch
        let revealedCell = try XCTUnwrap(containingCell(for: revealedRow))
        XCTAssertTrue(
            waitForSelectedStatus(true, on: revealedCell, timeout: 5),
            "Return must reveal and select the global-search result in its folder"
        )
    }

    func testGlobalSearchOffersContentModes() {
        XCTAssertTrue(
            rows(named: "Source Item.txt").firstMatch.waitForExistence(timeout: 10)
        )

        let globalSearchField = app.descendants(matching: .any)[
            "global-search-text-field"
        ]
        XCTAssertTrue(globalSearchField.waitForExistence(timeout: 5))
        globalSearchField.click()
        globalSearchField.typeText("grep-only-phrase")

        let searchScope = app.radioGroups["global-search-scope-picker"]
        XCTAssertTrue(searchScope.waitForExistence(timeout: 5))
        let contents = searchScope.radioButtons["Contents"]
        XCTAssertTrue(contents.waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.staticTexts["Search In"].exists,
            "The hidden picker label must not collapse into a vertical text column"
        )
        contents.click()

        XCTAssertTrue(
            app.staticTexts["Global Needle Alpha.txt"]
                .waitForExistence(timeout: 10),
            "Content search must surface a file whose name does not contain the query"
        )
        let contentModes = app.radioGroups[
            "global-search-content-mode-picker"
        ]
        XCTAssertTrue(contentModes.waitForExistence(timeout: 5))
        XCTAssertTrue(contentModes.radioButtons["Plain"].exists)
        XCTAssertTrue(contentModes.radioButtons["Regex"].exists)
        XCTAssertTrue(contentModes.radioButtons["Fuzzy"].exists)
    }

    func testThemePickerAndTerminalChooserAreAvailableFromToolbars() {
        XCTAssertTrue(
            rows(named: "Source Item.txt").firstMatch.waitForExistence(timeout: 10)
        )

        let themePicker = app.buttons["theme-picker-button"]
        XCTAssertTrue(themePicker.waitForExistence(timeout: 5))
        let globalSearchField = app.descendants(matching: .any)[
            "global-search-text-field"
        ]
        XCTAssertTrue(globalSearchField.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(
            themePicker.frame.minX,
            globalSearchField.frame.maxX,
            "The theme button must be a separate toolbar item to the right of search"
        )
        themePicker.click()

        let midnightTheme = app.buttons["theme-choice-midnight"]
        XCTAssertTrue(midnightTheme.waitForExistence(timeout: 5))
        midnightTheme.click()
        XCTAssertTrue(midnightTheme.waitForNonExistence(timeout: 5))

        let terminalButton = app.buttons["pane-terminal-button"]
        XCTAssertTrue(terminalButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForEnabled(terminalButton, timeout: 5))
        terminalButton.click()
        XCTAssertTrue(
            app.staticTexts["Choose an installed terminal for this folder."]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.checkBoxes["remember-terminal-choice"].exists)
    }

    func testNearbyTransferPickerAndPairingFlow() throws {
        let sourceRow = rows(named: "Source Item.txt").firstMatch
        XCTAssertTrue(sourceRow.waitForExistence(timeout: 10))
        sourceRow.coordinate(
            withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)
        ).click()
        XCTAssertTrue(try XCTUnwrap(containingCell(for: sourceRow)).isSelected)

        let nearbyButton = app.buttons["nearby-transfer-toolbar-button"]
        XCTAssertTrue(nearbyButton.waitForExistence(timeout: 5))
        nearbyButton.click()

        XCTAssertTrue(
            app.descendants(matching: .any)["nearby-device-picker"]
                .waitForExistence(timeout: 5)
        )
        let peer = app.buttons[
            "nearby-peer-8a1660d1-44d5-4b14-bb7b-a4c73916c671"
        ]
        XCTAssertTrue(peer.waitForExistence(timeout: 5))
        XCTAssertTrue(peer.isEnabled)
        peer.click()

        let pairingCode = app.staticTexts["nearby-pairing-code"]
        XCTAssertTrue(pairingCode.waitForExistence(timeout: 5))
        XCTAssertTrue(pairingCode.label.contains("4827"))
        let confirm = app.buttons["nearby-pairing-confirm-button"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()

        let toast = app.descendants(matching: .any)["file-operation-toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertEqual(toast.value as? String, "Sent to UI Test Mac")
    }

    private var sourceFileURL: URL {
        fixtureRootURL.appending(path: "Source Item.txt", directoryHint: .notDirectory)
    }

    private var destinationFolderURL: URL {
        fixtureRootURL.appending(path: "Destination", directoryHint: .isDirectory)
    }

    private var copiedFileURL: URL {
        destinationFolderURL.appending(path: "Source Item.txt", directoryHint: .notDirectory)
    }

    private var globalSearchFolderURL: URL {
        fixtureRootURL.appending(path: "Global Results", directoryHint: .isDirectory)
    }

    private var globalSearchAlphaURL: URL {
        globalSearchFolderURL.appending(
            path: "Global Needle Alpha.txt",
            directoryHint: .notDirectory
        )
    }

    private var globalSearchBetaURL: URL {
        globalSearchFolderURL.appending(
            path: "Global Needle Beta.txt",
            directoryHint: .notDirectory
        )
    }

    private func rows(named name: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier ENDSWITH %@", "-\(name)")
        )
    }

    private func element(withIdentifier identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@", identifier)
        ).firstMatch
    }

    private func existingElements(in query: XCUIElementQuery) -> [XCUIElement] {
        (0..<query.count)
            .map(query.element(boundBy:))
            .filter(\.exists)
    }

    private func containingCell(for element: XCUIElement) -> XCUIElement? {
        let point = CGPoint(x: element.frame.midX, y: element.frame.midY)
        return existingElements(in: app.cells)
            .filter { $0.frame.contains(point) }
            .min { $0.frame.width < $1.frame.width }
    }

    private func leftToRight(_ lhs: XCUIElement, _ rhs: XCUIElement) -> Bool {
        lhs.frame.minX < rhs.frame.minX
    }

    private func unionFrame(of elements: [XCUIElement]) -> CGRect {
        guard let first = elements.first else { return .null }
        return elements.dropFirst().reduce(first.frame) { frame, element in
            frame.union(element.frame)
        }
    }

    private func assertSplitFrame(
        _ splitFrame: CGRect,
        keepsLeadingAndVerticalEdgesOf originalFrame: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            splitFrame.minX,
            originalFrame.minX,
            accuracy: 2,
            "Splitting must not move panes underneath or away from the sidebar",
            file: file,
            line: line
        )
        XCTAssertEqual(
            splitFrame.minY,
            originalFrame.minY,
            accuracy: 2,
            "Splitting must not move panes underneath or away from the toolbar",
            file: file,
            line: line
        )
        XCTAssertEqual(
            splitFrame.maxY,
            originalFrame.maxY,
            accuracy: 2,
            "Splitting must keep the workspace's bottom edge stable",
            file: file,
            line: line
        )
    }

    private func waitForElementCount(
        _ query: XCUIElementQuery,
        toEqual expectedCount: Int,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate { object, _ in
            (object as? XCUIElementQuery)?.count == expectedCount
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: query)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForHiddenStatus(
        _ expectedStatus: Bool,
        at url: URL,
        timeout: TimeInterval
    ) -> Bool {
        let path = url.path(percentEncoded: false)
        let predicate = NSPredicate { object, _ in
            guard let path = object as? NSString else { return false }
            let refreshedURL = URL(
                filePath: path as String,
                directoryHint: .isDirectory
            )
            return (try? refreshedURL.resourceValues(forKeys: [.isHiddenKey]).isHidden)
                == expectedStatus
        }
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: path as NSString
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForValue(
        _ expectedValue: String,
        on element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "value == %@", expectedValue)
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForLabel(
        _ expectedLabel: String,
        on element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "label == %@", expectedLabel)
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForLabelSuffix(
        _ suffix: String,
        on element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let normalizedSuffix = suffix.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            let displayedValues = [element.label, element.value as? String]
                .compactMap { $0 }

            return displayedValues.contains { displayedValue in
                let normalizedValue = displayedValue.trimmingCharacters(
                    in: CharacterSet(charactersIn: "/")
                )
                if normalizedValue.hasSuffix(normalizedSuffix) {
                    return true
                }

                guard normalizedValue.hasPrefix("~") else { return false }
                let homeRelativeValue = String(normalizedValue.dropFirst())
                return normalizedSuffix.hasSuffix(homeRelativeValue)
            }
        }
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForSelectedStatus(
        _ expectedStatus: Bool,
        on element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate { object, _ in
            (object as? XCUIElement)?.isSelected == expectedStatus
        }
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForEnabled(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate { object, _ in
            (object as? XCUIElement)?.isEnabled == true
        }
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func rightClickRow(_ row: XCUIElement) throws {
        let cell = try XCTUnwrap(containingCell(for: row))
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .rightClick()
    }

    private func destinationContents() -> [String] {
        (try? FileManager.default.contentsOfDirectory(
            at: destinationFolderURL,
            includingPropertiesForKeys: nil
        ).map(\.lastPathComponent).sorted()) ?? []
    }

    private func fixtureContents() -> [String] {
        (try? FileManager.default.contentsOfDirectory(
            at: fixtureRootURL,
            includingPropertiesForKeys: nil
        ).map(\.lastPathComponent).sorted()) ?? []
    }

    private func folderContentsByteCount(at directoryURL: URL) throws -> Int64 {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey]
        )
        return try urls.reduce(into: 0) { total, url in
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            total += Int64(size)
        }
    }
}
