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
        try Data("Finally Explorer cross-pane drag regression fixture.".utf8)
            .write(to: sourceFileURL, options: .atomic)

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
        XCTAssertTrue(resetView.waitForNonExistence(timeout: 10))
        XCTAssertTrue(
            waitForElementCount(rows(named: "Source Item.txt"), toEqual: 1, timeout: 10)
        )
    }

    func testFolderCanBeAddedAndRemovedFromFavorites() throws {
        let destinationRows = rows(named: "Destination")
        XCTAssertTrue(destinationRows.firstMatch.waitForExistence(timeout: 10))

        try rightClickRow(destinationRows.firstMatch)
        let addFavorite = app.menuItems["Add to Favorites"]
        XCTAssertTrue(addFavorite.waitForExistence(timeout: 3))
        addFavorite.click()

        try rightClickRow(destinationRows.firstMatch)
        let removeFavorite = app.menuItems["Remove from Favorites"]
        XCTAssertTrue(removeFavorite.waitForExistence(timeout: 3))
        removeFavorite.click()

        try rightClickRow(destinationRows.firstMatch)
        XCTAssertTrue(app.menuItems["Add to Favorites"].waitForExistence(timeout: 3))
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

    private var sourceFileURL: URL {
        fixtureRootURL.appending(path: "Source Item.txt", directoryHint: .notDirectory)
    }

    private var destinationFolderURL: URL {
        fixtureRootURL.appending(path: "Destination", directoryHint: .isDirectory)
    }

    private var copiedFileURL: URL {
        destinationFolderURL.appending(path: "Source Item.txt", directoryHint: .notDirectory)
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
