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

### September 19 — Native mutation acceptance, partial evidence

`NativeSandboxFileMutationUITests` uses the same normally launched Files QA Release copy, QA bundle-ID/app-path checks and compile-time opt-in. Its signature and signed sandbox permissions were rechecked; no production source, signing setting, entitlement or app container was changed in this test-only increment. Tests only mutate synthetic files through the QA UI. The runner reads originals and generated artifacts; it does not perform the copy, move or compression itself.

Prepare a **fresh** non-symlink root directly under `/private/tmp`, named `fe-native-m*`, before each case. `NativeSandboxMutationFixture` requires this exact initial tree and exact UTF-8 text, including a final newline:

| Relative path | Text |
| --- | --- |
| `SandboxMarker.txt` | `Synthetic native Sandbox mutation fixture 20260919.` |
| `Source/FECopy.txt` | `Synthetic copy payload 7319. Original must remain unchanged.` |
| `Source/Package/Notes/Résumé.txt` | `Synthetic ZIP payload — Unicode 7319.` |
| `Source/Package/.hidden` | `Synthetic hidden ZIP payload 7319.` |
| `Destination/Anchor.txt` | `Synthetic destination anchor. Do not modify.` |

Use the file-consumer invocation above, replacing the test selector with **one** of these case paths and the fixture environment variable with a fresh mutation root. Do not run the entire class with one shared fixture: mutations deliberately make it ineligible for reuse. Failed fixtures, grants and artifacts are retained, not reset/deleted.

- `FinallyExplorerUITests/NativeSandboxFileMutationUITests/testNativeCrossPaneCopyAndMove`
- `FinallyExplorerUITests/NativeSandboxFileMutationUITests/testNativeMoveCollisionPreservesBothFiles`
- `FinallyExplorerUITests/NativeSandboxFileMutationUITests/testNativeContextMenuZIPPreservesContentsAndCollisions`

The native chooser must select only the fixture root, never Home or its parent. Exact source/destination paths are asserted using both AX label and value. Copy/paste selects a file in the destination pane, specifically checking that paste targets the displayed folder rather than requiring a selected subfolder. A repeated paste must preserve the first copy and create `FECopy copy.txt`. Move uses only that newly generated duplicate; the original is never moved. ZIP validation runs `unzip -t`, checks the exact payload names/count, then uses `ditto -x -k` in a newly generated directory inside the test runner's own temporary area. Each extracted payload must be a regular non-symlink file with exact expected bytes. Only that generated extraction directory is removed; fixture originals and ZIPs are retained. Folder-root structure, hidden/Unicode contents, repeated-name preservation and single-file archives without an extra parent are independent assertions.

#### Runs and current limits

- The initial combined UI case failed before file mutations because macOS exposed the current-path text as AXValue rather than AXTitle. Result: `test_macos_2026-09-19T14-36-48-420Z_pid71614_e239d646.xcresult` (66.2 seconds MCP elapsed). The path guard was corrected to compare absolute canonical paths from either field; no empty text is interpreted as the runner's working directory.
- On `/private/tmp/fe-native-m19a`, **copy, collision-safe repeated copy and moving the generated duplicate passed their individual assertions**. The combined case then failed waiting for the expected move-collision alert in XCTest's accessibility tree. Result: `test_macos_2026-09-19T14-38-55-753Z_pid72020_0c026dea.xcresult` (100.0 seconds MCP elapsed). Its QA-window screenshot was inspected: the centered `File Operation Failed` alert correctly says the destination name already exists and shows `Source/FECopy.txt`. The captured accessibility tree, however, contains a disabled application/window without the alert's controls. **This is not a passing UI case**, and ZIP was not reached.
- A fresh `/private/tmp/fe-native-m19b` repeat reached the same point, then a proposed test-only system-service lookup threw `NSInternalInconsistencyException` because that XPC service cannot be represented by `XCUIApplication`. Result: `test_macos_2026-09-19T14-43-14-711Z_pid72587_3230509f.xcresult` (90.1 seconds MCP elapsed). This was a driver exception, not an observed QA-app crash. The speculative lookup was removed; the actual alert host has not been established. No system service is launched or dismissed by the current tests.
- Both retained fixtures have their five originals unchanged (SHA-256 checked after termination), plus the expected `Destination/FECopy.txt` and moved `Source/FECopy copy.txt`; the destination duplicate is absent. No ZIP artifacts were produced in those attempts. The QA app was terminated and the user was released from the keyboard/mouse hold.
- The combined test has now been split into the three independent cases listed above. They compile, but **none of the split cases has yet completed a native run**. The move-collision case remains an explicit automation acceptance gate; its alert assertion was not weakened or marked as a passing expected failure. `/private/tmp/fe-native-m19c` is prepared and untouched for the independent ZIP case, pending renewed foreground readiness.
- The four focused background suites (`FileOperationServiceTests`, `FileOperationCoordinatorTests`, `FileOperationServiceCreateFolderTests`, `ArchiveCompressionTests`) passed **75 tests, 0 failures/skips** before UI work, result `test_macos_2026-09-19T14-36-06-508Z_pid71244_740f7d92.xcresult` (17.5 seconds MCP elapsed). After splitting the UI cases, compilation and the same 75 tests passed again: `test_macos_2026-09-19T14-50-32-656Z_pid73305_e023d4a7.xcresult` (6.0 seconds MCP elapsed). The full 643-test result remains the earlier run; it was not repeated in this test-only increment.

