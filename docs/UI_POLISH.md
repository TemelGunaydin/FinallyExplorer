# AI and Tools UI polish

## Scope — September 12, 2026

- Keep the launcher at the right of the window toolbar, with a visible **Tools** label instead of an unexplained wrench-only native menu. The popover uses the current app palette, full-width actions, short descriptions and two groups: **Find & Understand** and **Organize & Manage**. It does not imply that every tool uses AI.
- Preserve the active folder and selected-document routing. Opening a tool does not authorize reading, analysis, removal or reorganization. The existing operation gate and review/confirmation steps remain unchanged.
- Use one surfaced action style across AI and related tool sheets. Primary actions use the accent surface; secondary actions use the control surface. Disabled controls remain legible and visibly button-shaped but lose elevation. Full-label hit areas, keyboard focus outlines and reduced-motion-aware press feedback are included. Existing pane toolbar styles and the retired Nearby implementation are unchanged.
- Shorten Ask AI, Visual Search, Ask Documents and AI Settings instructions. Put supported formats, reading limits and privacy details in closed-by-default disclosures. Keep OCR and source-verification warnings beside answers and source excerpts, where they are relevant.
- Separate a citation's filename from its page/OCR line so long filenames cannot truncate the page information. Source excerpts use an inset reading surface. Reading/interpreting status rows have their own visible surface; cancellation and source-validation behavior is unchanged.
- Keep photo/document memory ownership accurate: closing a tool panel preserves its window-owned context; **Clear** forgets it, and closing the Explorer window releases that window's context. No new indexing, model download, API or file mutation behavior is introduced.

## Validation

Use XcodeBuildMCP, isolated temporary fixtures and XCTest for interaction checks. Offscreen NSHostingView renders inspect app UI without activating a window or capturing unrelated desktop content. SwiftUI, design-engineering and Swift Testing guidance informed the shared controls, concise hierarchy, keyboard access, restrained motion and separation of layout and interaction tests.

