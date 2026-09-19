// Opt-in acceptance against a separately signed Release app, without UI fixtures
// or XCTest's filesystem exceptions in the application under test.
#if FINALLY_EXPLORER_NATIVE_SANDBOX_ACCEPTANCE
import XCTest

final class NativeSandboxFileAccessUITests: XCTestCase {
    private var app: XCUIApplication?
    private var fixture: NativeSandboxFileFixture?

    override func setUpWithError() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        let bundleID = try XCTUnwrap(environment["FINALLY_EXPLORER_NATIVE_QA_BUNDLE_ID"])
        let appPath = try XCTUnwrap(environment["FINALLY_EXPLORER_NATIVE_QA_APP_PATH"])
        guard bundleID.hasPrefix("com.temelgunaydin.finallyexplorer.sandboxqa.files") else {
            throw NSError(domain: "NativeSandboxFileAccess", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Refusing to launch a non-file-QA app."
            ])
        }
        let bundle = try XCTUnwrap(Bundle(url: URL(filePath: appPath)))
        XCTAssertEqual(bundle.bundleIdentifier, bundleID)
        let preparedFixture = try NativeSandboxFileFixture(
            path: XCTUnwrap(environment["FINALLY_EXPLORER_NATIVE_QA_FOLDER"])
        )
        try preparedFixture.assertOriginalsUnchanged()
        fixture = preparedFixture

        let application = XCUIApplication(bundleIdentifier: bundleID)
        application.launchArguments = []
        application.launchEnvironment = [:]
        app = application
        application.launch()
        XCTAssertTrue(application.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(application.windows.firstMatch.waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
        try fixture?.assertOriginalsUnchanged()
        // Preserve native grants, favorites and the synthetic evidence. Never
        // reset an app container or production preferences to make a test pass.
    }

    override func record(_ issue: XCTIssue) {
        if issue.type == .assertionFailure, let app {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Native file access failure hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        super.record(issue)
    }

    func testRestoredNarrowGrantSupportsListingPreviewAndLocalSearch() throws {
        let application = try XCTUnwrap(app)
        let fixture = try XCTUnwrap(fixture)
        try grantAndRestoreSource(fixture, in: application)

        if application.buttons["Hide Preview"].exists {
            application.buttons["Hide Preview"].click()
        }
        let search = application.textFields["pane-search-field"]
        replaceText("NativeNeedle", in: search, application: application)
        XCTAssertTrue(row(named: NativeSandboxFileFixture.needleName, in: application)
            .waitForExistence(timeout: 15))
        XCTAssertTrue(row(named: "Control.txt", in: application).waitForNonExistence(timeout: 5))

        replaceText("native-token-7319", in: search, application: application)
        let contents = application.radioButtons["Contents"]
        XCTAssertTrue(contents.waitForExistence(timeout: 5))
        contents.click()
        XCTAssertTrue(row(named: NativeSandboxFileFixture.needleName, in: application)
            .waitForExistence(timeout: 20), "Native content search must read the granted document.")
        XCTAssertTrue(row(named: "Control.txt", in: application).waitForNonExistence(timeout: 5))
        let regex = application.radioButtons["Regex"]
        XCTAssertTrue(regex.waitForExistence(timeout: 5))
        regex.click()
        replaceText("native-token-[0-9]{4}", in: search, application: application)
        XCTAssertTrue(row(named: NativeSandboxFileFixture.needleName, in: application)
            .waitForExistence(timeout: 15))
        attachFixtureEvidence("Restored native scope supports regex content search", in: application)

        replaceText("absent-token-9999", in: search, application: application)
        XCTAssertTrue(row(named: NativeSandboxFileFixture.needleName, in: application)
            .waitForNonExistence(timeout: 10), "Search must not retain the previous result.")
        replaceText("", in: search, application: application)
        XCTAssertTrue(row(named: "Control.txt", in: application).waitForExistence(timeout: 10))
        try fixture.assertOriginalsUnchanged()
    }

    func testGlobalSearchDiscoversRestoredNarrowGrantThroughUngrantedAncestors() throws {
        let application = try XCTUnwrap(app)
        let fixture = try XCTUnwrap(fixture)
        try grantAndRestoreSource(fixture, in: application)
        let search = application.descendants(matching: .any)["global-search-text-field"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: search)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        replaceText("FENativeNeedle", in: search, application: application)
        let result = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@",
            "global-search-result-", NativeSandboxFileFixture.needleName
        )).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 45),
                      "Global search must discover the granted file without a grant to its parents.")
        attachFixtureEvidence("Global name search discovers native narrow grant", in: application)

        replaceText("native-token-7319", in: search, application: application)
        XCTAssertTrue(result.waitForNonExistence(timeout: 10),
                      "The name result must clear before validating content search.")
        let contents = application.radioGroups["global-search-scope-picker"].radioButtons["Contents"]
        XCTAssertTrue(contents.waitForExistence(timeout: 5))
        contents.click()
        XCTAssertTrue(result.waitForExistence(timeout: 45),
                      "Global content search must read files under the narrow native grant.")
        attachFixtureEvidence("Global content search discovers native narrow grant", in: application)

        replaceText("absent-token-9999", in: search, application: application)
        XCTAssertTrue(result.waitForNonExistence(timeout: 10), "Global search must clear stale content results.")
        let regex = application.radioGroups["global-search-content-mode-picker"].radioButtons["Regex"]
        XCTAssertTrue(regex.waitForExistence(timeout: 5))
        regex.click()
        replaceText("native-token-[0-9]{4}", in: search, application: application)
        XCTAssertTrue(result.waitForExistence(timeout: 45),
                      "Global regex search must read the same narrowly granted document.")
        attachFixtureEvidence("Global regex search discovers native narrow grant", in: application)
    }

    private func grantAndRestoreSource(_ fixture: NativeSandboxFileFixture,
                                       in application: XCUIApplication) throws {

        // Home has no read grant in a fresh QA identity. Do not approve a macOS
        // privacy prompt or grant Home; select only the explicit synthetic root.
        let home = application.descendants(matching: .any)["sidebar-built-in-home"]
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        application.activate()
        XCTAssertTrue(application.wait(for: .runningForeground, timeout: 5))
        home.click()
        let choose = application.buttons["allow-folder-access"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10),
                      "The fresh QA app must expose permission recovery before selecting the fixture.")
        choose.click()
        selectNativeFolder(fixture.root, in: application)

        let source = row(named: "QA Source", in: application)
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        XCTAssertTrue(row(named: "QA Destination", in: application).exists)
        let favorite = application.buttons["Add QA Source to Favorites"]
        if favorite.exists {
            favorite.click()
        } else {
            // A repeat run can retain this exact synthetic folder's favorite;
            // never reset preferences or choose an unrelated remembered row.
            XCTAssertTrue(application.buttons["Remove QA Source from Favorites"].exists)
        }
        let favorites = application.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "sidebar-favorite-")
        )
        XCTAssertEqual(favorites.count, 1, "The dedicated QA identity must not contain unrelated favorites.")
        let favoriteID = favorites.firstMatch.identifier
        XCTAssertFalse(favoriteID.isEmpty)
        try cell(for: source, in: application)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).doubleClick()
        assertListingAndPreview(fixture, in: application)
        attachFixtureEvidence("Native folder grant reads exact JSON", in: application)

        application.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(application.wait(for: .notRunning, timeout: 5))
        application.launch()
        XCTAssertTrue(application.wait(for: .runningForeground, timeout: 10))
        let restoredFavorite = application.descendants(matching: .any)[favoriteID]
        XCTAssertTrue(restoredFavorite.waitForExistence(timeout: 10))
        application.activate()
        XCTAssertTrue(application.wait(for: .runningForeground, timeout: 5))
        restoredFavorite.click()
        // No native chooser is opened after relaunch. These exact bytes must be
        // read by the QA app using its restored parent-folder scope.
        assertListingAndPreview(fixture, in: application)
        XCTAssertFalse(application.buttons["allow-folder-access"].exists)
        attachFixtureEvidence("Restored bookmark reads exact JSON", in: application)
    }

    private func assertListingAndPreview(_ fixture: NativeSandboxFileFixture,
                                         in application: XCUIApplication,
                                         file: StaticString = #filePath, line: UInt = #line) {
        let needle = row(named: NativeSandboxFileFixture.needleName, in: application)
        XCTAssertTrue(needle.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertTrue(row(named: "Control.txt", in: application).exists, file: file, line: line)
        needle.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).click()
        let preview = application.textViews["text-file-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5), file: file, line: line)
        let exactText = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", NativeSandboxFileFixture.needleText), object: preview
        )
        XCTAssertEqual(XCTWaiter.wait(for: [exactText], timeout: 10), .completed,
                       "The Release app must display the entire granted file, not a cached test value.",
                       file: file, line: line)
    }

    private func selectNativeFolder(_ folder: URL, in application: XCUIApplication) {
        let panel = application.windows.containing(.button, identifier: "Allow Access").firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        application.typeKey("g", modifierFlags: [.command, .shift])
        let sheet = panel.sheets["GoToWindow"]
        let field = sheet.textFields["PathTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceText(folder.path, in: field, application: application)
        application.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        let location = panel.popUpButtons["where popup"]
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", folder.lastPathComponent), object: location
        )
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        panel.buttons["Allow Access"].click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
    }

    private func replaceText(_ text: String, in field: XCUIElement, application: XCUIApplication) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        application.typeKey("a", modifierFlags: .command)
        application.typeKey(.delete, modifierFlags: [])
        for character in text { application.typeKey(String(character), modifierFlags: []) }
        XCTAssertEqual(field.value as? String, text)
    }

    private func row(named name: String, in application: XCUIApplication) -> XCUIElement {
        application.groups.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "file-row-", "-\(name)"
        )).firstMatch
    }

    private func cell(for row: XCUIElement, in application: XCUIApplication) throws -> XCUIElement {
        let center = CGPoint(x: row.frame.midX, y: row.frame.midY)
        return try XCTUnwrap(application.cells.allElementsBoundByIndex
            .filter { $0.frame.contains(center) }.min { $0.frame.width < $1.frame.width })
    }

    private func attachFixtureEvidence(_ name: String, in application: XCUIApplication) {
        let window = application.windows.firstMatch
        let hierarchy = XCTAttachment(string: window.debugDescription)
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
