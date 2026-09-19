#if FINALLY_EXPLORER_NATIVE_SANDBOX_ACCEPTANCE
import XCTest

final class NativeSandboxFileMutationUITests: XCTestCase {
    private var app: XCUIApplication?
    private var fixture: NativeSandboxMutationFixture?

    override func setUpWithError() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        let identifier = try XCTUnwrap(environment["FINALLY_EXPLORER_NATIVE_QA_BUNDLE_ID"])
        let path = try XCTUnwrap(environment["FINALLY_EXPLORER_NATIVE_QA_APP_PATH"])
        guard identifier.hasPrefix("com.temelgunaydin.finallyexplorer.sandboxqa.files") else {
            throw NSError(domain: "NativeSandboxFileMutationUITests", code: 1)
        }
        XCTAssertEqual(Bundle(url: URL(filePath: path))?.bundleIdentifier, identifier)
        fixture = try NativeSandboxMutationFixture(path: XCTUnwrap(environment["FINALLY_EXPLORER_NATIVE_QA_FOLDER"]))
        let application = XCUIApplication(bundleIdentifier: identifier)
        application.launchArguments = []
        application.launchEnvironment = [:]
        app = application
        application.launch()
        XCTAssertTrue(application.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(application.windows.firstMatch.waitForExistence(timeout: 10))
        application.activate()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
        try fixture?.assertOriginalsUnchanged()
        // Retain grants, originals and generated artifacts, including failures.
        // Never delete user data, reset preferences or silently clean a fixture.
    }

    override func record(_ issue: XCTIssue) {
        if issue.type == .assertionFailure, let app { evidence("Native mutation failure", in: app) }
        super.record(issue)
    }