Outstanding mutation acceptance includes the independent positive copy/move and ZIP runs, accessible move-collision dismissal, drag-and-drop, recursive folder copy, external/cross-volume moves, Trash/create/rename, cancellation and low-disk-space behavior. The passing background tests and partial native assertions do not close those release gates.

#### Independent ZIP attempt — verifier locale correction

With renewed foreground approval, `testNativeContextMenuZIPPreservesContentsAndCollisions` ran against the unchanged Files QA app and fresh `/private/tmp/fe-native-m19c`. Signature/embedded-library verification and sandbox entitlement checks passed again (the restricted certificate-store check first returned `CSSMERR_TP_NOT_TRUSTED`; normal certificate access verified the signature). No permissions were widened and migration remains excluded from QA.

- The native narrow grant, folder listing, custom right-click menu, enabled/hittable `Compress to ZIP` action, visible `Package.zip` row and archive CRC validation passed. The case then **failed** its exact entry-name assertion: macOS `unzip` printed `R??sum??.txt` in the runner's environment. Result: `test_macos_2026-09-19T15-07-46-604Z_pid74624_f839849d.xcresult` (63.2 seconds MCP elapsed; teardown terminated QA). The attached QA-window screenshot was inspected and shows `Package.zip` alongside the unchanged originals. Repeated compression and single-file compression were **not reached**; this is not a passing complete UI scenario.
- Read-only checks of that same retained archive reproduced the filename mismatch with `LC_ALL=C` and showed the exact `Package/Notes/Résumé.txt` entry with `LC_ALL=en_US.UTF-8`. UTF-8 `unzip -t` passed; `unzip -p` SHA-256 for both the Unicode file and hidden file matched their originals. All five original fixture hashes also remained unchanged. The archive was not rewritten or extracted to make verification pass.
- `NativeSandboxMutationFixture` now supplies a deterministic `LC_ALL=en_US.UTF-8` environment to its **read-only unzip subprocess only**. The QA app, host locale, filenames, byte assertions and production ZIP implementation are unchanged. The updated helper compiled, and all **75 focused background tests passed, 0 failures/skips**: `test_macos_2026-09-19T15-10-22-753Z_pid75207_edc69ac2.xcresult` (5.8 seconds MCP elapsed). No full background rerun was performed.
- The failed fixture and ZIP remain available for inspection. Fresh `/private/tmp/fe-native-m19d` is prepared for a full native rerun, pending renewed foreground readiness after releasing keyboard/mouse control. ZIP acceptance remains incomplete until repeated-name preservation and single-file layout pass in that run. The separate move-collision accessibility gap is unchanged.

#### Independent ZIP rerun — passed

