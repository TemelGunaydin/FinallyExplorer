//
//  FinallyExplorerUITests.swift
//  FinallyExplorerUITests
//

import XCTest
import CoreGraphics
import CoreText
import ImageIO
import PDFKit
import UniformTypeIdentifiers

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
        try Data().write(to: globalSearchCompactNameURL, options: .atomic)
        try Data().write(to: globalSearchDistractorURL, options: .atomic)

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

    override func record(_ issue: XCTIssue) {
        if issue.type == .assertionFailure, let app {
            print("UI failure hierarchy: \(app.windows.firstMatch.debugDescription)")
        }
        super.record(issue)
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
        let copyCommand = fileContextMenuButton(named: "Copy")
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
        let pasteCommand = fileContextMenuButton(named: "Paste Into Folder")
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

    func testCrossPaneDropIntoPopulatedFolderBackgroundAndFileRow() throws {
        app.terminate()
        let existingURL = destinationFolderURL.appending(path: "Existing.txt")
        let secondSourceURL = fixtureRootURL.appending(path: "Another Source.json")
        try Data("Keep this destination file".utf8).write(to: existingURL)
        try Data("{\"copied\":true}".utf8).write(to: secondSourceURL)
        app.launch()
        XCTAssertTrue(rows(named: "Source Item.txt").firstMatch.waitForExistence(timeout: 10))
        app.buttons["Split Right"].click()
        XCTAssertTrue(waitForElementCount(rows(named: "Destination"), toEqual: 2, timeout: 5))
        let rightFolder = try XCTUnwrap(existingElements(in: rows(named: "Destination"))
            .sorted(by: leftToRight).last)
        // A cell also contains favorite/trash buttons. Open its row background,
        // rather than letting XCTest choose an arbitrary hittable descendant.
        try XCTUnwrap(containingCell(for: rightFolder))
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .doubleClick()
        XCTAssertTrue(rows(named: "Existing.txt").firstMatch.waitForExistence(timeout: 5))

        let bodies = app.descendants(matching: .any).matching(identifier: "pane-directory-body")
        let rightBody = try XCTUnwrap(existingElements(in: bodies).sorted(by: leftToRight).last)
        let source = try XCTUnwrap(containingCell(for: rows(named: "Source Item.txt").firstMatch))
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            .click(forDuration: 0.5,
                   thenDragTo: rightBody.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.85)),
                   withVelocity: .slow, thenHoldForDuration: 0.8)
        XCTAssertTrue(waitForElementCount(rows(named: "Source Item.txt"), toEqual: 2, timeout: 10))
        XCTAssertEqual(try Data(contentsOf: copiedFileURL), try Data(contentsOf: sourceFileURL))

        let secondSource = try XCTUnwrap(containingCell(for: rows(named: "Another Source.json").firstMatch))
        let existingRow = try XCTUnwrap(containingCell(for: rows(named: "Existing.txt").firstMatch))
        secondSource.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            .click(forDuration: 0.5,
                   thenDragTo: existingRow.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)),
                   withVelocity: .slow, thenHoldForDuration: 0.8)
        XCTAssertTrue(waitForElementCount(rows(named: "Another Source.json"), toEqual: 2, timeout: 10))
        XCTAssertEqual(
            try Data(contentsOf: destinationFolderURL.appending(path: "Another Source.json")),
            try Data(contentsOf: secondSourceURL)
        )
        XCTAssertEqual(try Data(contentsOf: existingURL), Data("Keep this destination file".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondSourceURL.path))
    }

    func testCodeAndJSONFilesShowReadablePreview() throws {
        app.terminate()
        let swiftText = "struct PreviewFixture { let message = \"Hello Swift\" }"
        let jsonText = "{\"previewMessage\": \"Hello JSON\", \"count\": 42}"
        try Data(swiftText.utf8).write(to: fixtureRootURL.appending(path: "Preview.swift"))
        try Data(jsonText.utf8).write(to: fixtureRootURL.appending(path: "Preview.json"))
        app.launch()
        let swiftRow = rows(named: "Preview.swift").firstMatch
        XCTAssertTrue(swiftRow.waitForExistence(timeout: 10))
        swiftRow.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).click()
        let preview = app.textViews["text-file-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(swiftText, on: preview, timeout: 5))

        rows(named: "Preview.json").firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).click()
        XCTAssertTrue(waitForValue(jsonText, on: preview, timeout: 5))
        XCTAssertGreaterThan(preview.frame.width, 100)
        XCTAssertGreaterThan(preview.frame.height, 0)
        // SwiftUI's inspector identifier can replace the representable's outer
        // scroll identifier. Locate the viewport by its actual text editor.
        let previewViewport = app.scrollViews.containing(
            .textView, identifier: "text-file-preview"
        ).firstMatch
        XCTAssertTrue(previewViewport.exists)
        XCTAssertGreaterThan(previewViewport.frame.height, 100)
        recordWindowHierarchy("JSON preview and developer file icons")
    }

    func testAISettingsCanDisableSmartRenameAndPersist() throws {
        let settingsButton = app.buttons["window-settings-button"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.click()
        let enabledToggle = app.descendants(matching: .any)["ai-settings-enabled-toggle"]
        XCTAssertTrue(enabledToggle.waitForExistence(timeout: 5))
        enabledToggle.click()
        let settingsWindow = app.windows.containing(
            .any, identifier: "ai-settings-view"
        ).firstMatch
        XCTAssertTrue(settingsWindow.exists)
        recordWindowHierarchy("AI settings")
        settingsWindow.buttons[XCUIIdentifierCloseWindow].click()

        let sourceRow = rows(named: "Source Item.txt").firstMatch
        // Exercise the native menu entry as well as the dedicated right-click
        // regressions, while checking that the preference survives relaunch.
        let sourceCell = try XCTUnwrap(containingCell(for: sourceRow))
        sourceCell.click()
        app.menuBars.menuBarItems["File"].click()
        app.menuItems["Rename"].click()
        XCTAssertTrue(app.textFields["rename-text-field"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["smart-rename-disabled"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["smart-rename-suggest-button"].exists)
        app.buttons["Cancel"].click()
        app.terminate()
        app.launch()
        XCTAssertTrue(rows(named: "Source Item.txt").firstMatch.waitForExistence(timeout: 10))
        let relaunchedCell = try XCTUnwrap(containingCell(for: rows(named: "Source Item.txt").firstMatch))
        relaunchedCell.click()
        app.menuBars.menuBarItems["File"].click()
        app.menuItems["Rename"].click()
        XCTAssertTrue(app.textFields["rename-text-field"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["smart-rename-disabled"].waitForExistence(timeout: 5))
    }

    func testContextMenuRenameWorksAfterClosingSettings() throws {
        app.buttons["window-settings-button"].click()
        let toggle = element(withIdentifier: "ai-settings-enabled-toggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()
        let settingsWindow = app.windows.containing(.any, identifier: "ai-settings-view").firstMatch
        XCTAssertTrue(settingsWindow.exists)
        settingsWindow.buttons[XCUIIdentifierCloseWindow].click()
        try assertContextMenuPresentsRename()
        XCTAssertTrue(app.staticTexts["smart-rename-disabled"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].click()
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFileURL.path))
    }

    func testContextMenuRenameWorksWithoutSettings() throws {
        try assertContextMenuPresentsRename()
        app.buttons["Cancel"].click()
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFileURL.path))
    }

    func testContextMenuRenameWorksAtTrailingEdge() throws {
        try assertContextMenuPresentsRename(horizontalPosition: 0.92)
        app.buttons["Cancel"].click()
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFileURL.path))
    }

    private func assertContextMenuPresentsRename(horizontalPosition: CGFloat = 0.5) throws {
        let sourceRow = rows(named: "Source Item.txt").firstMatch
        XCTAssertTrue(sourceRow.waitForExistence(timeout: 10))
        try rightClickRow(sourceRow)
        let rename = fileContextMenuButton(named: "Rename")
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        XCTAssertTrue(rename.isEnabled)
        rename.coordinate(withNormalizedOffset: CGVector(dx: horizontalPosition, dy: 0.5)).click()
        XCTAssertTrue(app.textFields["rename-text-field"].waitForExistence(timeout: 5))
        XCTAssertFalse(element(withIdentifier: "file-item-context-menu").exists)
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

    func testSidebarResizeStaysBoundedAfterDraggingAndToggling() throws {
        XCTAssertTrue(rows(named: "Source Item.txt").firstMatch.waitForExistence(timeout: 10))
        let sidebar = app.descendants(matching: .any)["explorer-sidebar"].firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        let sidebarViewport = app.scrollViews.containing(
            .outline, identifier: "explorer-sidebar"
        ).firstMatch
        XCTAssertTrue(sidebarViewport.exists)

        func dragSidebarDivider(by delta: CGFloat) throws {
            let divider = try XCTUnwrap(
                app.descendants(matching: .splitter).allElementsBoundByIndex
                    .filter { $0.isHittable && $0.frame.height > $0.frame.width }
                    .min { $0.frame.minX < $1.frame.minX }
            )
            let start = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let endX = max(app.windows.firstMatch.frame.minX + 4, divider.frame.midX + delta)
            start.click(
                forDuration: 0.2,
                thenDragTo: start.withOffset(CGVector(dx: endX - divider.frame.midX, dy: 0)),
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
        }

        func expectSidebarWidth(in range: ClosedRange<CGFloat>) {
            let expectation = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    // NSOutlineView extends one pixel outside each clip edge;
                    // the visible sidebar column is its scroll viewport.
                    sidebarViewport.exists && range.contains(sidebarViewport.frame.width)
                },
                object: sidebarViewport
            )
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
        }

        expectSidebarWidth(in: 209...281)
        try dragSidebarDivider(by: 450)
        expectSidebarWidth(in: 279...281)
        try dragSidebarDivider(by: -450)
        expectSidebarWidth(in: 209...211)

        let toggle = app.buttons["window-sidebar-toggle"]
        toggle.click()
        XCTAssertTrue(app.staticTexts["FAVORITES"].waitForNonExistence(timeout: 5))
        toggle.click()
        XCTAssertTrue(app.staticTexts["FAVORITES"].waitForExistence(timeout: 5))
        expectSidebarWidth(in: 209...281)

        app.buttons["Split Right"].click()
        XCTAssertTrue(waitForElementCount(rows(named: "Source Item.txt"), toEqual: 2, timeout: 5))
        try dragSidebarDivider(by: 450)
        expectSidebarWidth(in: 279...281)

        recordWindowHierarchy("Sidebar remains bounded with a split workspace")
    }

    func testWindowUsesLargerCustomTrafficLightControls() {
        XCTAssertTrue(
            rows(named: "Source Item.txt").firstMatch.waitForExistence(timeout: 10)
        )

        let closeButton = app.buttons["window-close-button"]
        let minimizeButton = app.buttons["window-minimize-button"]
        let fullscreenButton = app.buttons["window-fullscreen-button"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        XCTAssertTrue(minimizeButton.waitForExistence(timeout: 5))
        XCTAssertTrue(fullscreenButton.waitForExistence(timeout: 5))

        XCTAssertGreaterThanOrEqual(closeButton.frame.width, 24)
        XCTAssertGreaterThanOrEqual(closeButton.frame.height, 28)
        XCTAssertLessThan(closeButton.frame.maxX, minimizeButton.frame.minX + 1)
        XCTAssertLessThan(minimizeButton.frame.maxX, fullscreenButton.frame.minX + 1)
        XCTAssertEqual(
            closeButton.frame.midY,
            fullscreenButton.frame.midY,
            accuracy: 2
        )
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
        XCTAssertTrue(waitForElementCount(workspacePanes, toEqual: 2, timeout: 5))
        XCTAssertTrue(waitForElementCount(sourceRows, toEqual: 2, timeout: 5))

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
        XCTAssertLessThanOrEqual(
            locationMenu.frame.maxY,
            locationPath.frame.minY,
            "The current path belongs below the location menu"
        )
        XCTAssertLessThanOrEqual(
            locationPath.frame.maxY,
            searchField.frame.minY,
            "The current path belongs above folder search"
        )
        XCTAssertGreaterThanOrEqual(
            locationPath.frame.height,
            15,
            "The current folder path must remain readable at normal window scale"
        )

        locationMenu.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.8)
        ).click()
        XCTAssertTrue(
            app.buttons["pane-location-option-Desktop"]
                .waitForExistence(timeout: 3),
            "The complete location pill should open its menu"
        )
        app.typeKey(.escape, modifierFlags: [])

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
        let removeFavorite = app.menuItems["Remove from Sidebar"]
        XCTAssertTrue(removeFavorite.waitForExistence(timeout: 3))
        removeFavorite.click()
        XCTAssertTrue(
            waitForElementCount(sidebarFavorites, toEqual: 0, timeout: 5)
        )

        try rightClickRow(destinationRows.firstMatch)
        XCTAssertTrue(
            fileContextMenuButton(named: "Add to Favorites")
                .waitForExistence(timeout: 3)
        )
    }

    func testBuiltInSidebarItemsCanBeRemovedAndRestored() throws {
        XCTAssertTrue(
            rows(named: "Source Item.txt").firstMatch.waitForExistence(timeout: 10)
        )

        let homeRow = app.descendants(matching: .any)["sidebar-built-in-home"]
        XCTAssertTrue(homeRow.waitForExistence(timeout: 5))
        let accountName = NSUserName()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedHomeTitle = accountName.isEmpty ? "Home" : accountName
        XCTAssertTrue(
            app.staticTexts[expectedHomeTitle].waitForExistence(timeout: 3),
            "The Home sidebar row should use the current account name"
        )

        let picturesRow = app.descendants(matching: .any)[
            "sidebar-built-in-pictures"
        ]
        XCTAssertTrue(picturesRow.waitForExistence(timeout: 5))
        try rightClickRow(picturesRow)

        let remove = app.menuItems["Remove from Sidebar"]
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        remove.click()
        XCTAssertTrue(picturesRow.waitForNonExistence(timeout: 5))

        let restoreItems = app.buttons["sidebar-restore-items-button"]
        XCTAssertTrue(restoreItems.waitForExistence(timeout: 5))
        restoreItems.click()

        let restorePictures = app.buttons["sidebar-restore-pictures"]
        XCTAssertTrue(restorePictures.waitForExistence(timeout: 5))
        restorePictures.click()
        XCTAssertTrue(picturesRow.waitForExistence(timeout: 5))
    }

    func testFileContextMenuOffersSharingAndInformation() throws {
        let sourceRows = rows(named: "Source Item.txt")
        XCTAssertTrue(sourceRows.firstMatch.waitForExistence(timeout: 10))

        try rightClickRow(sourceRows.firstMatch)
        XCTAssertTrue(
            fileContextMenuButton(named: "Share").waitForExistence(timeout: 3)
        )

        let getInfo = fileContextMenuButton(named: "Get Info")
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

    func testFileContextMenuOffersCompatibleOpenWithApplication() throws {
        let sourceRow = rows(named: "Source Item.txt").firstMatch
        XCTAssertTrue(sourceRow.waitForExistence(timeout: 10))

        try rightClickRow(sourceRow)
        let contextMenu = app.descendants(matching: .any)["file-item-context-menu"]
        XCTAssertTrue(contextMenu.waitForExistence(timeout: 3))
        let contextMenuFrame = contextMenu.frame
        let openWith = fileContextMenuButton(named: "Open With")
        XCTAssertTrue(openWith.waitForExistence(timeout: 3))
        XCTAssertTrue(fileContextMenuButton(named: "Move to Trash").exists)
        XCTAssertEqual(openWith.value as? String, "Closed")
        openWith.click()

        let applicationMenu = app.descendants(matching: .any)[
            "open-with-application-menu"
        ]
        XCTAssertTrue(applicationMenu.waitForExistence(timeout: 5))
        XCTAssertEqual(openWith.value as? String, "Open")
        XCTAssertEqual(
            contextMenu.frame.width,
            contextMenuFrame.width,
            accuracy: 4,
            "Opening the side menu must not expand the main context menu"
        )
        XCTAssertEqual(
            contextMenu.frame.height,
            contextMenuFrame.height,
            accuracy: 4,
            "Opening the side menu must not add inline application rows"
        )
        let fixtureViewer = applicationMenu.buttons["Fixture Viewer"]
        XCTAssertTrue(fixtureViewer.waitForExistence(timeout: 5))
        XCTAssertTrue(fixtureViewer.isEnabled)
        fixtureViewer.click()
        XCTAssertTrue(applicationMenu.waitForNonExistence(timeout: 5))
        XCTAssertTrue(
            contextMenu.waitForNonExistence(timeout: 5)
        )

        let destinationRow = rows(named: "Destination").firstMatch
        XCTAssertTrue(destinationRow.waitForExistence(timeout: 3))
        try rightClickRow(destinationRow)
        XCTAssertFalse(fileContextMenuButton(named: "Open With").exists)
    }

    func testApplicationContextMenuOffersConfirmedUninstall() throws {
        app.terminate()
        try makeApplicationBundle(at: applicationBundleURL)
        app.launch()

        let applicationRow = rows(named: applicationBundleURL.lastPathComponent)
            .firstMatch
        XCTAssertTrue(
            applicationRow.waitForExistence(timeout: 10),
            "The application fixture did not appear after relaunch"
        )

        try rightClickRow(applicationRow)
        let uninstall = fileContextMenuButton(named: "Uninstall Application")
        XCTAssertTrue(uninstall.waitForExistence(timeout: 3))
        XCTAssertTrue(uninstall.isEnabled)
        XCTAssertFalse(fileContextMenuButton(named: "Move to Trash").exists)
        scrollFileContextMenuTo(uninstall)
        uninstall.click()

        let confirmationSheet = app.sheets.firstMatch
        XCTAssertTrue(
            confirmationSheet.staticTexts["Uninstall Fixture App?"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            confirmationSheet.staticTexts[
                "“Fixture App.app” will be moved to Trash. "
                    + "Its documents and settings will remain on this Mac."
            ].exists
        )
        XCTAssertTrue(confirmationSheet.buttons["Uninstall"].exists)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: applicationBundleURL.path(percentEncoded: false)
            )
        )

        confirmationSheet.buttons["Cancel"].click()
        XCTAssertTrue(confirmationSheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(applicationRow.waitForExistence(timeout: 3))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: applicationBundleURL.path(percentEncoded: false)
            ),
            "Cancel must preserve the application bundle"
        )

        let applicationCell = try XCTUnwrap(containingCell(for: applicationRow))
        applicationCell.click()
        applicationCell.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(
            app.staticTexts["Uninstall Fixture App?"]
                .waitForExistence(timeout: 5),
            "The Delete key must use the application uninstall confirmation"
        )
        confirmationSheet.buttons["Cancel"].click()
        XCTAssertTrue(confirmationSheet.waitForNonExistence(timeout: 5))

        let trashButton = app.buttons["trash-item-Fixture App.app"]
        XCTAssertTrue(trashButton.waitForExistence(timeout: 3))
        XCTAssertTrue(trashButton.isEnabled)
        trashButton.click()
        XCTAssertTrue(
            app.staticTexts["Uninstall Fixture App?"]
                .waitForExistence(timeout: 5),
            "The row Trash button must use the application uninstall confirmation"
        )
        confirmationSheet.buttons["Cancel"].click()
        XCTAssertTrue(confirmationSheet.waitForNonExistence(timeout: 5))

        try rightClickRow(applicationRow)
        let confirmedUninstall = fileContextMenuButton(
            named: "Uninstall Application"
        )
        XCTAssertTrue(confirmedUninstall.waitForExistence(timeout: 3))
        scrollFileContextMenuTo(confirmedUninstall)
        confirmedUninstall.click()
        XCTAssertTrue(
            confirmationSheet.buttons["Uninstall"].waitForExistence(timeout: 5)
        )
        confirmationSheet.buttons["Uninstall"].click()

        XCTAssertTrue(applicationRow.waitForNonExistence(timeout: 10))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: applicationBundleURL.path(percentEncoded: false)
            )
        )
        let toast = app.descendants(matching: .any)["file-operation-toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertEqual(toast.value as? String, "Moved to Trash")
    }

    func testFolderInformationCalculatesItsRecursiveSize() throws {
        let folderRow = rows(named: "Global Results").firstMatch
        XCTAssertTrue(folderRow.waitForExistence(timeout: 10))

        try rightClickRow(folderRow)
        let getInfo = fileContextMenuButton(named: "Get Info")
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
            waitForValue(expectedText, on: sizeValue, timeout: 10),
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
        let hideFolder = fileContextMenuButton(named: "Hide Folder")
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
        let unhideFolder = fileContextMenuButton(named: "Unhide Folder")
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

    func testDuplicatesRequireSelectionAndConfirmationAndRetainOneCopy() throws {
        app.terminate()
        let first = fixtureRootURL.appending(path: "Duplicate A.txt")
        let second = fixtureRootURL.appending(path: "Duplicate B.txt")
        let data = Data("Exact duplicate UI fixture".utf8)
        try data.write(to: first)
        try data.write(to: second)
        app.launch()
        XCTAssertTrue(rows(named: "Duplicate A.txt").firstMatch.waitForExistence(timeout: 10))
        app.buttons["window-file-tools-button"].click()
        app.buttons["file-tools-duplicates"].click()
        let scan = app.buttons["duplicates-scan"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        let review = app.buttons["duplicates-review"]
        XCTAssertFalse(review.isEnabled)
        scan.click()
        let chooseFirst = app.buttons["duplicate-select-Duplicate A.txt"]
        XCTAssertTrue(chooseFirst.waitForExistence(timeout: 10))
        XCTAssertFalse(review.isEnabled, "Scanning must not select a removal automatically")
        chooseFirst.click()
        XCTAssertFalse(app.buttons["duplicate-select-Duplicate B.txt"].isEnabled, "At least one copy must stay")
        XCTAssertTrue(review.isEnabled)
        recordWindowHierarchy("Duplicates")
        review.click()
        let confirm = app.buttons["duplicate-trash-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        app.buttons["duplicate-trash-cancel"].click()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        XCTAssertEqual(try Data(contentsOf: first), data)
        XCTAssertEqual(try Data(contentsOf: second), data)
        review.click()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(app.staticTexts["duplicate-trash-report"].waitForExistence(timeout: 10))
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertEqual(try Data(contentsOf: second), data)
        app.buttons["duplicates-close"].click()
        XCTAssertTrue(rows(named: "Duplicate A.txt").firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(rows(named: "Duplicate B.txt").firstMatch.waitForExistence(timeout: 5))
    }

    func testOrganizationPreviewShowsDestinationsWithoutChangingFiles() throws {
        XCTAssertTrue(rows(named: "Source Item.txt").firstMatch.waitForExistence(timeout: 10))
        let before = fixtureContents()
        app.buttons["window-file-tools-button"].click()
        app.buttons["file-tools-organize"].click()
        let preview = app.buttons["organization-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.click()
        XCTAssertTrue(app.staticTexts["organization-summary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Documents/Source Item.txt"].exists)
        XCTAssertTrue(app.buttons["organization-review-button"].isEnabled)
        XCTAssertEqual(fixtureContents(), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixtureRootURL.appending(path: "Documents").path))
        recordWindowHierarchy("Organization")
        app.buttons["organization-close"].click()
        XCTAssertTrue(rows(named: "Source Item.txt").firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(fixtureContents(), before)
    }

    func testOrganizationRequiresReviewAndConfirmationThenRefreshesTheFolder() throws {
        XCTAssertTrue(rows(named: "Source Item.txt").firstMatch.waitForExistence(timeout: 10))
        let source = fixtureRootURL.appending(path: "Source Item.txt")
        let data = try Data(contentsOf: source)
        let destination = fixtureRootURL.appending(path: "Documents/Source Item.txt")
        let before = fixtureContents()
        app.buttons["window-file-tools-button"].click()
        app.buttons["file-tools-organize"].click()
        let preview = app.buttons["organization-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        let review = app.buttons["organization-review-button"]
        XCTAssertFalse(review.isEnabled)
        preview.click()
        XCTAssertTrue(app.staticTexts["organization-summary"].waitForExistence(timeout: 10))
        review.click()
        let confirm = app.buttons["organization-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Files to move: 1 · New folders: 1"].exists)
        recordWindowHierarchy("Organization move review")
        app.buttons["organization-review-cancel"].click()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        XCTAssertEqual(fixtureContents(), before)
        XCTAssertEqual(try Data(contentsOf: source), data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.deletingLastPathComponent().path))
        review.click()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(app.staticTexts["organization-report"].waitForExistence(timeout: 10))
        XCTAssertFalse(review.isEnabled, "A completed plan must not be reused")
        XCTAssertEqual(try Data(contentsOf: destination), data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        app.buttons["organization-close"].click()
        XCTAssertTrue(rows(named: "Source Item.txt").firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(rows(named: "Documents").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(rows(named: "Destination").firstMatch.exists)
    }

    func testOfflineCatalogRequiresSaveAndSurvivesDisconnectAndRelaunch() throws {
        let file = mountedVolumeURL.appending(path: "Offline Invoice.txt")
        try Data("Offline metadata fixture; contents stay on the disk.".utf8).write(to: file)
        try createOfflineCatalog()
        let search = app.textFields["offline-catalog-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        typeCatalogQuery("invoice", in: search)
        XCTAssertTrue(waitForValue("invoice", on: search, timeout: 3), "Typing must preserve every character")
        XCTAssertTrue(waitForValue("Showing 1 of 1 matches", on: app.staticTexts["offline-catalog-match-count"], timeout: 5))
        let reveal = app.buttons["offline-catalog-reveal-Offline Invoice.txt"]
        XCTAssertTrue(reveal.isEnabled)
        recordWindowHierarchy("Connected offline catalog")
        app.terminate()

        let disconnected = fixtureRootURL.appending(path: "Disconnected Test Disk")
        try FileManager.default.moveItem(at: mountedVolumeURL, to: disconnected)
        app.launch()
        try openOfflineCatalogs()
        XCTAssertTrue(app.textFields["offline-catalog-search"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForValue("Disk offline — saved metadata", on: element(withIdentifier: "offline-catalog-connection"), timeout: 5))
        typeCatalogQuery("invoice", in: app.textFields["offline-catalog-search"])
        XCTAssertTrue(waitForValue("invoice", on: app.textFields["offline-catalog-search"], timeout: 3))
        XCTAssertTrue(reveal.waitForExistence(timeout: 5))
        XCTAssertFalse(reveal.isEnabled)
        XCTAssertFalse(app.buttons["offline-catalog-refresh"].isEnabled)
        XCTAssertTrue(waitForValue("Showing 1 of 1 matches", on: app.staticTexts["offline-catalog-match-count"], timeout: 5))
        recordWindowHierarchy("Offline catalog after relaunch")
        app.terminate()

        try FileManager.default.moveItem(at: disconnected, to: mountedVolumeURL)
        app.launch()
        try openOfflineCatalogs()
        XCTAssertTrue(reveal.waitForExistence(timeout: 10))
        XCTAssertTrue(reveal.isEnabled)
        reveal.click()
        XCTAssertTrue(app.buttons["offline-catalog-close"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(rows(named: "Offline Invoice.txt").firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testOfflineCatalogRemovalNeedsConfirmationAndKeepsOriginalFiles() throws {
        let file = mountedVolumeURL.appending(path: "Keep Original.txt")
        let data = Data("Never remove this source when deleting a saved catalog.".utf8)
        try data.write(to: file)
        try createOfflineCatalog()
        let remove = app.buttons["offline-catalog-remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        remove.click()
        let confirm = app.buttons["offline-catalog-remove-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        app.buttons["Cancel"].click()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        XCTAssertTrue(remove.exists)
        XCTAssertEqual(try Data(contentsOf: file), data)
        remove.click()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(waitForValue("Saved catalog removed. Original files were not changed.", on: app.staticTexts["offline-catalog-notice"], timeout: 5))
        XCTAssertFalse(remove.exists)
        XCTAssertEqual(try Data(contentsOf: file), data)
        recordWindowHierarchy("Saved catalog removed without touching originals")
    }

    func testVisualSearchRequiresAnalysisFindsImageTextAndCanForgetIt() throws {
        app.terminate()
        let file = fixtureRootURL.appending(path: "ZXQ-Visual-Fixture.png")
        let data = try visualReceiptImage()
        try data.write(to: file)
        app.launch()
        openVisualSearch()
        XCTAssertFalse(app.textFields["visual-search-query"].exists, "Opening the tool must not analyze images")
        app.buttons["visual-search-analyze"].click()
        let query = app.textFields["visual-search-query"]
        XCTAssertTrue(query.waitForExistence(timeout: 45))
        XCTAssertFalse(app.staticTexts["visual-search-error"].exists)
        typeCatalogQuery("invoice", in: query)
        XCTAssertEqual(query.value as? String, "invoice")
        let reveal = app.buttons["visual-search-reveal-ZXQ-Visual-Fixture.png"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 5))
        recordWindowHierarchy("Real local OCR result with its evidence")
        app.buttons["visual-search-close"].click()
        openVisualSearch()
        XCTAssertEqual(app.textFields["visual-search-query"].value as? String, "invoice")
        XCTAssertTrue(reveal.waitForExistence(timeout: 5), "Reopening reuses memory without another scan")
        app.buttons["visual-search-clear"].click()
        XCTAssertFalse(app.textFields["visual-search-query"].exists)
        XCTAssertEqual(try Data(contentsOf: file), data)
        app.buttons["visual-search-close"].click()
        XCTAssertTrue(element(withIdentifier: "global-search-text-field").waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        openVisualSearch()
        XCTAssertFalse(app.textFields["visual-search-query"].exists, "Image evidence must not persist across launches")
    }

    func testVisualSearchRejectsAChangedResultWithoutNavigating() throws {
        app.terminate()
        let file = fixtureRootURL.appending(path: "Changed-Visual-Fixture.png")
        try visualReceiptImage().write(to: file)
        app.launch()
        openVisualSearch()
        app.buttons["visual-search-analyze"].click()
        XCTAssertTrue(app.textFields["visual-search-query"].waitForExistence(timeout: 45))
        let reveal = app.buttons["visual-search-reveal-Changed-Visual-Fixture.png"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 5))
        try Data("Replaced fixture".utf8).write(to: file)
        reveal.click()
        XCTAssertTrue(app.staticTexts["visual-search-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["visual-search-close"].exists)
        recordWindowHierarchy("Changed image cannot be revealed from stale evidence")
    }

    func testAskAIRoutesPhotoDescriptionAndReusesAnalyzedFolder() throws {
        app.terminate()
        try visualReceiptImage().write(to: fixtureRootURL.appending(path: "Visual.png"))
        app.launch()
        app.buttons["window-ask-ai-button"].click()
        let input = app.textFields["ask-ai-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        typeCatalogQuery("Find photos taken by the sea", in: input)
        app.buttons["ask-ai-submit"].click()
        let description = app.textFields["visual-description-input"]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        XCTAssertEqual(description.value as? String, "Find photos taken by the sea")
        XCTAssertFalse(app.buttons["visual-description-submit"].isEnabled)
        XCTAssertFalse(app.textFields["visual-search-query"].exists, "A natural request must not silently start a folder scan")
        app.buttons["visual-search-analyze"].click()
        XCTAssertTrue(app.textFields["visual-search-query"].waitForExistence(timeout: 45))
        app.buttons["visual-description-submit"].click()
        XCTAssertTrue(app.staticTexts["visual-description-evidence"].waitForExistence(timeout: 10))
        XCTAssertTrue((app.staticTexts["visual-description-evidence"].value as? String ?? "").contains("beach"))
        recordWindowHierarchy("Photo sentence resolved to visible visual evidence")
        app.buttons["visual-search-close"].click()
        XCTAssertTrue(app.buttons["ask-ai-submit"].waitForExistence(timeout: 5))
        app.buttons["ask-ai-submit"].click()
        XCTAssertTrue(app.staticTexts["visual-description-evidence"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["visual-search-error"].exists)
        app.buttons["visual-search-close"].click()
        app.buttons["ask-ai-documents"].click()
        XCTAssertTrue(app.buttons["document-choose"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["document-ready"].exists, "Opening the document tool must not read files")
        app.buttons["document-close"].click()
        XCTAssertTrue(app.buttons["ask-ai-submit"].waitForExistence(timeout: 5))
    }

    func testPhotoDateAndTypeFollowUpsPreserveSceneAcrossAskAI() throws {
        app.terminate()
        let fixture = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "FinallyExplorerTests/Fixtures/VisualPhotos/beach-monterey.jpg")
        let bytes = try Data(contentsOf: fixture)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let lastWeek = try XCTUnwrap(Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        for (name, type) in [("Coast.jpg", UTType.jpeg), ("Coast.png", UTType.png)] {
            let url = fixtureRootURL.appending(path: name)
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: formatter.string(from: lastWeek), kCGImagePropertyExifOffsetTimeOriginal: "+00:00",
            ]] as CFDictionary)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
        }
        app.launch()
        app.buttons["window-ask-ai-button"].click()
        let input = app.textFields["ask-ai-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        typeCatalogQuery("Find beach photos from last week", in: input)
        app.buttons["ask-ai-submit"].click()
        XCTAssertTrue(app.buttons["visual-search-analyze"].waitForExistence(timeout: 5))
        app.buttons["visual-search-analyze"].click()
        XCTAssertTrue(app.textFields["visual-search-query"].waitForExistence(timeout: 45))
        app.buttons["visual-description-submit"].click()
        let filters = app.staticTexts["visual-description-filters"]
        XCTAssertTrue(filters.waitForExistence(timeout: 10))
        let originalDate = try XCTUnwrap(filters.value as? String)
        XCTAssertTrue(originalDate.contains("Captured (EXIF)"))
        XCTAssertTrue(app.buttons["visual-search-reveal-Coast.jpg"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["visual-search-reveal-Coast.png"].exists)

        app.buttons["visual-search-close"].click()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.click()
        input.typeKey("a", modifierFlags: .command)
        input.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])
        XCTAssertEqual(input.value as? String, "", "Command-A and Delete must clear the photo follow-up field")
        typeCatalogQuery("Only PNG", in: input)
        XCTAssertEqual(input.value as? String, "Only PNG")
        app.buttons["ask-ai-submit"].click()
        XCTAssertTrue(filters.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(originalDate + " · Type: PNG", on: filters, timeout: 10))
        XCTAssertTrue(app.buttons["visual-search-reveal-Coast.png"].exists)
        XCTAssertFalse(app.buttons["visual-search-reveal-Coast.jpg"].exists)
        XCTAssertTrue((app.staticTexts["visual-description-evidence"].value as? String ?? "").contains("beach"))

        let description = app.textFields["visual-description-input"]
        description.click()
        description.typeKey("a", modifierFlags: .command)
        description.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])
        XCTAssertEqual(description.value as? String, "")
        typeCatalogQuery("Only HEIC", in: description)
        XCTAssertEqual(description.value as? String, "Only HEIC")
        app.buttons["visual-description-submit"].click()
        XCTAssertTrue(waitForValue(originalDate + " · Type: HEIC", on: filters, timeout: 5))
        XCTAssertFalse(app.buttons["visual-search-reveal-Coast.png"].exists)
        XCTAssertFalse(app.staticTexts["visual-search-error"].exists)
        recordWindowHierarchy("Photo date and format refinement")
        app.buttons["visual-description-new-search"].click()
        XCTAssertTrue(filters.waitForNonExistence(timeout: 5))
        XCTAssertEqual(description.value as? String, "")
        app.buttons["visual-search-close"].click()
        app.buttons["ask-ai-new-search"].click()
        XCTAssertEqual(input.value as? String, "")
    }

    func testToolsLauncherKeyboardAndFullRowActions() throws {
        let tools = app.buttons["window-file-tools-button"]
        XCTAssertTrue(tools.waitForExistence(timeout: 10))
        tools.click()
        XCTAssertTrue(element(withIdentifier: "file-tools-popover").waitForExistence(timeout: 5))
        app.popovers.firstMatch.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        XCTAssertTrue(element(withIdentifier: "file-tools-popover").waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.popovers.firstMatch.waitForNonExistence(timeout: 5))
        tools.click()
        XCTAssertTrue(app.buttons["file-tools-visual-search"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue("Selected", on: app.buttons["file-tools-visual-search"], timeout: 3))
        app.popovers.firstMatch.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: [])
        XCTAssertTrue(waitForValue("Selected", on: app.buttons["file-tools-documents"], timeout: 3))
        app.popovers.firstMatch.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["document-close"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["document-ready"].exists, "Opening Tools must not read documents")
        app.buttons["document-close"].click()
        for (tool, close) in [
            ("file-tools-visual-search", "visual-search-close"),
            ("file-tools-documents", "document-close"),
            ("file-tools-duplicates", "duplicates-close"),
            ("file-tools-organize", "organization-close"),
            ("file-tools-offline-catalogs", "offline-catalog-close")
        ] {
            tools.click()
            let action = app.buttons[tool]
            XCTAssertTrue(action.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(action.frame.height, 36)
            // Hit the card's trailing padding, not its title or icon.
            action.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).click()
            XCTAssertTrue(app.buttons[close].waitForExistence(timeout: 5), tool)
            app.buttons[close].click()
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFileURL.path))
    }

    func testVisualSearchActionsStayVisibleAndFolderCancelKeepsSource() throws {
        openVisualSearch()
        let choose = app.buttons["visual-search-choose-folder"]
        let find = app.buttons["visual-description-submit"]
        let clear = app.buttons["visual-search-clear"]
        for action in [choose, find] {
            XCTAssertTrue(action.exists)
            XCTAssertGreaterThanOrEqual(action.frame.height, 36)
        }
        XCTAssertTrue(choose.isEnabled)
        XCTAssertFalse(find.isEnabled)
        XCTAssertFalse(clear.exists, "There is no analysis to clear yet")
        XCTAssertFalse(app.checkBoxes["visual-search-hidden-items"].exists, "Advanced options should not clutter the main controls")
        XCTAssertTrue(app.buttons["visual-search-options"].exists)
        let source = choose.value as? String
        choose.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).click()
        let picker = app.windows["open-panel"]
        let cancel = picker.buttons["CancelButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.click()
        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
        XCTAssertEqual(choose.value as? String, source)
        XCTAssertFalse(app.staticTexts["visual-search-summary"].exists)
        XCTAssertTrue(app.buttons["visual-search-analyze"].isEnabled)
        app.buttons["visual-search-close"].click()
    }

    func testScannedPDFRequiresReadingAndShowsOCRPageCitation() throws {
        app.terminate()
        let file = fixtureRootURL.appending(path: "Scanned Invoice.pdf")
        let original = try scannedInvoicePDF()
        try original.write(to: file)
        app.launch()
        let row = rows(named: "Scanned Invoice.pdf").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        app.buttons["window-file-tools-button"].click()
        app.buttons["file-tools-documents"].click()
        XCTAssertTrue(app.buttons["document-read"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["document-ready"].exists)
        XCTAssertFalse(element(withIdentifier: "document-ocr-summary").exists)
        app.buttons["document-read"].click()
        XCTAssertTrue(app.staticTexts["document-ready"].waitForExistence(timeout: 20))
        XCTAssertTrue(element(withIdentifier: "document-ocr-summary").exists)
        let question = element(withIdentifier: "document-question")
        typeCatalogQuery("What is the payment deadline?", in: question)
        XCTAssertEqual(question.value as? String, "What is the payment deadline?")
        app.buttons["document-ask"].click()
        let citation = app.buttons["document-citation-2"].firstMatch
        XCTAssertTrue(citation.waitForExistence(timeout: 45))
        XCTAssertTrue(citation.label.contains("page 2 · OCR"), citation.label)
        XCTAssertFalse(app.staticTexts["document-error"].exists)
        XCTAssertTrue(element(withIdentifier: "document-answer-ocr-notice").exists)
        let answer = app.staticTexts.matching(identifier: "document-answer-claim").allElementsBoundByIndex
            .compactMap { $0.value as? String }.joined(separator: " ")
        XCTAssertTrue(answer.contains("2026"), answer)
        citation.click()
        XCTAssertTrue(app.buttons["document-source-done"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(withIdentifier: "document-source-ocr-notice").exists)
        let source = element(withIdentifier: "document-source-sheet")
        // macOS SwiftUI static text exposes its contents through AX value.
        XCTAssertEqual(source.value as? String, "Scanned Invoice.pdf · page 2 · OCR")
        recordWindowHierarchy("Scanned PDF OCR citation with original page number and recognition warning")
        app.buttons["document-source-done"].click()
        app.buttons["document-clear"].click()
        XCTAssertFalse(app.staticTexts["document-ready"].exists)
        XCTAssertFalse(element(withIdentifier: "document-ocr-summary").exists)
        XCTAssertFalse(citation.exists)
        XCTAssertEqual(try Data(contentsOf: file), original)
        app.buttons["document-close"].click()
    }

    private func scannedInvoicePDF() throws -> Data {
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 1_200, height: 1_600, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 1_200, height: 1_600))
        let lines = ["Harbor Studio invoice 4827", "Payment deadline is 30 September 2026."]
        for (index, text) in lines.enumerated() {
            let line = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 32, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
            ])
            bitmap.textPosition = CGPoint(x: 60, y: 1_400 - index * 56)
            CTLineDraw(CTLineCreateWithAttributedString(line), bitmap)
        }
        let image = try XCTUnwrap(bitmap.makeImage())
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        var box = CGRect(x: 0, y: 0, width: 600, height: 800)
        let pdfContext = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        pdfContext.beginPDFPage(nil)
        let cover = NSAttributedString(string: "Invoice cover sheet", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 16, nil),
        ])
        pdfContext.textPosition = CGPoint(x: 30, y: 700)
        CTLineDraw(CTLineCreateWithAttributedString(cover), pdfContext)
        pdfContext.endPDFPage()
        pdfContext.beginPDFPage(nil)
        pdfContext.draw(image, in: box)
        pdfContext.endPDFPage()
        pdfContext.closePDF()
        let pdf = try XCTUnwrap(PDFDocument(data: data as Data))
        let scanned = try XCTUnwrap(pdf.page(at: 1))
        XCTAssertTrue((scanned.string ?? "").isEmpty, "The scan must not have a hidden text layer")
        return data as Data
    }

    func testDocumentQuestionRequiresReadingAndShowsSourceThenClears() throws {
        app.terminate()
        let original = Data("The payment deadline is 30 September 2026. The invoice total is 480 USD.".utf8)
        try original.write(to: sourceFileURL)
        app.launch()
        let row = rows(named: "Source Item.txt").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        app.buttons["window-file-tools-button"].click()
        app.buttons["file-tools-documents"].click()
        XCTAssertTrue(app.buttons["document-read"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["document-ready"].exists)
        app.buttons["document-read"].click()
        XCTAssertTrue(app.staticTexts["document-ready"].waitForExistence(timeout: 10))
        let question = element(withIdentifier: "document-question")
        typeCatalogQuery("What is the payment deadline?", in: question)
        XCTAssertEqual(question.value as? String, "What is the payment deadline?")
        app.buttons["document-ask"].click()
        let citation = app.buttons["document-citation-1"].firstMatch
        XCTAssertTrue(citation.waitForExistence(timeout: 45))
        XCTAssertFalse(app.staticTexts["document-error"].exists)
        recordWindowHierarchy("Actual on-device document answer with verified citation")
        citation.click()
        XCTAssertTrue(app.buttons["document-source-done"].waitForExistence(timeout: 5))
        app.buttons["document-source-done"].click()
        app.buttons["document-clear"].click()
        XCTAssertFalse(app.staticTexts["document-ready"].exists)
        XCTAssertFalse(citation.exists)
        XCTAssertEqual(try Data(contentsOf: sourceFileURL), original)
        app.buttons["document-close"].click()
        XCTAssertTrue(element(withIdentifier: "global-search-text-field").waitForExistence(timeout: 5))
    }

    func testDocumentFollowUpShowsResolutionAndCanStartNewConversation() throws {
        app.terminate()
        let original = Data("Harbor Studio invoice 4827 payment is due on 30 September 2026. Harbor Studio invoice 4827 total is 480 USD.".utf8)
        try original.write(to: sourceFileURL)
        app.launch()
        let row = rows(named: "Source Item.txt").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        app.buttons["window-file-tools-button"].click()
        app.buttons["file-tools-documents"].click()
        XCTAssertTrue(app.buttons["document-read"].waitForExistence(timeout: 5))
        app.buttons["document-read"].click()
        XCTAssertTrue(app.staticTexts["document-ready"].waitForExistence(timeout: 10))
        let input = element(withIdentifier: "document-question")
        typeCatalogQuery("When is Harbor Studio's invoice due?", in: input)
        XCTAssertEqual(input.value as? String, "When is Harbor Studio's invoice due?")
        app.buttons["document-ask"].click()
        XCTAssertTrue(app.buttons["document-citation-1"].firstMatch.waitForExistence(timeout: 45))
        let firstAnswer = app.staticTexts.matching(identifier: "document-answer-claim").allElementsBoundByIndex
            .compactMap { $0.value as? String }.joined(separator: " ")
        XCTAssertTrue(firstAnswer.contains("2026"), firstAnswer)
        XCTAssertFalse(firstAnswer.contains("480"), "The date question must not be answered with the invoice total: \(firstAnswer)")
        XCTAssertTrue(app.buttons["document-new-conversation"].exists)
        input.click()
        input.typeKey("a", modifierFlags: .command)
        input.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])
        XCTAssertEqual(input.value as? String, "")
        typeCatalogQuery("How much is it?", in: input)
        XCTAssertEqual(input.value as? String, "How much is it?")
        app.buttons["document-ask"].click()
        // Selectable SwiftUI Text exposes its content as the AX value on macOS.
        let amount = app.staticTexts.matching(identifier: "document-answer-claim")
            .matching(NSPredicate(format: "value CONTAINS %@", "480")).firstMatch
        // Previous verified answers remain visible while the next request is
        // running. Wait for this turn's interpretation, not the old card.
        XCTAssertTrue(app.staticTexts["document-resolved-question"].firstMatch.waitForExistence(timeout: 60))
        XCTAssertTrue(amount.waitForExistence(timeout: 60))
        XCTAssertFalse(app.staticTexts["document-error"].exists)
        recordWindowHierarchy("Document follow-up with explicit interpretation and verified quote")
        app.buttons["document-citation-1"].firstMatch.click()
        XCTAssertTrue(app.buttons["document-source-done"].waitForExistence(timeout: 5))
        app.buttons["document-source-done"].click()
        app.buttons["document-new-conversation"].click()
        XCTAssertTrue(app.staticTexts["document-ready"].exists, "Starting fresh must not reread the selection")
        XCTAssertFalse(app.staticTexts["document-answer-claim"].firstMatch.exists)
        XCTAssertFalse(app.buttons["document-new-conversation"].exists)
        XCTAssertEqual(input.value as? String, "")
        typeCatalogQuery("What is the invoice total?", in: input)
        XCTAssertEqual(input.value as? String, "What is the invoice total?")
        app.buttons["document-ask"].click()
        XCTAssertTrue(amount.waitForExistence(timeout: 45))
        XCTAssertFalse(app.staticTexts["document-resolved-question"].firstMatch.exists)
        XCTAssertEqual(try Data(contentsOf: sourceFileURL), original)
        app.buttons["document-close"].click()
    }

    private func openVisualSearch() {
        let tools = app.buttons["window-file-tools-button"]
        XCTAssertTrue(tools.waitForExistence(timeout: 10))
        tools.click()
        app.buttons["file-tools-visual-search"].click()
        XCTAssertTrue(app.buttons["visual-search-close"].waitForExistence(timeout: 5))
    }

    func testDocumentSettingsOptOutClearsClosedContextAndPersists() throws {
        let row = rows(named: "Source Item.txt").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        app.buttons["window-file-tools-button"].click()
        app.buttons["file-tools-documents"].click()
        XCTAssertTrue(app.buttons["document-read"].waitForExistence(timeout: 5))
        app.buttons["document-read"].click()
        XCTAssertTrue(app.staticTexts["document-ready"].waitForExistence(timeout: 10))
        app.buttons["document-close"].click()

        app.buttons["window-settings-button"].click()
        let toggle = element(withIdentifier: "ai-settings-document-questions-toggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()
        let settingsWindow = app.windows.containing(.any, identifier: "ai-settings-view").firstMatch
        XCTAssertTrue(settingsWindow.exists)
        settingsWindow.buttons[XCUIIdentifierCloseWindow].click()

        app.buttons["window-file-tools-button"].click()
        app.buttons["file-tools-documents"].click()
        XCTAssertTrue(app.buttons["document-read"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["document-ready"].exists, "Opt-out must clear text even while the document tool is closed")
        XCTAssertFalse(app.buttons["document-read"].isEnabled)
        XCTAssertFalse(app.buttons["document-ask"].isEnabled)
        app.buttons["document-close"].click()
        XCTAssertTrue(element(withIdentifier: "global-search-text-field").waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        app.buttons["window-file-tools-button"].click()
        app.buttons["file-tools-documents"].click()
        XCTAssertTrue(app.buttons["document-read"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["document-read"].isEnabled, "Document Questions opt-out must survive relaunch")
        XCTAssertFalse(app.staticTexts["document-ready"].exists)
    }

    private func visualReceiptImage() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1_000, height: 500, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1_000, height: 500))
        let line = NSAttributedString(string: "INVOICE 4827", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, 80, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ])
        context.textPosition = CGPoint(x: 100, y: 250)
        CTLineDraw(CTLineCreateWithAttributedString(line), context)
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func openOfflineCatalogs() throws {
        let tools = app.buttons["window-file-tools-button"]
        XCTAssertTrue(tools.waitForExistence(timeout: 10))
        tools.click()
        app.buttons["file-tools-offline-catalogs"].click()
        XCTAssertTrue(app.buttons["offline-catalog-close"].waitForExistence(timeout: 5))
    }

    private func typeCatalogQuery(_ query: String, in field: XCUIElement) {
        field.click()
        // On this macOS runner typeText("c") drops the character even in
        // isolation, whereas typeKey delivers it. Keep real keyboard input
        // and assert the complete value instead of weakening the query.
        for character in query { field.typeKey(String(character), modifierFlags: []) }
    }

    private func createOfflineCatalog() throws {
        try openOfflineCatalogs()
        let volumeMenu = element(withIdentifier: "offline-catalog-volume-menu")
        XCTAssertTrue(volumeMenu.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: volumeMenu)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        volumeMenu.click()
        let disk = app.menuItems["UI Test Disk"]
        XCTAssertTrue(disk.waitForExistence(timeout: 5))
        disk.click()
        let save = app.buttons["offline-catalog-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixtureRootURL.appending(path: ".offline-catalog-storage").path), "Choosing a disk must not save automatically")
        save.click()
        XCTAssertTrue(app.staticTexts["offline-catalog-notice"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["offline-catalog-error"].exists)
    }

    /// App screenshots can capture an unrelated display in multi-monitor setups.
    /// Keep diagnostics scoped to this app; offscreen tests render the visual fixtures.
    private func recordWindowHierarchy(_ name: String) {
        let attachment = XCTAttachment(string: app.windows.firstMatch.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFolderComparisonRequiresApprovalAndCopiesOnlyMissingFiles() throws {
        app.terminate()
        let sourceFolder = fixtureRootURL.appending(path: "Comparison Source")
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        let source = sourceFolder.appending(path: "Verified.txt")
        let destination = destinationFolderURL.appending(path: "Verified.txt")
        try Data("verified fixture".utf8).write(to: source)
        app.launch()
        XCTAssertTrue(rows(named: "Comparison Source").firstMatch.waitForExistence(timeout: 10))
        app.buttons["Split Right"].click()
        XCTAssertTrue(waitForElementCount(rows(named: "Destination"), toEqual: 2, timeout: 5))
        let rightFolder = try XCTUnwrap(existingElements(in: rows(named: "Destination")).sorted(by: leftToRight).last)
        rightFolder.staticTexts["Destination"].doubleClick()
        XCTAssertTrue(app.staticTexts["Folder Is Empty"].waitForExistence(timeout: 5))
        let leftFolder = rows(named: "Comparison Source").firstMatch
        leftFolder.staticTexts["Comparison Source"].doubleClick()
        XCTAssertTrue(rows(named: "Verified.txt").firstMatch.waitForExistence(timeout: 5))

        app.buttons["window-compare-folders-button"].click()
        let compare = app.buttons["folder-comparison-start"]
        XCTAssertTrue(compare.waitForExistence(timeout: 5))
        XCTAssertTrue(compare.isEnabled)
        compare.click()
        let review = app.buttons["folder-comparison-review-copy"]
        XCTAssertTrue(waitForEnabled(review, timeout: 10))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        review.click()
        let confirm = app.buttons["verified-copy-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        app.buttons["verified-copy-cancel"].click()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        review.click()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(app.descendants(matching: .any)["verified-copy-report"].waitForExistence(timeout: 10))
        XCTAssertEqual(try Data(contentsOf: destination), try Data(contentsOf: source))
        recordWindowHierarchy("Verified copy completion")
        app.buttons["folder-comparison-close"].click()
        XCTAssertTrue(waitForElementCount(rows(named: "Verified.txt"), toEqual: 2, timeout: 10))
    }

    func testAskAIPanelIsExplicitSubmitAndKeepsNormalSearchAvailable() throws {
        XCTAssertTrue(rows(named: "Source Item.txt").firstMatch.waitForExistence(timeout: 10))
        app.buttons["window-ask-ai-button"].click()
        let input = app.textFields["ask-ai-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.click()
        input.typeText("Find the accounting report from two days ago")
        XCTAssertTrue(app.buttons["ask-ai-submit"].isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["ask-ai-current-filters"].exists)
        recordWindowHierarchy("Ask AI panel")
        app.buttons["ask-ai-new-search"].click()
        XCTAssertEqual(input.value as? String, "")
        XCTAssertFalse(app.buttons["ask-ai-submit"].isEnabled)
        app.buttons["ask-ai-close"].click()
        XCTAssertTrue(input.waitForNonExistence(timeout: 5))
        let field = app.descendants(matching: .any)["global-search-text-field"]
        XCTAssertTrue(waitForEnabled(field, timeout: 10))
        field.click()
        field.typeText("Global Needle")
        XCTAssertTrue(app.staticTexts["Global Needle Alpha.txt"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Global Needle Beta.txt"].waitForExistence(timeout: 10))
    }

    func testUnifiedSearchHasOneExplicitAIEntryAndKeepsNormalSearch() throws {
        XCTAssertTrue(rows(named: "Source Item.txt").firstMatch.waitForExistence(timeout: 10))
        let field = app.descendants(matching: .any)["global-search-text-field"]
        let aiButton = app.buttons["window-ask-ai-button"]
        XCTAssertTrue(waitForEnabled(field, timeout: 10))
        XCTAssertTrue(aiButton.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "window-ask-ai-button").count, 1)
        XCTAssertEqual(aiButton.label, "Ask AI")
        XCTAssertFalse(app.buttons["global-search-smart-toggle"].exists)
        typeCatalogQuery("Global Needle", in: field)
        XCTAssertEqual(field.value as? String, "Global Needle")
        XCTAssertTrue(app.staticTexts["Global Needle Alpha.txt"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Global Needle Beta.txt"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["ask-ai-input"].exists, "Typing stays in normal search.")
        // Dismiss the nonmodal results first; the query must survive the handoff.
        field.typeKey(.escape, modifierFlags: [])
        aiButton.click()
        let input = app.textFields["ask-ai-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Global Needle"].firstMatch.waitForExistence(timeout: 10),
                      "The explicit AI action submits the existing query once.")
        app.buttons["ask-ai-close"].click()
        XCTAssertTrue(input.waitForNonExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Global Needle")
        typeCatalogQuery("Global Needle Alpha", in: field)
        XCTAssertTrue(app.staticTexts["Global Needle Alpha.txt"].waitForExistence(timeout: 10))
        recordWindowHierarchy("Unified search preserves normal file search")
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
        XCTAssertTrue(
            waitForEnabled(globalSearchField, timeout: 10),
            "Global search indexing did not finish"
        )
        let readyGlobalSearchField = app.descendants(matching: .any)[
            "global-search-text-field"
        ]

        readyGlobalSearchField.click()
        readyGlobalSearchField.typeText("Global Needle")

        let resultRows = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "global-search-result-"
            )
        )
        XCTAssertTrue(
            waitForMinimumElementCount(resultRows, 2, timeout: 10),
            "Global search must return both exact fixture matches"
        )
        XCTAssertTrue(
            app.staticTexts["Global Needle Alpha.txt"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(
            app.staticTexts["Global Needle Beta.txt"]
                .waitForExistence(timeout: 10)
        )

        let visibleResults = existingElements(in: resultRows).sorted {
            $0.frame.minY < $1.frame.minY
        }
        let firstResult = try XCTUnwrap(visibleResults.first)
        let secondResult = try XCTUnwrap(visibleResults.dropFirst().first)
        XCTAssertEqual(firstResult.value as? String, "Selected")

        readyGlobalSearchField.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(
            waitForValue("Selected", on: secondResult, timeout: 3),
            "Down Arrow must move the active global-search result"
        )
        let selectedResultName = secondResult.label
        XCTAssertFalse(selectedResultName.isEmpty)

        readyGlobalSearchField.typeKey(.return, modifierFlags: [])
        let revealedRows = rows(named: selectedResultName)
        XCTAssertTrue(revealedRows.firstMatch.waitForExistence(timeout: 10))
        let revealedRow = revealedRows.firstMatch
        let revealedCell = try XCTUnwrap(containingCell(for: revealedRow))
        XCTAssertTrue(
            waitForSelectedStatus(true, on: revealedCell, timeout: 5),
            "Return must reveal and select the global-search result in its folder"
        )
    }

    func testGlobalSearchRanksAndSelectsCompactWhitespaceMatch() throws {
        XCTAssertTrue(
            rows(named: "Source Item.txt").firstMatch.waitForExistence(timeout: 10)
        )

        let globalSearchField = app.descendants(matching: .any)[
            "global-search-text-field"
        ]
        XCTAssertTrue(globalSearchField.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForEnabled(globalSearchField, timeout: 10),
            "Global search indexing did not finish"
        )

        globalSearchField.click()
        globalSearchField.typeText("api design")

        let resultRows = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "global-search-result-"
            )
        )
        let compactResult = resultRows.matching(
            NSPredicate(format: "label == %@", "apidesign.pdf")
        ).firstMatch
        XCTAssertTrue(compactResult.waitForExistence(timeout: 10))

        let visibleResults = existingElements(in: resultRows).sorted {
            $0.frame.minY < $1.frame.minY
        }
        let firstResult = try XCTUnwrap(visibleResults.first)
        XCTAssertEqual(firstResult.label, "apidesign.pdf")
        XCTAssertEqual(firstResult.value as? String, "Selected")
    }

    func testGlobalSearchOffersContentModes() {
        XCTAssertTrue(
            rows(named: "Source Item.txt").firstMatch.waitForExistence(timeout: 10)
        )

        let globalSearchField = app.descendants(matching: .any)[
            "global-search-text-field"
        ]
        XCTAssertTrue(globalSearchField.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForEnabled(globalSearchField, timeout: 10),
            "Global search indexing did not finish"
        )
        let readyGlobalSearchField = app.descendants(matching: .any)[
            "global-search-text-field"
        ]
        readyGlobalSearchField.click()
        readyGlobalSearchField.typeText("grep-only-phrase")

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
        try XCTSkipIf(
            ExplorerFeatureFlagsForUITests.nearbyTransferEnabled == false,
            "Nearby Transfer is temporarily disabled for App Review."
        )

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

    private var applicationBundleURL: URL {
        fixtureRootURL.appending(
            path: "Fixture App.app",
            directoryHint: .isDirectory
        )
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

    private var globalSearchCompactNameURL: URL {
        globalSearchFolderURL.appending(
            path: "apidesign.pdf",
            directoryHint: .notDirectory
        )
    }

    private var globalSearchDistractorURL: URL {
        globalSearchFolderURL.appending(
            path: "A Practical Introduction Design Guide.pdf",
            directoryHint: .notDirectory
        )
    }

    private func rows(named name: String) -> XCUIElementQuery {
        app.groups.matching(
            NSPredicate(format: "identifier ENDSWITH %@", "-\(name)")
        )
    }

    private func element(withIdentifier identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@", identifier)
        ).firstMatch
    }

    private func fileContextMenuButton(named name: String) -> XCUIElement {
        app.descendants(matching: .any)["file-item-context-menu"]
            .buttons[name]
    }

    private func scrollFileContextMenuTo(_ button: XCUIElement) {
        let menu = app.scrollViews["file-item-context-menu"]
        // Installed terminal apps change this menu's length. Bring the whole
        // action into view instead of assuming it fits without scrolling.
        for _ in 0..<5 {
            if menu.frame.insetBy(dx: 2, dy: 2).contains(button.frame), button.isHittable { return }
            menu.scroll(byDeltaX: 0, deltaY: button.frame.maxY > menu.frame.maxY ? 120 : -120)
        }
        XCTAssertTrue(button.isHittable)
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

    private func waitForMinimumElementCount(
        _ query: XCUIElementQuery,
        _ minimumCount: Int,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let query = object as? XCUIElementQuery else { return false }
            return query.count >= minimumCount
        }
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: query
        )
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

    private func makeApplicationBundle(at applicationURL: URL) throws {
        let contentsURL = applicationURL.appending(
            path: "Contents",
            directoryHint: .isDirectory
        )
        let executableDirectoryURL = contentsURL.appending(
            path: "MacOS",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: executableDirectoryURL,
            withIntermediateDirectories: true
        )

        let info: [String: Any] = [
            "CFBundleExecutable": "FixtureApp",
            "CFBundleIdentifier": "dev.finallyexplorer.ui-fixture",
            "CFBundleName": "Fixture App",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1",
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try infoData.write(to: contentsURL.appending(path: "Info.plist"))
        let executableURL = executableDirectoryURL.appending(path: "FixtureApp")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(
            to: executableURL
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path(percentEncoded: false)
        )
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

private enum ExplorerFeatureFlagsForUITests {
    static let nearbyTransferEnabled = false
}
