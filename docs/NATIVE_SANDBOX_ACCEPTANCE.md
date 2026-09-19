# Native Sandbox acceptance

This is an opt-in XCTest UI suite, not part of ordinary regression runs. It launches a **separately built Release app** by its QA bundle identifier. It does not use the app's `--ui-testing` launch mode, a fixture-root override, mock services or an injected defaults suite.

## Safety and preparation

1. Build the current app source with XcodeBuildMCP using a unique identifier starting with `com.temelgunaydin.finallyexplorer.sandboxqa.` and a separate product name/Derived Data directory. Never use the production identifier.
2. For this QA copy only, exclude `container-migration.plist` with the build override `EXCLUDED_SOURCE_FILE_NAMES=container-migration.plist`. Otherwise a fresh QA identity could migrate the user's real offline catalogs. This deliberately leaves first-container migration **untested**.
3. Inspect the built app's actual signed entitlements: App Sandbox, user-selected read/write, app-scoped bookmarks and Downloads read/write; no XCTest filesystem/Mach exceptions. Verify its signature and embedded FFF library. The development-signed QA copy is not a distribution artifact.
4. Initially copy the QA bundle to a new, non-conflicting location in the user's `Applications` folder. To update that same QA copy, first verify its exact QA identifier and that it is stopped; preserve its existing container and grants. Never overwrite a production/unrelated app or reset a container. On this host, Launch Services/agent-device did not resolve the copy under `/tmp`; the user Applications copy was discoverable.
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

## September 19 — Native file-consumer acceptance

`NativeSandboxFileAccessUITests` adds actual listing, text preview and search checks against another separately installed Release copy. It uses the same compile-time opt-in, but requires a bundle identifier beginning with `com.temelgunaydin.finallyexplorer.sandboxqa.files` and an app path whose bundle identifier matches. It never launches the ordinary test host as the application under test.

The preflighted copy is `/Users/temelgunaydin/Applications/FinallyExplorer Files QA 20260919.app`, identifier `com.temelgunaydin.finallyexplorer.sandboxqa.files20260919`. It was built from commit `425a356` plus the user's existing working-tree icon/project edits. No production code was changed in this increment. Build log: `build_macos_2026-09-19T12-45-21-250Z_pid24874_9b9b6139.log`. The migration manifest is excluded, signature verification passes, and the actual signed entitlements contain App Sandbox, bookmarks, user-selected read/write and Downloads read/write, with no XCTest filesystem/Mach exceptions. Development `get-task-allow` is still true: this is not a distribution artifact. A restricted-environment entitlement display initially warned about an invalid blob; the same read with normal certificate access showed the expected entitlements and strict signature verification passed. No signing settings were changed.

### Fixture and launch

Prepare a new non-symlink `/private/tmp/fe-native-f*` root outside the runner. `NativeSandboxFileFixture` verifies its directory types and these exact UTF-8 originals (each ending with a newline) before launch and after teardown:

- `SandboxMarker.txt`: `Synthetic native Sandbox file-consumer fixture.`
- `QA Source/FENativeNeedle.json`: `{"message":"Synthetic native-token-7319","count":19}`
- `QA Source/Control.txt`: `Synthetic control document without the search token.`
- `QA Destination/`: an empty directory reserved for a later file-operation increment.

The September 19 root is `/private/tmp/fe-native-f19a`. Its parent is never selected in the native chooser. The runner only reads these originals; the QA app owns its normal container/preferences and native bookmark scopes. Do not add a runner filesystem write exception or silently switch to `--ui-testing`. Repeat runs may reuse the same exact synthetic favorite; the suite checks the current folder's favorite action and requires exactly one QA favorite rather than resetting preferences. Prepare another QA identity if it contains unrelated state.

```sh
npx --offline -y xcodebuildmcp@2.7.0 macos test --json '{
  "projectPath": "/Users/temelgunaydin/Desktop/DevelopmentGeneral/Apps/FinallyExplorer/FinallyExplorer.xcodeproj",
  "scheme": "FinallyExplorer",
  "configuration": "Debug",
  "derivedDataPath": "/tmp/FinallyExplorer-Layout-20260919",
  "extraArgs": [
    "-only-testing:FinallyExplorerUITests/NativeSandboxFileAccessUITests",
    "-parallel-testing-enabled", "NO",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG FINALLY_EXPLORER_NATIVE_SANDBOX_ACCEPTANCE"
  ],
  "testRunnerEnv": {
    "FINALLY_EXPLORER_NATIVE_QA_BUNDLE_ID": "com.temelgunaydin.finallyexplorer.sandboxqa.files20260919",
    "FINALLY_EXPLORER_NATIVE_QA_APP_PATH": "/Users/temelgunaydin/Applications/FinallyExplorer Files QA 20260919.app",
    "FINALLY_EXPLORER_NATIVE_QA_FOLDER": "/private/tmp/fe-native-f19a"
  }
}'
```

### Initial results — failure retained as regression history