- The `/private/tmp/fe-native-m19d` attempt passed UTF-8 listing and CRC validation, but the verifier's `unzip -p` invocation received a decomposed-Unicode filename and could not match the archive's precomposed name. Result: `test_macos_2026-09-19T15-42-12-411Z_pid92872_ebd2eb8b.xcresult` (68.6 seconds MCP elapsed). This failed attempt is retained; the five originals remain unchanged. It was another verifier failure, not a passing UI case or an observed app crash.
- The verifier now validates the actual macOS extraction result in a unique runner-owned temporary directory, as described above. CRC/name checks remain, a payload-count check also rejects duplicates, and each extracted file's bytes/type are asserted. No filename expectation, source integrity check or timeout was relaxed. This change affects only the test helper, not production compression or app permissions.
- On fresh `/private/tmp/fe-native-m19e`, the **complete native ZIP case passed: 1 test, 0 failures/skips**. Result: `test_macos_2026-09-19T15-45-47-840Z_pid94365_f828f911.xcresult`; log: `test_macos_2026-09-19T15-45-47-839Z_pid94365_a8dc4dce.log` (51.433 seconds test execution, 57.2 seconds MCP elapsed). The normally launched Release QA app obtained only the narrow fixture grant. Right-click compression created `Package.zip`, then `Package 2.zip` without changing any byte of the first archive. Both contain the exact hidden/Unicode payloads beneath the correct root. `FECopy.txt.zip` contains only `FECopy.txt` as its payload, without an extra source-directory level. No unexpected fixture files remain.
- Teardown terminated the QA app. The final QA-window screenshot was inspected and shows all three generated archives alongside the originals. Post-run SHA-256 checks confirm all five original files still match their initial values; generated archives and grants are retained. The user was released from keyboard/mouse control. No further foreground test was started.
- Final focused background rerun: **75 tests, 0 failures/skips**, result `test_macos_2026-09-19T15-47-19-699Z_pid94796_e7833d97.xcresult` (5.8 seconds MCP elapsed). Production source is unchanged from the previously preflighted Release QA copy; current user icon/project edits were preserved and were not evaluated as part of the installed QA artifact. The full 643-test target was not rerun.

The native context-menu ZIP success/Unicode/hidden-file/name-collision/single-file acceptance increment is now complete. Separate positive copy/move reruns, move-collision alert accessibility/dismissal, drag-and-drop, recursive copy, external/cross-volume operations, Trash/create/rename, cancellation/low-space behavior and the other release gates remain open.

#### Native move collision — passed

- Corrected the test selector, not the production alert. On this host, macOS exposes the expected warning as a **Sheet labeled `alert`**, rather than an XCTest Alert. The helper now queries only the QA application's alerts, dialogs and sheets, requiring `File Operation Failed`, the exact destination-collision explanation, the full expected file path (including the equivalent `/tmp` alias), and an `OK` button. The existing 10-second deadline is unchanged. The earlier main-window-only hierarchy was insufficient to establish an app accessibility defect or a separate system-service host; those failed runs remain history above.
- The same normally launched Release QA copy passed strict signature verification again. No production source, app container, signing setting, entitlement or existing grant was changed. No guessed service, interruption monitor, blind Return/Escape, wider folder grant or permission reset was used. Current user icon/project edits remain outside this installed QA artifact's scope.
- The four focused file-operation/archive suites passed **75 background tests, 0 failures/skips**, also compiling the updated UI case: `test_macos_2026-09-19T16-16-47-720Z_pid1944_b895c1f7.xcresult` (8.7 seconds MCP elapsed). The full 643-test target and ZIP UI case were not rerun in this test-only increment.
- With renewed foreground approval and fresh `/private/tmp/fe-native-m19f`, `testNativeMoveCollisionPreservesBothFiles` **passed: 1 UI test, 0 failures/skips**. Result: `test_macos_2026-09-19T16-18-14-232Z_pid2453_6c94f304.xcresult`; log: `test_macos_2026-09-19T16-18-14-231Z_pid2453_607738d0.log` (53.539 seconds test execution; 57.4 seconds MCP elapsed). Only the fixture root was granted. The app copied `Source/FECopy.txt` into the destination pane, then correctly rejected moving that copy back onto the existing original.
- The matched sheet's `OK` button was enabled and hittable; clicking it dismissed the sheet. Both exact pane paths and both `FECopy.txt` rows remained accessible/hittable, and selecting `Destination/Anchor.txt` succeeded after dismissal. Original and copied bytes plus exact source/destination directory contents were checked again. Post-run SHA-256 checks confirmed all five originals were unchanged; the destination copy matched the original hash `f0740c2285382fa3d36889eb0e6a071a78b185940fc0e09f173faf70f8a65115`.
- Before/after QA-window screenshots and application hierarchies are attached to the result; both screenshots were visually inspected. Teardown terminated only QA. The fixture, generated copy and narrow grant are retained, and keyboard/mouse control was released. No further foreground test was started.

