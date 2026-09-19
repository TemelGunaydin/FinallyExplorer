// Opt-in interaction checks against a separately installed QA app.
// The app only browses its own bundled legal documents; no user files are used.
#if FINALLY_EXPLORER_LAYOUT_ACCEPTANCE
import XCTest

final class WorkspaceLayoutUITests: XCTestCase {
    private var app: XCUIApplication?
    private var privacyURL: URL?
    private var originalPrivacyData: Data?
    private var evidenceDirectory: URL?

    override func setUpWithError() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        let bundleID = try XCTUnwrap(environment["FINALLY_EXPLORER_LAYOUT_QA_BUNDLE_ID"])
        let appPath = try XCTUnwrap(environment["FINALLY_EXPLORER_LAYOUT_QA_APP_PATH"])
        guard bundleID.hasPrefix("com.temelgunaydin.finallyexplorer.sandboxqa.layout") else {
            throw NSError(domain: "WorkspaceLayoutUITests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Refusing to launch a non-layout-QA app."
            ])
        }
        let bundle = try XCTUnwrap(Bundle(url: URL(filePath: appPath)))
        XCTAssertEqual(bundle.bundleIdentifier, bundleID)
        let resources = try XCTUnwrap(bundle.resourceURL)
        let privacy = resources.appending(path: "PrivacyPolicy.md")
        originalPrivacyData = try Data(contentsOf: privacy)
        privacyURL = privacy
        let evidence = FileManager.default.temporaryDirectory
            .appending(path: "FinallyExplorer-LayoutEvidence-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: false)
        evidenceDirectory = evidence

        let application = XCUIApplication(bundleIdentifier: bundleID)
        application.launchArguments = ["--ui-testing"]
        application.launchEnvironment = [
            "FINALLY_EXPLORER_UI_FIXTURE_ROOT": resources.path,
            "FINALLY_EXPLORER_UI_DEFAULTS_SUITE": "FinallyExplorer.LayoutUITests.\(UUID().uuidString)"
        ]
        app = application
        application.launch()
        XCTAssertTrue(application.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(resourceRows(in: application).firstMatch.waitForExistence(timeout: 10),
                      application.debugDescription)
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
        if let privacyURL, let originalPrivacyData {
            XCTAssertEqual(try Data(contentsOf: privacyURL), originalPrivacyData)
        }
        // Do not reset a container or any production preferences/permissions.
    }

    override func record(_ issue: XCTIssue) {
        if issue.type == .assertionFailure, let app {
            attachEvidence("Failed layout assertion", in: app)
        }
        super.record(issue)
    }

    func testNarrowWindowPreviewAndFourPaneGridKeepControlsInsideTheirPane() throws {
        let application = try XCTUnwrap(app)
        let window = application.windows.firstMatch
        XCTAssertGreaterThanOrEqual(window.frame.width, 980)
        attachEvidence("Initial workspace", in: application)
        assertLayout(in: application, paneCount: 1, previewVisible: true)

        resize(window, to: CGSize(width: 980, height: 720))
        waitForWidth(980, of: window)
        assertLayout(in: application, paneCount: 1, previewVisible: true)

        resourceRows(in: application).firstMatch.click()
        let textPreview = application.textViews["text-file-preview"]
        XCTAssertTrue(textPreview.waitForExistence(timeout: 5))
        let expectedText = String(decoding: try XCTUnwrap(originalPrivacyData), as: UTF8.self)
        let previewLoaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            textPreview.value as? String == expectedText
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [previewLoaded], timeout: 5), .completed,
                       "Preview must display the exact bundled document contents")
        assertLayout(in: application, paneCount: 1, previewVisible: true)
        attachEvidence("Narrow workspace with text preview", in: application)

        application.buttons["Hide Preview"].click()
        XCTAssertTrue(application.buttons["Show Preview"].waitForExistence(timeout: 5))
        assertLayout(in: application, paneCount: 1, previewVisible: false)
        application.buttons["Show Preview"].click()
        XCTAssertTrue(application.buttons["Hide Preview"].waitForExistence(timeout: 5))
        assertLayout(in: application, paneCount: 1, previewVisible: true)

        // The scene's minimum size must reject the formerly broken small frame.
        resize(window, to: CGSize(width: 850, height: 480))
        XCTAssertGreaterThanOrEqual(window.frame.width, 978)
        XCTAssertGreaterThanOrEqual(window.frame.height, 640)
        assertLayout(in: application, paneCount: 1, previewVisible: true)
        attachEvidence("Minimum window clamp", in: application)

        application.buttons["Split Right"].click()
        waitForPaneCount(2, in: application)
        assertLayout(in: application, paneCount: 2, previewVisible: false)
        let rightPane = try XCTUnwrap(panes(in: application).max { $0.frame.minX < $1.frame.minX })
        rightPane.buttons["Split Below"].click()
        waitForPaneCount(3, in: application)
        assertLayout(in: application, paneCount: 3, previewVisible: false)
        let leftPane = try XCTUnwrap(panes(in: application).min { $0.frame.minX < $1.frame.minX })
        leftPane.buttons["Split Below"].click()
        waitForPaneCount(4, in: application)
        assertLayout(in: application, paneCount: 4, previewVisible: false)
        attachEvidence("Minimum window four-pane grid", in: application)

        // Exercise the divider's minimum pane width, not just its initial ratio.
        let divider = application.descendants(matching: .any)["workspace-column-divider"]
        XCTAssertTrue(divider.exists)
        let origin = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        origin.click(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: -150, dy: 0)),
                     withVelocity: .slow, thenHoldForDuration: 0.1)
        assertLayout(in: application, paneCount: 4, previewVisible: false)

        let reset = application.buttons["Reset View"]
        XCTAssertTrue(reset.isHittable)
        reset.click()
        waitForPaneCount(1, in: application)
        assertLayout(in: application, paneCount: 1, previewVisible: true)
        attachEvidence("Reset restores the single-pane preview", in: application)
    }

    private func resize(_ window: XCUIElement, to size: CGSize) {
        let frame = window.frame
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: -2, dy: -2))
        corner.click(forDuration: 0.1,
                     thenDragTo: corner.withOffset(CGVector(dx: size.width - frame.width,
                                                          dy: size.height - frame.height)),
                     withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    private func waitForWidth(_ width: CGFloat, of window: XCUIElement) {
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(window.frame.width - width) <= 3
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
    }

    private func paneQuery(in application: XCUIApplication) -> XCUIElementQuery {
        application.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "workspace-pane-")
        )
    }

    private func panes(in application: XCUIApplication) -> [XCUIElement] {
        paneQuery(in: application).allElementsBoundByIndex.filter(\.exists)
    }

    private func waitForPaneCount(_ count: Int, in application: XCUIApplication) {
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.panes(in: application).count == count
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
    }

    private func resourceRows(in application: XCUIApplication) -> XCUIElementQuery {
        application.descendants(matching: .any).matching(
            NSPredicate(format: "identifier ENDSWITH %@", "-PrivacyPolicy.md")
        )
    }

    private func assertLayout(in application: XCUIApplication, paneCount: Int, previewVisible: Bool,
                              file: StaticString = #filePath, line: UInt = #line) {
        let visiblePanes = panes(in: application)
        XCTAssertEqual(visiblePanes.count, paneCount, file: file, line: line)
        for pane in visiblePanes {
            let bounds = pane.frame.insetBy(dx: -1, dy: -1)
            let identifiers = ["pane-location-menu", "pane-search-field", "pane-location-path"]
            for identifier in identifiers {
                let control = pane.descendants(matching: .any)[identifier]
                XCTAssertTrue(control.exists, identifier, file: file, line: line)
                XCTAssertTrue(bounds.contains(control.frame),
                              "\(identifier) \(control.frame) outside pane \(bounds)", file: file, line: line)
            }
            let buttons = ["New Folder", "pane-terminal-button", "Show Hidden Items", "Split Right", "Split Below"]
            for label in buttons {
                let button = pane.buttons[label]
                XCTAssertTrue(button.exists, label, file: file, line: line)
                XCTAssertTrue(bounds.contains(button.frame),
                              "\(label) \(button.frame) outside pane \(bounds)", file: file, line: line)
                if button.isEnabled { XCTAssertTrue(button.isHittable, label, file: file, line: line) }
            }
            for label in ["Hide Preview", "Show Preview", "Reset View", "Close Pane"] {
                let button = pane.buttons[label]
                if button.exists {
                    XCTAssertTrue(bounds.contains(button.frame), label, file: file, line: line)
                    XCTAssertTrue(button.isHittable, label, file: file, line: line)
                }
            }
            XCTAssertEqual(pane.buttons["Split Right"].frame.midY,
                           pane.buttons["Split Below"].frame.midY, accuracy: 1, file: file, line: line)
            XCTAssertLessThan(pane.buttons["Split Right"].frame.maxX,
                              pane.buttons["Split Below"].frame.minX, file: file, line: line)
            let body = pane.descendants(matching: .any)["pane-directory-body"]
            XCTAssertGreaterThan(body.frame.height, 20, file: file, line: line)
        }
        for first in visiblePanes.indices {
            for second in visiblePanes.indices where second > first {
                XCTAssertFalse(visiblePanes[first].frame.intersects(visiblePanes[second].frame),
                               file: file, line: line)
            }
        }
        let preview = application.descendants(matching: .any)["preview-inspector"]
        if previewVisible {
            XCTAssertTrue(preview.exists, file: file, line: line)
            XCTAssertGreaterThanOrEqual(preview.frame.width, 218, file: file, line: line)
            if let pane = visiblePanes.first {
                XCTAssertLessThanOrEqual(pane.frame.maxX, preview.frame.minX + 1, file: file, line: line)
            }
        } else {
            XCTAssertFalse(preview.exists && preview.frame.width > 1, file: file, line: line)
        }
    }

    private func attachEvidence(_ name: String, in application: XCUIApplication) {
        let window = application.windows.firstMatch
        guard window.exists else { return }
        let captured = window.screenshot()
        let screenshot = XCTAttachment(screenshot: captured)
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: window.debugDescription)
        hierarchy.name = "\(name) — accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        if let evidenceDirectory {
            let path = evidenceDirectory.appending(path: "\(name).png")
            do {
                try captured.pngRepresentation.write(to: path)
                print("LAYOUT_SCREENSHOT: \(path.path)")
            } catch {
                print("Screenshot remains in the result bundle; extra PNG export failed: \(error)")
            }
        }
    }
}
#endif
