# Native Sandbox acceptance

This is an opt-in XCTest UI suite, not part of ordinary regression runs. It launches a **separately built Release app** by its QA bundle identifier. It does not use the app's `--ui-testing` launch mode, a fixture-root override, mock services or an injected defaults suite.

## Safety and preparation

1. Build the current app source with XcodeBuildMCP using a unique identifier starting with `com.temelgunaydin.finallyexplorer.sandboxqa.` and a separate product name/Derived Data directory. Never use the production identifier.
2. For this QA copy only, exclude `container-migration.plist` with the build override `EXCLUDED_SOURCE_FILE_NAMES=container-migration.plist`. Otherwise a fresh QA identity could migrate the user's real offline catalogs. This deliberately leaves first-container migration **untested**.
3. Inspect the built app's actual signed entitlements: App Sandbox, user-selected read/write, app-scoped bookmarks and Downloads read/write; no XCTest filesystem/Mach exceptions. Verify its signature and embedded FFF library. The development-signed QA copy is not a distribution artifact.
4. Copy the QA bundle to a new, non-conflicting location in the user's `Applications` folder. Do not overwrite an existing app or reset a container. On this host, Launch Services/agent-device did not resolve the copy under `/tmp`; the user Applications copy was discoverable.
5. Notify the user before foreground keyboard/mouse work. Run tests serially. Do not run another UI automation session concurrently.
6. Prepare a new real directory directly under `/private/tmp`, with a name starting `fe-native-`. Put `SandboxMarker.txt` inside it, containing exactly `Synthetic native Sandbox acceptance fixture.` followed by a newline. Do not use a symlink, an existing user-data folder, or the parent `/private/tmp` as the grant. Pass this short folder path using `FINALLY_EXPLORER_NATIVE_QA_FOLDER`.

The suite rejects a non-QA bundle identifier before launching anything and rejects broad/non-QA fixture paths. It only reads the prepared synthetic marker; it does not create or modify files. The UI runner has Xcode's read-only `/` test exception (not write access to global `/private/tmp`); **the separately signed QA app does not**. Creating a fixture in the runner's own container was possible, but its long absolute path made native keyboard synthesis impractically slow on this host. The short external fixture retains the same exact-location and persistence assertions. Tiny fixtures and failed-run QA records are retained for inspection; no existing user files or preferences are deleted. Teardown terminates only the selected QA app.

## Run

The following is the verified local configuration for the September 14 QA copy. Rebuild/re-preflight the QA app after production code changes; do not mistake testing an older installed copy for testing current source. Change the QA identifier consistently when preparing a new copy.

```sh
npx --offline -y xcodebuildmcp@2.7.0 macos test --json '{
  "projectPath": "/Users/temelgunaydin/Desktop/DevelopmentGeneral/Apps/FinallyExplorer/FinallyExplorer.xcodeproj",
  "scheme": "FinallyExplorer",
  "configuration": "Debug",
  "derivedDataPath": "/tmp/FinallyExplorer-SandboxAcceptance-20260914/UITestDriver",
  "extraArgs": [
    "-only-testing:FinallyExplorerUITests/NativeSandboxAcceptanceUITests",
    "-parallel-testing-enabled", "NO",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG FINALLY_EXPLORER_NATIVE_SANDBOX_ACCEPTANCE"
  ],
  "testRunnerEnv": {
    "FINALLY_EXPLORER_NATIVE_QA_BUNDLE_ID": "com.temelgunaydin.finallyexplorer.sandboxqa.20260914",
    "FINALLY_EXPLORER_NATIVE_QA_FOLDER": "/private/tmp/fe-native-0914d"
  }
}'
```

The pinned MCP package is already cached on this host; offline invocation avoids repeatedly checking the registry. The Debug configuration builds the **test driver**. `XCUIApplication(bundleIdentifier:)` targets the separately installed, preflighted Release QA app, not the driver's default app target.

`FINALLY_EXPLORER_NATIVE_SANDBOX_ACCEPTANCE` is a compile-time opt-in. Without it, the suite is not discovered; it does not add skipped tests to normal runs. No project-wide build setting was changed to enable it by default.

## Assertions and limits

- Cancel: open Settings with Command-comma, select Folder Access, open the native chooser and cancel. The remembered-record count/empty state stay unchanged, the action is enabled again and no storage error is displayed.
- Narrow grant: use a freshly prepared synthetic folder/file, verify its expected bytes before interaction, navigate to that exact folder in the native chooser, verify the chooser's selected location before accepting, and verify one new record with the exact path.
- Relaunch: quit normally with Command-Q, reopen and verify the same record/path remains.
- Forget: remove only this run's record, check the next-launch explanation, quit/reopen and verify the baseline record count is restored. The synthetic source bytes remain unchanged.

Native path entry uses individual `typeKey` events after focusing the path field: bulk `typeText` timed out on this host. The complete entered value and selected location are checked before accepting. Path assertions collect displayed path values with predicates and compare canonical path components, avoiding XCTest's 128-character shorthand-identifier limit and false mismatches from trailing separators or `/tmp` aliases. Settings tabs are toolbar buttons on this macOS build, and the native Go to Folder sheet exposes `PathTextField`.

These assertions establish the visible grant-record workflow, not every downstream consumer's ability to read a restored scope. Listing/preview/search under a restored grant, unselected sibling denial, global FFF/grep discovery through ungranted ancestors, file operations, external-volume reconnection, first-container migration and the rest of the release UI matrix remain separate acceptance work. Passing these tests is not App Store approval.

Results and outstanding release gates are recorded in [APP_STORE_READINESS.md](APP_STORE_READINESS.md).