The move-collision warning/dismissal acceptance gate is now closed for this native case. The separate positive copy/move case still needs a complete independent run; earlier partial assertions are not counted as that pass. Drag-and-drop, recursive copy, external/cross-volume operations, Trash/create/rename, cancellation/low-space behavior, explicit unselected-sibling denial, AI consumers, migration and the other release gates remain open. This pass does not establish overall App Store readiness or a complete visual/accessibility audit.

### September 20 — Independent positive copy/move preparation

- Strengthened `testNativeCrossPaneCopyAndMove` to recheck the first destination copy's exact bytes after repeated paste and after moving only the generated duplicate. It also rechecks both exact pane paths, hittable source/destination rows and subsequent selection of the destination anchor. Existing absence, directory-content and original-byte assertions are retained. Production source is unchanged.
- The installed Files QA identity and strict bundle/embedded-library signatures were verified again. Signed sandbox/bookmark/Downloads/user-selected permissions are unchanged; no XCTest exceptions are present, and development `get-task-allow` is still true. A restricted entitlement read produced the previously seen invalid-blob warning; normal certificate access returned the expected entitlements and signature verification passed without changing trust/signing settings. No interrupted QA/test execution was running. The installed app was not rebuilt or launched, and current user icon/project edits remain untouched and outside this artifact's scope.
- Prepared fresh `/private/tmp/fe-native-m20a` with the exact five-file fixture above. SHA-256 values match the established originals. No existing fixture, grant, preference or real user file was reset, removed or modified.
- The four focused background suites passed **75 tests, 0 failures/skips**, and the strengthened UI case compiled. Result: `test_macos_2026-09-20T11-15-14-346Z_pid9811_98b13866.xcresult`; log: `test_macos_2026-09-20T11-15-14-346Z_pid9811_f122b003.log` (10.7 seconds MCP elapsed). The full 643-test target was not rerun.
- **Native UI execution remains pending renewed foreground readiness.** This preparation is not a positive copy/move acceptance pass; use the single-case selector with the fresh root above once the user is ready. The previous collision/ZIP passes are unchanged, not rerun today.

#### Independent positive copy/move — passed

- After renewed foreground approval, `testNativeCrossPaneCopyAndMove` completed against the unchanged, normally launched Files QA Release app and `/private/tmp/fe-native-m20a`: **1 UI test passed, 0 failures/skips**. Result: `test_macos_2026-09-20T14-02-09-163Z_pid24229_a0d4e0a3.xcresult`; log: `test_macos_2026-09-20T14-02-09-162Z_pid24229_92e4b4a4.log` (52.868 seconds test execution; 64.7 seconds MCP elapsed). Strict bundle/embedded-library signature verification and the untouched fixture hashes were checked before launch.
- The native chooser granted only the exact synthetic root. With `Destination/Anchor.txt` selected, paste copied the source file into the displayed destination folder, without requiring a selected subfolder. Repeated paste created `Destination/FECopy copy.txt` while preserving `Destination/FECopy.txt` and all originals. Cutting only that generated duplicate and pasting into the source pane produced `Source/FECopy copy.txt`; its former destination row and file disappeared.
- Exact payload bytes, original bytes, source/destination child lists, both full pane paths and hittable rows all passed. Selecting the destination anchor after the move also succeeded. Post-run SHA-256 checks confirm all five original fixture files remain unchanged; both generated copies match `f0740c2285382fa3d36889eb0e6a071a78b185940fc0e09f173faf70f8a65115`. This verifies the same-volume keyboard copy/paste and cut/paste path, not drag-and-drop or cross-volume behavior.
- The repeated-paste and final-move QA-window screenshots were inspected; hierarchy/screenshot attachments are retained in the result. Teardown terminated QA, and the user was released from keyboard/mouse control. The fixture, generated copies and narrow grant remain available; no preferences or existing grants were reset. No production source, signing setting, app permission or user icon/project edit was changed.
- The preceding **75-test focused background pass** remains the result recorded above; neither that target nor the full 643-test target, ZIP or move-collision UI cases were rerun in this documentation-only completion.

The independent positive copy/move gate is now complete, alongside the earlier ZIP and move-collision passes. Next native file-operation work is cross-pane drag-and-drop and recursive folder copy. External/cross-volume operations, Trash/create/rename, cancellation/low-space behavior, explicit unselected-sibling denial, AI consumers, migration and other release gates remain open; this result is not overall release approval.