- **Passed:** `testRestoredNarrowGrantSupportsListingPreviewAndLocalSearch`, 1 test, 0 failures/skips; MCP elapsed 80.3 seconds. Result: `test_macos_2026-09-19T12-51-39-864Z_pid27866_e7356a19.xcresult`. The native recovery chooser grants only the fixture root. The QA app lists its children, favorites `QA Source`, reads the full JSON text, quits with Command-Q, relaunches normally, and reads the same JSON again via the restored favorite without another chooser. Folder-local names, plain content and regex queries find the fixture; an absent-token query removes the previous result and clearing search restores the listing. Source bytes remain unchanged. Successful UI stages have screenshot/hierarchy attachments; they have not received a separate visual-design review.
- **Failed / release gate:** global name search did not return `FENativeNeedle.json` within 45 seconds, even though the same run had already read its exact bytes after restoring the native grant. Result: `test_macos_2026-09-19T12-54-29-972Z_pid28919_23f9fc46.xcresult` (93.6 seconds MCP elapsed). The case was subsequently renamed from `...UngrantableAncestors` to `...UngrantedAncestors` for accurate terminology; its assertions are unchanged. It matches only `global-search-result-*` elements, so a still-visible file row cannot produce a false pass. Global content search is **not reached** after this failure; it is not counted as passed. The shared grant/relaunch helper was extracted between these two runs; the local-search assertions were unchanged but not rerun after extraction.
- **Investigation:** `ContentView` supplies `/` to global search, and the hybrid service's FFF fallback/content engine is rooted there. Available bookmark folders are not separately supplied as traversal roots. This is a candidate cause, not proof of whether the missed fixture was excluded by traversal permissions, engine policy or another indexing issue. Keep this regression red until the cause is fixed and the native case passes; do not grant `/`, Home or `/private/tmp`, enable symlink following, lengthen the timeout to hide the problem, or replace the Release app with an XCTest host.
- Preparation attempts are not passing runs: two fixture guards initially rejected Foundation's `/tmp` versus `/private/tmp` alias representation before app launch. The guard now accepts only those exact parent component lists and still rejects symlink fixture roots. One interaction attempt was obstructed by another app's window; explicitly activating only the QA app before interaction resolved it. No unrelated app was closed.

The QA app is terminated after each run. Native cross-pane mutations, ZIP/Trash/cancellation, an explicit unselected-sibling negative control, external volumes, global content discovery, and first-container migration remain unaccepted. The earlier 630-test background result does not establish these native behaviors.

After the foreground tests, the four focused background suites (`SandboxConfigurationTests`, `FolderAccessModelTests`, `HybridGlobalSearchServiceTests`, `GlobalSearchModelTests`) passed **42 tests, 0 failures/skips** under normal build conditions. Result: `test_macos_2026-09-19T12-59-14-879Z_pid30468_92180c60.xcresult` (17.6 seconds MCP elapsed). This verifies the existing model/configuration regressions still pass; it does not override the failed native global-search test. The complete 630-test target was not rerun in this test-only increment.

### September 19 — Direct authorized-root search correction

The production global-search service now searches available bookmarked folders and the already-entitled Downloads folder directly. It does not depend on traversing ungranted ancestors from `/`. Spotlight name results remain in use and are merged with direct-root results even when Spotlight is nonempty. Global content/regex search uses those same direct roots. Idle launch/access updates do not create indexes; root searches use pooled engines, bounded query fan-out, cancellation/lifetime checks, and stable deduplicated result IDs. A completed small root can refresh results without waiting for a larger root's warmup. Forget updates the search roots while retaining the existing process scope for in-flight file operations. No entitlement, parent grant, symlink-following policy, or AI interpretation service was changed.

The same Files QA identity was rebuilt from the corrected working tree, installed only over the verified stopped QA copy, and re-preflighted. Build: `build_macos_2026-09-19T13-43-10-468Z_pid51586_e3aa93d8.log` (59.3 seconds). The signature and embedded FFF library pass strict verification; signed permissions are unchanged, XCTest exceptions remain absent, and the migration manifest remains excluded. Existing bookmarks/favorites/container and the exact `/private/tmp/fe-native-f19a` fixture were retained.

- The full background target passed **640 tests in 88 suites, 0 failures/skips**, result `test_macos_2026-09-19T13-43-05-487Z_pid51523_b3ff54e4.xcresult` (96.5 seconds test execution; 103.8 seconds MCP elapsed).
- Both native file-consumer UI cases passed: **2 tests, 0 failures/skips**, result `test_macos_2026-09-19T13-46-11-845Z_pid52617_502084cd.xcresult` (147.2 seconds MCP elapsed). The previously failing upper name search now discovers the fixture, and upper plain-content search also finds its token after normal quit/relaunch. The test explicitly waits for the name result to disappear before checking content, preventing a cached-result false pass. The other case re-verifies exact Preview text and local name/plain/regex/negative/clear behavior. Original fixture bytes remain unchanged.
- One preceding UI-driver compilation failed because the new stale-result assertion was initially inserted into the local case instead of the global case. This was fixed before the passing run; it was not an app launch/crash or a passing UI attempt. The 45-second global-result deadline was not increased and no broader folder was granted.
- The global case was then extended with an absent-content query followed by a regex query. Its repeat passed **1 test, 0 failures/skips**, result `test_macos_2026-09-19T13-49-13-761Z_pid54332_f76ccfd4.xcresult` (76.1 seconds suite execution; 84.0 seconds MCP elapsed). This rechecks native name/plain-content discovery and proves both stale-result removal and `native-token-[0-9]{4}` matching in the upper global search. It is a rerun of the same global test, not a third distinct native test case. Teardown closed the QA app; all three original fixture hashes still match their pre-test values.
- Final background rerun after the extra cancellation/access-change, Spotlight-fallback and regex-routing assertions: **643 tests, 0 failures/skips**, result `test_macos_2026-09-19T13-51-11-586Z_pid54971_46e4ea40.xcresult` (101.2 seconds MCP elapsed). Production code is unchanged from the native-tested Release copy. Two pre-existing deprecated accessibility-method warnings remain in the test target; no new compiler errors remain.

Global search acceptance does not complete native cross-pane mutations, ZIP/Trash/cancellation, an explicit unselected-sibling negative control, external-volume reconnection, AI consumers or first-container migration. Screenshot/hierarchy attachments establish interaction evidence, not a separate visual-design review.
