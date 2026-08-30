//
//  FinallyExplorerUITests.swift
//  FinallyExplorerUITests
//

import XCTest

final class FinallyExplorerUITests: XCTestCase {
    private var app: XCUIApplication!
    private var fixtureRootURL: URL!
    private var defaultsSuiteName: String!

    override func setUpWithError() throws {
        continueAfterFailure = false

        fixtureRootURL = FileManager.default.temporaryDirectory
            .appending(
                path: "FinallyExplorerUITests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defaultsSuiteName = "FinallyExplorer.UITests.\(UUID().uuidString)"

        try FileManager.default.createDirectory(
            at: fixtureRootURL,
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
            "FINALLY_EXPLORER_UI_DEFAULTS_SUITE": defaultsSuiteName,
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

        app = nil
        fixtureRootURL = nil
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
        XCTAssertFalse(FileManager.default.fileExists(atPath: copiedFileURL.path()))

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

    func testResetViewCollapsesSplitPane() {
        let sourceRows = rows(named: "Source Item.txt")
        XCTAssertTrue(sourceRows.firstMatch.waitForExistence(timeout: 10))

        let splitRightButton = app.buttons["Split Right"]
        XCTAssertTrue(splitRightButton.waitForExistence(timeout: 3))
        splitRightButton.click()
        XCTAssertTrue(waitForElementCount(sourceRows, toEqual: 2, timeout: 5))

        let resetView = app.buttons["Reset View"]
        XCTAssertTrue(resetView.waitForExistence(timeout: 3))
        resetView.click()
        XCTAssertTrue(
            waitForElementCount(rows(named: "Source Item.txt"), toEqual: 1, timeout: 10)
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

    func testGlobalSearchOffersFFFGrepModes() {
        XCTAssertTrue(
            rows(named: "Source Item.txt").firstMatch.waitForExistence(timeout: 10)
        )

        let globalSearchField = app.descendants(matching: .any)[
            "global-search-text-field"
        ]
        XCTAssertTrue(globalSearchField.waitForExistence(timeout: 5))
        globalSearchField.click()
        globalSearchField.typeText("grep-only-phrase")

        let contents = app.descendants(matching: .any)["Contents"]
        XCTAssertTrue(contents.waitForExistence(timeout: 5))
        contents.click()

        XCTAssertTrue(
            app.staticTexts["Global Needle Alpha.txt"]
                .waitForExistence(timeout: 10),
            "FFF live grep must surface a file whose name does not contain the query"
        )
        XCTAssertTrue(app.descendants(matching: .any)["Plain"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Regex"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Fuzzy"].exists)
    }

    func testThemePickerAndTerminalChooserAreAvailableFromToolbars() {
        XCTAssertTrue(
            rows(named: "Source Item.txt").firstMatch.waitForExistence(timeout: 10)
        )

        let themePicker = app.buttons["theme-picker-button"]
        XCTAssertTrue(themePicker.waitForExistence(timeout: 5))
        themePicker.click()

        let midnightTheme = app.buttons["theme-choice-midnight"]
        XCTAssertTrue(midnightTheme.waitForExistence(timeout: 5))
        midnightTheme.click()
        XCTAssertTrue(midnightTheme.waitForNonExistence(timeout: 5))

        let terminalButton = app.buttons["pane-terminal-button"]
        XCTAssertTrue(terminalButton.waitForExistence(timeout: 5))
        terminalButton.click()
        XCTAssertTrue(
            app.staticTexts["Choose an installed terminal for this folder."]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.checkBoxes["remember-terminal-choice"].exists)
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
        let path = url.path()
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
}