- Initial layout checks passed in all five palettes, light and dark. The first full background regression passed **573 unit/integration/presentation tests, 0 failures/skips** (79 suites), bundle `test_macos_2026-09-12T17-21-55-070Z_pid33518_b64f869c.xcresult`.
- Interactive tests exposed two integration problems: SwiftUI focus/key handlers did not move selection in the toolbar popover, and inheriting the sheet's custom ButtonStyle interfered with the Connected Disks native Menu. The disk menu now keeps native interaction with an outer themed surface and native disclosure indicator; decorating only its label was discarded by native menu rendering.
- Window-scoped diagnostics showed that this macOS toolbar popover leaves the presenting window as the key/event window. Tools now maintains its own highlighted item and uses a local AppKit handler gated to the visible popover and its captured owner. It handles Up/Down, Tab/Shift-Tab, Return/Space and Escape; unrelated windows and modified shortcuts are excluded. The monitor is removed before keyboard activation/closing, on detachment and on representable teardown. The main-thread bridge returns a Sendable Bool rather than sending an NSEvent across an isolation boundary. This follows [Apple's local event-monitor lifecycle guidance](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html); the observed routing was verified locally, not assumed from documentation.
- The folder-picker test initially targeted the Touch Bar Cancel item, then an absent dialog role. It now targets the observed `open-panel` window and `CancelButton`, and verifies the original source is unchanged and no analysis starts. No production picker behavior was changed for this correction.
- The broad UI batch `test_macos_2026-09-12T17-33-03-756Z_pid35329_228d8ca4.xcresult` passed **14 of 16 scenarios**, with the two menu issues above still failing. It is not recorded as a fully green run. The passing flows include all four document scenarios with actual on-device answers/OCR, photo date/type follow-ups, visual analysis/clear, duplicates, organization, copy approval, Ask AI, New Folder cancellation, split/reset and sidebar/toolbar layout.

- Both offline-catalog UI workflows passed after the native-trigger correction: confirmed removal/original preservation and save/disconnect/relaunch, bundle `test_macos_2026-09-12T17-40-31-480Z_pid36053_1c5c6f10.xcresult`. Its Tools keyboard case was still failing, so that mixed bundle is not recorded as fully green.
- The final Tools interaction recheck passed together with the two initial keyboard policy/lifecycle tests: **3 passed, 0 failures/skips**, bundle `test_macos_2026-09-12T17-56-21-573Z_pid37889_e040c3af.xcresult`. It verifies Escape, visible selection moving to Ask Documents with Down Arrow, Return opening the correct tool without reading, and every card's trailing hit area. Together the final passing batches cover **17 distinct UI scenarios**. Temporary event diagnostics were then removed, and a background test was added for unrelated/missing key-window rejection. The handler's window predicate was extracted without changing its behavior.

- Final full background regression: **576 tests passed across 80 suites, 0 failures/skips**, bundle `test_macos_2026-09-12T17-58-41-896Z_pid38262_19004b58.xcresult`. This includes the real on-device model, existing file/search operations, keyboard policy/lifetime/window isolation and presentation tests.
- Final presentation-only cleanup puts the Connected Disks surface around its native menu (native label rendering had discarded its background/chevron) and prevents disabled cards from taking hover selection. All **11 focused presentation/keyboard tests passed**, bundle `test_macos_2026-09-12T18-03-22-605Z_pid38733_b9b489f1.xcresult`; the final renders were inspected. Native menu selection logic is unchanged from the passing catalog UI flows; interaction tests were not rerun after that outer-surface/disabled-hover adjustment.

The full UI target is not part of this scoped polish regression. Existing AppKit main-thread/QoS diagnostics are separate from test pass/fail results. No temporary event or keyboard-focus diagnostics remain in production or in the new UI scenario.

## Narrow workspace — September 19, 2026

The 900×450 first-launch window revealed a separate width-allocation defect: the fixed preview and non-wrapping toolbar could draw controls behind the inspector. This increment keeps the existing 3D button styling/actions while changing layout only:

- Use the detail column's proposal to allocate workspace/preview widths explicitly. Preview remains mounted across visibility changes but is hidden from accessibility when closed; it yields space down to 220 points, with 340 points as the preferred width.
- Measure the navigation, file-action and split/preview groups. Keep them in one row when they fit, otherwise put actions below navigation and wrap whole groups only when necessary. The same view instances retain popover state; there are no duplicated fallback controls.
- Prefer 1280×800 for new windows, enforce a 980×640 content minimum, and use a shared 340-point minimum column width. Existing 2×2 limits and sidebar behavior are unchanged.
- Test the pure arrangement/width calculations separately from native interactions. The final full background rerun, including the Preview accessibility correction and source formatting, passed 630 tests in 87 suites, with no failures or skips, in 84.0 seconds of test execution; bundle `test_macos_2026-09-19T12-25-19-338Z_pid17088_ac984882.xcresult`. This is not a foreground UI result.

`WorkspaceLayoutUITests` is compiled only with `FINALLY_EXPLORER_LAYOUT_ACCEPTANCE`. It requires a separately built/registered QA app whose identifier starts with `com.temelgunaydin.finallyexplorer.sandboxqa.layout`, supplied by `FINALLY_EXPLORER_LAYOUT_QA_BUNDLE_ID` and `FINALLY_EXPLORER_LAYOUT_QA_APP_PATH`. The bundle identifier is checked against the path before launch. Do not target the user's installed app.

The suite uses the QA app's own Resources folder as a read-only fixture, with isolated UI-test defaults. It verifies the bundled privacy document bytes before/after, exports only QA-window screenshots to the test runner's temporary folder, attaches native hierarchies to the result bundle, and terminates only the selected QA app. No file operation, permission reset or user-container cleanup is performed. This UI fixture mode does **not** replace native sandbox bookmark/file-consumer acceptance.

Foreground result: **1 complete UI scenario passed, 0 failures/skips**, in 150.1 seconds of suite execution, bundle `test_macos_2026-09-19T12-22-16-812Z_pid16277_5d532c9e.xcresult`. It verifies minimum-size clamping, exact document text preview, preview hide/show, one through four panes, divider resizing, button/path/search containment, split-button ordering and reset back to a single pane. Initial/narrow/minimum/four-pane/reset QA-window screenshots were inspected; controls remain inside their panels with a scrollable file-list area. The test quits only the QA app and verifies the source document is unchanged.

The first UI run exposed the inspector identifier being inherited by three empty-state children. The inspector now defines a single labeled accessibility container, retaining its children's own identities and excluding the hidden column from accessibility. The second attempt reached narrow-window preview successfully but had an incorrect sample-word assertion: the bundled document does not contain the assumed capitalized word. The final test compares the entire preview string to the source bytes instead. Neither failure is recorded as a passing run or suppressed with a skipped assertion.

Example invocation after building, registering and signature-checking the current separate QA copy (exclude `container-migration.plist` for QA only):

```sh
npx --offline -y xcodebuildmcp@2.7.0 macos test --json '{
  "projectPath": "/Users/temelgunaydin/Desktop/DevelopmentGeneral/Apps/FinallyExplorer/FinallyExplorer.xcodeproj",
  "scheme": "FinallyExplorer",
  "configuration": "Debug",
  "derivedDataPath": "/tmp/FinallyExplorer-Layout-20260919",
  "extraArgs": [
    "-only-testing:FinallyExplorerUITests/WorkspaceLayoutUITests",
    "-parallel-testing-enabled", "NO",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG FINALLY_EXPLORER_LAYOUT_ACCEPTANCE"
  ],
  "testRunnerEnv": {
    "FINALLY_EXPLORER_LAYOUT_QA_BUNDLE_ID": "com.temelgunaydin.finallyexplorer.sandboxqa.layout20260919",
    "FINALLY_EXPLORER_LAYOUT_QA_APP_PATH": "/Users/temelgunaydin/Applications/FinallyExplorer Layout QA 20260919.app"
  }
}'
```

The Debug product is the driver; the selected app is the preflighted Release copy. Rebuild/re-preflight that copy after production changes. These fixtures do not exercise bookmarked external folders, copy/move/Trash, external volumes or first-container migration. Those release checks remain open in [APP_STORE_READINESS.md](APP_STORE_READINESS.md).
