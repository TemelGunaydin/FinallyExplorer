// Opt-in native acceptance against a separately built, sandboxed QA app.
// Ordinary test runs do not compile this suite. Never target the user's app.
#if FINALLY_EXPLORER_NATIVE_SANDBOX_ACCEPTANCE
import XCTest

final class NativeSandboxAcceptanceUITests: XCTestCase {
    private var app: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
        let bundleID = try XCTUnwrap(
            ProcessInfo.processInfo.environment["FINALLY_EXPLORER_NATIVE_QA_BUNDLE_ID"],
            "Provide the separately installed, preflighted Sandbox QA bundle identifier."
        )
        guard bundleID.hasPrefix("com.temelgunaydin.finallyexplorer.sandboxqa.") else {
            throw NSError(domain: "NativeSandboxAcceptance", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Refusing to launch a non-QA app."
            ])
        }

        let application = XCUIApplication(bundleIdentifier: bundleID)
        // No --ui-testing flag, fixture-root override, injected defaults suite,
        // or mock services: the separately signed Release app runs normally.
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
        // Preserve the QA container so relaunch tests exercise real persistence.
        // Never delete/reset an app container or a user's existing permissions.
    }

    func testNativeFolderChooserCancelKeepsRememberedAccessUnchanged() throws {
        let application = try XCTUnwrap(app)
        let settings = openFolderAccessSettings(in: application)
        let allowFolder = settings.buttons["settings-allow-folder"]
        XCTAssertTrue(allowFolder.waitForExistence(timeout: 5), settings.debugDescription)
        let rememberedButtons = settings.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Forget access to ")
        )
        let rememberedCount = rememberedButtons.count
        let wasEmpty = settings.staticTexts["No folders remembered yet."].exists

        allowFolder.click()
        let panel = application.windows.containing(
            .button, identifier: "Allow Access"
        ).firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5), application.debugDescription)
        let cancel = panel.buttons["Cancel"]
        XCTAssertTrue(cancel.exists, panel.debugDescription)
        cancel.click()

        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        XCTAssertTrue(allowFolder.isEnabled)
        XCTAssertEqual(rememberedButtons.count, rememberedCount)
        XCTAssertEqual(settings.staticTexts["No folders remembered yet."].exists, wasEmpty)
        XCTAssertFalse(settings.descendants(matching: .any)["folder-access-error"].exists)

        let evidence = XCTAttachment(string: settings.debugDescription)
        evidence.name = "Native folder chooser cancelled without changing remembered access"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    func testNativeNarrowFolderGrantPersistsAndForgetSurvivesRelaunch() throws {
        let application = try XCTUnwrap(app)
        let fixturePath = try XCTUnwrap(
            ProcessInfo.processInfo.environment["FINALLY_EXPLORER_NATIVE_QA_FOLDER"],
            "Prepare a fresh /private/tmp/fe-native-* folder with the synthetic SandboxMarker.txt fixture."
        )
        let folder = URL(filePath: fixturePath, directoryHint: .isDirectory).standardizedFileURL
        let folderName = folder.lastPathComponent
        let parentComponents = Array(folder.pathComponents.dropLast())
        let isTemporaryRoot = parentComponents == ["/", "private", "tmp"] || parentComponents == ["/", "tmp"]
        guard isTemporaryRoot, folderName.hasPrefix("fe-native-") else {
            throw NSError(domain: "NativeSandboxAcceptance", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Refusing a broad or non-QA fixture path: \(folder.path)."
            ])
        }
        let folderValues = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        XCTAssertEqual(folderValues.isDirectory, true)
        XCTAssertEqual(folderValues.isSymbolicLink, false)
        let marker = folder.appending(path: "SandboxMarker.txt")
        let original = Data("Synthetic native Sandbox acceptance fixture.\n".utf8)
        XCTAssertEqual(try Data(contentsOf: marker), original)
        // The operator prepares a short path to avoid slow long-path keyboard
        // synthesis. The UI runner only reads it; no filesystem exception is
        // added to the separately signed QA app. Preserve fixtures for inspection.

        var settings = openFolderAccessSettings(in: application)
        let forgetLabel = "Forget access to \(folderName)"
        let rememberedPredicate = NSPredicate(format: "label BEGINSWITH %@", "Forget access to ")
        let countBefore = settings.buttons.matching(rememberedPredicate).count
        XCTAssertFalse(settings.buttons[forgetLabel].exists)
        settings.buttons["settings-allow-folder"].click()

        let panel = application.windows.containing(.button, identifier: "Allow Access").firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5), application.debugDescription)
        application.typeKey("g", modifierFlags: [.command, .shift])
        let goToSheet = panel.sheets["GoToWindow"]
        let goToField = goToSheet.textFields["PathTextField"]
        XCTAssertTrue(goToField.waitForExistence(timeout: 5), goToSheet.debugDescription)
        goToField.click()
        goToField.typeKey("a", modifierFlags: .command)
        // Bulk typeText times out under this app's keyboard-event isolation.
        // Match the existing UI suite's real key-event entry strategy.
        // The field is already focused: avoid resolving its full window/sheet
        // query for every character. Verify the complete value before accepting.
        for character in folder.path {
            application.typeKey(String(character), modifierFlags: [])
        }
        XCTAssertEqual(goToField.value as? String, folder.path)
        goToField.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(goToSheet.waitForNonExistence(timeout: 5))

        let selectedFolder = panel.popUpButtons["where popup"]
        let correctFolder = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", folderName), object: selectedFolder
        )
        XCTAssertEqual(XCTWaiter.wait(for: [correctFolder], timeout: 5), .completed, selectedFolder.debugDescription)
        XCTAssertTrue(panel.buttons["Allow Access"].isEnabled)
        panel.buttons["Allow Access"].click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        XCTAssertTrue(settings.buttons[forgetLabel].waitForExistence(timeout: 5), settings.debugDescription)
        assertRememberedPath(folder, in: settings)
        XCTAssertEqual(settings.buttons.matching(rememberedPredicate).count, countBefore + 1)

        quitAndRelaunch(application)
        settings = openFolderAccessSettings(in: application)
        XCTAssertTrue(settings.buttons[forgetLabel].waitForExistence(timeout: 5), settings.debugDescription)
        assertRememberedPath(folder, in: settings)
        XCTAssertEqual(settings.buttons.matching(rememberedPredicate).count, countBefore + 1)
        let restored = XCTAttachment(string: settings.debugDescription)
        restored.name = "Native narrow folder bookmark restored after ordinary quit and relaunch"
        restored.lifetime = .keepAlways
        add(restored)

        settings.buttons[forgetLabel].click()
        XCTAssertTrue(settings.buttons[forgetLabel].waitForNonExistence(timeout: 5))
        XCTAssertTrue(settings.staticTexts[
            "Folder access will no longer be restored after you quit and reopen the app."
        ].exists)
        quitAndRelaunch(application)
        settings = openFolderAccessSettings(in: application)
        XCTAssertFalse(settings.buttons[forgetLabel].exists)
        XCTAssertEqual(settings.buttons.matching(rememberedPredicate).count, countBefore)
        XCTAssertEqual(try Data(contentsOf: marker), original)
    }

    private func openFolderAccessSettings(in application: XCUIApplication) -> XCUIElement {
        application.typeKey(",", modifierFlags: .command)
        let settings = application.windows.containing(.any, identifier: "explorer-settings-view").firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5), application.debugDescription)
        let tab = settings.toolbars.buttons["Folder Access"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), settings.debugDescription)
        tab.click()
        XCTAssertTrue(settings.buttons["settings-allow-folder"].waitForExistence(timeout: 5), settings.debugDescription)
        return settings
    }

    private func assertRememberedPath(_ folder: URL, in settings: XCUIElement,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let pathTexts = settings.staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH %@ OR label BEGINSWITH %@", "/", "/")
        )
        let paths = pathTexts.allElementsBoundByIndex.map { ($0.value as? String) ?? $0.label }
        let expected = folder.resolvingSymlinksInPath().pathComponents
        XCTAssertTrue(paths.contains {
            URL(filePath: $0, directoryHint: .isDirectory).resolvingSymlinksInPath().pathComponents == expected
        }, "Expected \(folder.path); displayed paths: \(paths)", file: file, line: line)
    }

    private func quitAndRelaunch(_ application: XCUIApplication) {
        application.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(application.wait(for: .notRunning, timeout: 5))
        application.launch()
        XCTAssertTrue(application.wait(for: .runningForeground, timeout: 10))
    }
}
#endif