    func testNativeCrossPaneCopyAndMove() throws {
        let application = try XCTUnwrap(app)
        let fixture = try XCTUnwrap(fixture)
        let (source, destination) = try openSourceAndDestination(fixture, in: application)

        // Paste targets the displayed directory, even while a FILE is selected.
        select(row("FECopy.txt", in: source))
        application.typeKey("c", modifierFlags: .command)
        select(row("Anchor.txt", in: destination))
        application.typeKey("v", modifierFlags: .command)
        XCTAssertTrue(row("FECopy.txt", in: destination).waitForExistence(timeout: 15))
        try fixture.assertText(NativeSandboxMutationFixture.copyText, at: fixture.destination.appending(path: "FECopy.txt"))
        try fixture.assertOriginalsUnchanged()

        application.typeKey("v", modifierFlags: .command)
        let duplicate = row("FECopy copy.txt", in: destination)
        XCTAssertTrue(duplicate.waitForExistence(timeout: 15))
        try fixture.assertText(NativeSandboxMutationFixture.copyText, at: fixture.destination.appending(path: "FECopy copy.txt"))
        evidence("Copy collision preserves both files", in: application)

        // Move only the copy just created by this test, never the original.
        select(duplicate)
        application.typeKey("x", modifierFlags: .command)
        select(row("FECopy.txt", in: source))
        application.typeKey("v", modifierFlags: .command)
        XCTAssertTrue(row("FECopy copy.txt", in: source).waitForExistence(timeout: 15))
        XCTAssertTrue(duplicate.waitForNonExistence(timeout: 5))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.appending(path: "FECopy copy.txt").path))
        try fixture.assertText(NativeSandboxMutationFixture.copyText, at: fixture.source.appending(path: "FECopy copy.txt"))
        try fixture.assertOriginalsUnchanged()
        XCTAssertEqual(try fixture.children(fixture.source), ["FECopy copy.txt", "FECopy.txt", "Package"])
        XCTAssertEqual(try fixture.children(fixture.destination), ["Anchor.txt", "FECopy.txt"])
        evidence("Native cross-pane copy and move verified bytes", in: application)
    }

    func testNativeMoveCollisionPreservesBothFiles() throws {
        let application = try XCTUnwrap(app)
        let fixture = try XCTUnwrap(fixture)
        let (source, destination) = try openSourceAndDestination(fixture, in: application)
        select(row("FECopy.txt", in: source))
        application.typeKey("c", modifierFlags: .command)
        select(row("Anchor.txt", in: destination))
        application.typeKey("v", modifierFlags: .command)
        XCTAssertTrue(row("FECopy.txt", in: destination).waitForExistence(timeout: 15))
        try fixture.assertText(NativeSandboxMutationFixture.copyText, at: fixture.destination.appending(path: "FECopy.txt"))

        // A move collision must fail without overwriting either original/copy.
        select(row("FECopy.txt", in: destination))
        application.typeKey("x", modifierFlags: .command)
        select(row("FECopy.txt", in: source))
        application.typeKey("v", modifierFlags: .command)
        let failure = try collisionDialog(in: application, destination: fixture.source.appending(path: "FECopy.txt"))
        try fixture.assertOriginalsUnchanged()
        try fixture.assertText(NativeSandboxMutationFixture.copyText, at: fixture.destination.appending(path: "FECopy.txt"))
        failure.buttons["OK"].click()
        XCTAssertTrue(failure.waitForNonExistence(timeout: 5))
        evidence("Move collision keeps both sources intact", in: application)
    }

    func testNativeContextMenuZIPPreservesContentsAndCollisions() throws {
        let application = try XCTUnwrap(app)
        let fixture = try XCTUnwrap(fixture)
        try grantAndOpenSource(fixture, in: application)
        let source = paneQuery(application).firstMatch
        assertPath(fixture.source, in: source)
        try compress(row("Package", in: source), in: application)
        XCTAssertTrue(row("Package.zip", in: source).waitForExistence(timeout: 25))
        let originalArchive = try Data(contentsOf: fixture.source.appending(path: "Package.zip"))
        let folderEntries = ["Package/Notes/Résumé.txt": NativeSandboxMutationFixture.noteText,
                             "Package/.hidden": NativeSandboxMutationFixture.hiddenText]
        try fixture.assertArchive("Package.zip", contains: folderEntries)
        try compress(row("Package", in: source), in: application)
        XCTAssertTrue(row("Package 2.zip", in: source).waitForExistence(timeout: 25))
        XCTAssertEqual(try Data(contentsOf: fixture.source.appending(path: "Package.zip")), originalArchive)
        try fixture.assertArchive("Package 2.zip", contains: folderEntries)

        try compress(row("FECopy.txt", in: source), in: application)
        XCTAssertTrue(row("FECopy.txt.zip", in: source).waitForExistence(timeout: 25))
        try fixture.assertArchive("FECopy.txt.zip", contains: ["FECopy.txt": NativeSandboxMutationFixture.copyText])
        try fixture.assertOriginalsUnchanged()
        XCTAssertEqual(try fixture.children(fixture.source),
                       ["FECopy.txt", "FECopy.txt.zip", "Package", "Package 2.zip", "Package.zip"])
        XCTAssertEqual(try fixture.children(fixture.destination), ["Anchor.txt"])
        XCTAssertTrue(source.isEnabled)
        evidence("Native context-menu ZIP verified bytes", in: application)
    }

    private func grantAndOpenSource(_ fixture: NativeSandboxMutationFixture, in application: XCUIApplication) throws {
        let home = application.descendants(matching: .any)["sidebar-built-in-home"]
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        home.click()
        let choose = application.buttons["allow-folder-access"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10), "Do not grant Home or a parent to make this test pass.")
        choose.click()
        selectNativeFolder(fixture.root, in: application)
        let sourceFolder = row("Source", in: application)
        XCTAssertTrue(sourceFolder.waitForExistence(timeout: 10))
        XCTAssertTrue(row("Destination", in: application).exists)
        try open(sourceFolder, in: application)
        XCTAssertTrue(row("FECopy.txt", in: application).waitForExistence(timeout: 10))
        waitForPaneCount(1, in: application)
    }

    private func openSourceAndDestination(_ fixture: NativeSandboxMutationFixture,
                                          in application: XCUIApplication) throws -> (XCUIElement, XCUIElement) {
        try grantAndOpenSource(fixture, in: application)
        application.buttons["Split Right"].click()
        waitForPaneCount(2, in: application)
        let panes = paneQuery(application).allElementsBoundByIndex.sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertEqual(panes.count, 2)
        let source = panes[0]
        let destination = panes[1]
        XCTAssertTrue(destination.buttons["Back"].waitForExistence(timeout: 5))
        destination.buttons["Back"].click()
        let destinationFolder = row("Destination", in: destination)
        XCTAssertTrue(destinationFolder.waitForExistence(timeout: 5))
        try open(destinationFolder, in: application)
        XCTAssertTrue(row("Anchor.txt", in: destination).waitForExistence(timeout: 5))
        XCTAssertTrue(row("FECopy.txt", in: source).exists)
        assertPath(fixture.source, in: source)
        assertPath(fixture.destination, in: destination)
        evidence("Narrow-grant source and destination panes", in: application)
        return (source, destination)
    }

    private func compress(_ item: XCUIElement, in application: XCUIApplication) throws {
        XCTAssertTrue(item.exists)
        item.rightClick()
        let menu = application.descendants(matching: .any)["file-item-context-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        let command = menu.buttons["Compress to ZIP"]
        XCTAssertTrue(command.isEnabled)
        XCTAssertTrue(command.isHittable)
        command.click()
        XCTAssertTrue(menu.waitForNonExistence(timeout: 5))
    }

    private func collisionDialog(in application: XCUIApplication, destination: URL) throws -> XCUIElement {
        // This remains a separate acceptance gate: on the September 19 host
        // the visible alert was absent from XCTest's accessibility tree.
        // Do not attach to/launch a guessed system service or dismiss blindly.
        let alert = application.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "Native collision alert must be accessible to XCTest.")
        let text = alert.staticTexts.allElementsBoundByIndex.map {
            [$0.label, $0.value as? String ?? ""].joined(separator: " ")
        }.joined(separator: "\n")
        XCTAssertTrue(text.contains("File Operation Failed"))
        XCTAssertTrue(text.contains("already exists"))
        XCTAssertTrue(text.contains(destination.lastPathComponent))
        XCTAssertTrue(text.contains(destination.deletingLastPathComponent().lastPathComponent))
        XCTAssertTrue(alert.buttons["OK"].exists)
        return alert
    }

    private func select(_ item: XCUIElement) {
        XCTAssertTrue(item.exists)
        // Avoid favorite/trash child controls inside the row.
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).click()
    }

    private func open(_ item: XCUIElement, in application: XCUIApplication) throws {
        let center = CGPoint(x: item.frame.midX, y: item.frame.midY)
        let cell = try XCTUnwrap(application.cells.allElementsBoundByIndex
            .filter { $0.frame.contains(center) }.min { $0.frame.width < $1.frame.width })
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).doubleClick()
    }

    private func row(_ name: String, in element: XCUIElement) -> XCUIElement {
        element.groups.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
                                            "file-row-", "-\(name)")).firstMatch
    }

    private func assertPath(_ expected: URL, in pane: XCUIElement) {
        let path = pane.descendants(matching: .any)["pane-location-path"]
        XCTAssertTrue(path.exists)
        // macOS static text can expose its full text as AXValue, not AXTitle.
        // Never treat an empty label as a relative URL (the runner's cwd).
        let candidates = [path.label, path.value as? String ?? ""].filter { $0.hasPrefix("/") }
        XCTAssertTrue(candidates.contains {
            URL(filePath: $0).standardizedFileURL.resolvingSymlinksInPath().pathComponents
                == expected.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        }, "Expected exact pane path \(expected.path). Actual: \(path.debugDescription)")
    }

    private func paneQuery(_ application: XCUIApplication) -> XCUIElementQuery {
        application.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "workspace-pane-"))
    }

    private func waitForPaneCount(_ count: Int, in application: XCUIApplication) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.paneQuery(application).count == count
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
    }

    private func selectNativeFolder(_ folder: URL, in application: XCUIApplication) {
        let panel = application.windows.containing(.button, identifier: "Allow Access").firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        application.typeKey("g", modifierFlags: [.command, .shift])
        let sheet = panel.sheets["GoToWindow"]
        let field = sheet.textFields["PathTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        application.typeKey("a", modifierFlags: .command)
        application.typeKey(.delete, modifierFlags: [])
        for character in folder.path { application.typeKey(String(character), modifierFlags: []) }
        XCTAssertEqual(field.value as? String, folder.path)
        application.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", folder.lastPathComponent),
                                                object: panel.popUpButtons["where popup"])
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        panel.buttons["Allow Access"].click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
    }

    private func evidence(_ name: String, in application: XCUIApplication) {
        let window = application.windows.firstMatch
        guard window.exists else { return }
        let hierarchy = XCTAttachment(string: application.debugDescription)
        hierarchy.name = name
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let screenshot = XCTAttachment(screenshot: window.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
#endif
