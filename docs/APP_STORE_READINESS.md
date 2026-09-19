# App Store preparation — September 19, 2026

This is an incremental implementation record, not a declaration that the app is ready for submission. App Sandbox is now enabled, but native permission/relaunch acceptance and the app-icon blocker are still open. Do not upload this build as a release candidate yet.

## Step 1 — Local product and legal website

Completed locally at `/Users/temelgunaydin/Desktop/buildandruns/finallyexplorer/`:

- Product introduction, a clearly labeled 2/4-pane illustration, actual Tools-panel artwork, feature limits, and support information.
- Separate `privacy.html`, `terms.html`, and `support.html` pages with consistent navigation, readable layouts, keyboard focus, reduced-motion support, and print styles for legal text.
- No advertising, tracking scripts, externally loaded fonts, accounts, purchases, or browser storage.
- No invented download link, launch date, price, trial duration, or lifetime-upgrade promise.
- All preview pages are `noindex, nofollow` until publication is explicitly approved.
- `node scripts/validate.mjs` checks the four pages, 72 local references, JavaScript syntax, and 2/4-pane interaction state. Each page returns HTTP 200 from the localhost preview.

Nothing was pushed or deployed. Browser interaction/visual QA has not been run; the user requested local inspection. The site's README lists publication checks. Intended public URLs must not be entered in App Store Connect or presented as working links until the site is actually published and verified.

### Legal publication gate

The documents are explicitly pre-release drafts. Before publication, confirm the operator's legal details, support-mailbox delivery, hosting and email providers, production logging/retention and processing locations, applicable transfer safeguards, distribution and purchase terms, and any notices required in the intended markets. Obtain appropriate legal review. Do not interpret the draft as legal compliance certification.

Keep the website and app's bundled `Legal/PrivacyPolicy.md` and `Legal/TermsOfService.md` consistent when practices change. Finalize both copies together.

## Step 2 — In-app disclosure and packaging basics

Implemented:

- Settings keeps On-Device AI and adds Privacy & Support.
- Privacy Policy, Terms of Service, and Open-Source Licenses open from bundled resources without network access. Draft status is explicit.
- Email Support opens a compose request with a subject only; it does not attach files, paths, diagnostics, or a message body. The address is also selectable text.
- The app does not link to the unpublished product website.
- The complete FFF MIT license is included beside the existing Devicon notice and exposed in Settings. A test compares the FFF notice with the vendored license.
- Debug and Release metadata declare Utilities, the copyright holder, and a Downloads purpose string. App Sandbox has **not** been toggled as a shortcut.

Validation is recorded below. Existing user-paused foreground UI testing remains paused.

## Step 3A — Persistent folder access and recovery

Implemented before switching on the sandbox:

- Explicitly selected folders are saved as security-scoped bookmarks in local preferences. The app restores them before constructing the workspace. It does not automatically grant access to favorites, parents, Home, or the whole disk.
- Bookmark resolution uses `withoutUI` and `withoutMounting`. Missing disks and denied/unresolvable folders retain their records and can be retried. Corrupt storage is not silently overwritten. Stale bookmarks are refreshed while preserving working session access if saving fails.
- Renamed folders retain their known previous locations so sidebar favorites can follow repeated moves; child mappings are applied before parent mappings. A mapping is applied only when the old location is positively missing and is not another remembered folder. Existing/reused paths and ambiguous permission errors are not redirected. These are bookmark-based relocations, not guesses based on folder names.
- A shared session owns balanced explicit scopes. AppKit's implicit folder-panel scope is released after transfer to the explicit scope, including failure paths. Forget removes the saved record for the next launch, but keeps current access until exit to avoid cutting off an in-flight operation. It is not an OS permission revocation.
- Settings adds **Folder Access** with Allow a Folder, remembered paths, unavailable-folder retry, and Forget. The permission error view offers Choose Folder, Try Again, and supplemental Privacy Settings. Cancelling the chooser makes no changes; selecting an unrelated folder navigates only to that explicitly selected location.
- Permission/not-found refresh failures expose recovery instead of retaining a misleading stale directory listing. A directory-access error takes precedence over the folder's search-empty state.
- Visual Search and Offline Catalog folder pickers share the persistent grant owner. Pane listing and local search requests refresh after a new grant. The named-account Home lookup no longer relies on the current-process home, which can be the sandbox container.

Step 3A was tested with `ENABLE_APP_SANDBOX = NO`. It was a prerequisite, not a completed sandbox migration; Step 3B below records the subsequent switch. No foreground mouse/keyboard UI test was resumed.

## Step 3B — Access consumers and sandbox configuration

Implemented:

- Debug and Release use a shared entitlements file: App Sandbox, user-selected read/write, app-scoped bookmarks, and the existing Downloads read/write capability. No network, Apple Events, privileged-helper, executable-writing, or broad filesystem exception was added to the app's entitlements.
- Individually selected documents adopt the panel's implicit scope. Read, answer and source-validation tasks retain their lease until cancellation actually unwinds, even after Clear or the model is released. Replacing/clearing selection releases the previous grant. Document selection itself is cancellable and mutually exclusive with document work.
- Existing global FFF indexes rescan after folder-access changes using a temporary balanced pool lease. An idle pool remains idle. The model uses the latest query and rejects completion after shutdown/cancellation. Pane-local invalidation remains in place.
- Offline Catalog validates volume identity, selected-root inode and every ancestor's metadata before/after opening only the selected folder. It no longer opens the disk root's directory contents first. Comparison/verified-copy ancestry checks likewise use metadata without opening unselected parents. Symlink, placeholder and identity checks remain.
- A real sandbox-host test showed that Foundation's named-user Home lookup still returned the container on this system. A bounded, reentrant `getpwuid_r` lookup now identifies the account Home. Desktop/Documents/Downloads/media URLs are built from that location; this does not grant access to their contents.
- `container-migration.plist` names **only** `${ApplicationSupport}/FinallyExplorer/OfflineCatalogs`. It does not request migration of user documents, caches, other apps' data or an entire Home folder. Actual first-container migration and preservation of existing preferences still need the acceptance pass below; no existing user container was deleted/reset for testing.
- ZIP creation copies the selected source into app-owned temporary storage before invoking system `ditto`, so the helper does not need a Powerbox grant owned by the parent process. The app stages/publishes the resulting archive without overwriting a collision. Folder archives retain their root; single-file archives no longer acquire an extra parent directory. A concurrent drain consumes all stderr while retaining at most 16 KiB, removing the pipe-buffer deadlock risk. Temporary copies require additional disk space; cleanup is attempted on success, error and cancellation. App and local website privacy drafts disclose this behavior and possible crash/cleanup leftovers.
- Drag/drop and clipboard inspection confirmed the existing implementation is **app-internal**, using opaque process-local tokens/in-memory URLs. No external Finder drop/paste import was introduced or claimed. Its existing regression tests remain; remembered folder scopes last for the app session.
- Terminal and Open With continue using `NSWorkspace` handoff. No AppleScript or new shell-command execution was introduced for those features. Their deterministic/mocked tests do not prove live sandbox handoff.
- Test fixtures now load corpus images and notices from bundles, and write diagnostic images into the app's temporary directory instead of global `/tmp`. Tests do not require adding a source-repository access grant. The complete bundled FFF license is checked against the audited vendored file's SHA-256.

### Native sandbox acceptance — partial native UI coverage; matrix still open

XCTest injects a read-only `/` exception and testmanager Mach exceptions into its host. Runtime entitlement assertions prove the sandbox is on, **not** that a normal Release app has the same access. The September 13 background integration step did not automate foreground input; the separate September 14 native UI increment is recorded below.

1. Use the non-test sandboxed Release app with a fresh test profile/container. Never delete the user's existing container, favorites, catalogs, permissions, or files to obtain a clean test.
2. Native chooser grant/deny/cancel, individual document selection, stale/moved folders, unplug/reconnect and relaunch. Confirm saved favorites/AI settings/terminal choice and catalogs survive first-container migration. A container already created by development tests will not establish first-launch migration behavior.
3. Select only a synthetic subfolder, not its parent. Exercise listing, preview, local search, **global name/content/grep search discovery through ungranted ancestors**, Visual Search, document questions and offline catalog rescan/reveal. A test-root FFF rescan does not establish global discovery under a narrow native grant.
4. Exercise 1–4 panes and internal cross-pane drag/paste; create/rename/copy/move/Trash/ZIP. Check ZIP cancellation while staging/compressing, failure/cleanup, and low-space behavior. No unselected sibling should be read or modified.
5. Check live Terminal/Open With handoff using synthetic fixtures, unavailable AI models, recovery copy and Settings/legal/Tools keyboard regressions.

Code integration is complete for this increment, but the sandbox migration is **not accepted for shipping** until this matrix passes. Background tests and a successful Release build are not App Store approval.

### September 14 — Isolated native acceptance preparation

The user authorized resuming the native acceptance pass. A separate, non-XCTest Release copy was built and launched with XcodeBuildMCP. Only command-line build overrides were used; the app's source, project configuration and production bundle identifier were not changed.

- QA bundle identifier: `com.temelgunaydin.finallyexplorer.sandboxqa.20260914`; product: `FinallyExplorer Sandbox QA`.
- Artifact: `/tmp/FinallyExplorer-SandboxAcceptance-20260914/DerivedData/Build/Products/Release/FinallyExplorer Sandbox QA.app`.
- Build log: `build_macos_2026-09-14T10-04-31-755Z_pid42027_08750955.log`.
- The QA build excludes `container-migration.plist` so it cannot migrate the user's existing offline catalogs into the temporary QA identity. The built bundle was inspected and the manifest is absent. This copy therefore **cannot validate first-container migration**; that needs a separate synthetic-profile test.
- Actual signed entitlements include App Sandbox, app-scoped bookmarks, user-selected read/write and Downloads read/write, with no XCTest filesystem/Mach exceptions. Development `get-task-allow` remains true. `codesign --verify --deep --strict --verbose=2` passes, including `libFFF.dylib`.
- Synthetic text, Swift and JSON fixtures, a copy destination and a separate unselected sibling were prepared under `/private/tmp/FinallyExplorer-SandboxAcceptance-20260914/Fixture/`. The intended native grant is only `Fixture/Allowed`, never the fixture parent or all of `/tmp`.
- **Initial connection attempt:** the process launched and remained running, but agent-device 0.21.1 could not resolve the QA application's bundle identifier through Launch Services. Direct-path and fresh frontmost inspection attempts also failed; explicitly registering only the QA bundle did not resolve the connection. The alternative computer-use surface returned `CUA_REPL_ENABLED_SURFACES is required` before any UI state was available.
- No chooser, grant, cancel, relaunch, file operation, search or visual UI assertion passed in this attempt. The September 13 count of 618 passing tests is historical background coverage, not a new run or proof of this acceptance matrix. No user container, favorites, catalogs, preferences or permissions were reset. Stop before foreground input until a working UI connection is available and the user is notified again.

### September 14 — Native UI resumption

After the user's confirmation, the QA bundle was copied without overwriting an existing app to `/Users/temelgunaydin/Applications/FinallyExplorer Sandbox QA 20260914.app`. Its signature verification passed before the UI run. An additional post-test signature recheck was not executed because automatic permission review timed out twice; it does not replace or invalidate the earlier successful check. The copy was discoverable by agent-device; snapshots worked, but initial button presses did not establish the desired state changes. That session was closed before switching to direct XCTest interactions through XcodeBuildMCP.

`NativeSandboxAcceptanceUITests` is a compile-time opt-in suite with an explicit QA-only bundle identifier guard. It launches the separately installed Release app normally, not the driver's default app or the app's mock/fixture launch mode. The [runbook](NATIVE_SANDBOX_ACCEPTANCE.md) documents the setup, short synthetic fixture, invocation and limits. Production app code and default project settings are unchanged.

The final direct XCTest batch passed **2 native UI tests, 0 failures/skips**, with 50.9 seconds of suite execution reported in the test log. Result: `test_macos_2026-09-14T11-18-35-872Z_pid80911_58835c6e.xcresult`; log: `test_macos_2026-09-14T11-18-35-872Z_pid80911_e0ba1a05.log`. Cancel leaves remembered records unchanged. Native selection of `/private/tmp/fe-native-0914d` adds exactly one matching canonical path; ordinary Command-Q/relaunch preserves that record. Forget removes only that record, its explanation is visible, and a second ordinary quit/relaunch restores the baseline count. The synthetic marker bytes match before and after. Teardown closes the QA app. Settings-hierarchy evidence is attached to the result bundle.

This completes the initial **native grant-record UI increment**, not the whole sandbox acceptance matrix. It does not establish downstream file-consumer access from a visible bookmark record alone. The source marker is read by the test driver for integrity checks, not by the QA app as a file-preview test. No new full background regression was run: the 618-test result above remains the September 13 result, and production app code is unchanged in this increment.

Test-harness preparation exposed macOS-specific selectors, a 128-character XCTest shorthand-query limit, and slow/timed-out keyboard synthesis. No app assertion was weakened to hide these problems. Two long-path attempts were deliberately stopped via XcodeBuildMCP after the keyboard phase became impractically slow; their missing-process failures are interrupted runs, not evidence of an app crash. A short, independently prepared `/private/tmp/fe-native-*` fixture keeps exact target selection, record counts, relaunch, Forget and before/after source-byte checks intact. The UI runner's read-only `/` test exception permits those source-byte checks; no such exception was added to the Release QA app.

### September 19 — Narrow workspace layout

- The previous 900×450 first window combined a fixed 340-point preview with a single-line, fixed-width toolbar. The workspace now reserves its own measured width, lets the preview shrink before the file pane, and wraps complete toolbar groups without recreating the stateful location/terminal popovers. Split buttons remain adjacent and the preview toggle stays at the trailing end of that group.
- New windows prefer 1280×800 points and enforce a 980×640 content minimum. The 340-point pane minimum also constrains the internal column divider; two columns fit beside the maximum-width sidebar. Existing sidebar limits and 2×2 pane-count limits are unchanged.
- All **630 background tests across 87 suites passed, 0 failures/skips**, via XcodeBuildMCP. The final rerun after the Preview accessibility correction and source formatting passed in 84.0 seconds of test execution; result: `test_macos_2026-09-19T12-25-19-338Z_pid17088_ac984882.xcresult`. This includes 12 new parameterized/boundary test methods, the existing real-window preview/split regressions, and the full file/search/AI regression target. The earlier full run also passed (`test_macos_2026-09-19T12-11-56-669Z_pid12345_a9d8216d.xcresult`). The initial compile caught a missing CoreGraphics import, which was fixed before either passing run.
- A separate Release QA copy (`com.temelgunaydin.finallyexplorer.sandboxqa.layout20260919`) built successfully, then was rebuilt with the Preview accessibility-group correction; final log: `build_macos_2026-09-19T12-18-40-349Z_pid15259_cb98e235.log`. Signature verification passes. Migration is excluded only for this QA copy, and its sandbox entitlements contain no XCTest exceptions. It remains development-signed, not a distribution artifact.
- Opt-in `WorkspaceLayoutUITests` uses that separately installed Release app with the existing UI-test launch mode, isolated defaults and the app's own bundled legal documents as read-only fixtures. Its complete interaction scenario passed **1 UI test, 0 failures/skips**, in 150.1 seconds of suite time: `test_macos_2026-09-19T12-22-16-812Z_pid16277_5d532c9e.xcresult`. It verifies resizing to 980 points, rejecting an undersized frame, exact document-preview text, preview hide/show, one through four panes, divider dragging, control containment and reset. QA-window screenshots were visually inspected; the bundled document bytes are unchanged. See [UI_POLISH.md](UI_POLISH.md) for first-attempt findings and test scope. This is not native-grant discovery/migration or the complete release UI matrix.
- The user's already staged Icon Composer files and project/icon edits were preserved. Builds include the current working-tree icon selection; those unrelated changes are not part of the layout increment.

### September 19 — Native file reads pass; global discovery blocked

- A separate normal-launch, sandboxed Release QA app successfully read synthetic files through a narrow native folder grant, then quit/relaunched and read the exact JSON again through the restored bookmark. Folder-local name, plain-content and regex search, negative query and clearing search passed. Result: `test_macos_2026-09-19T12-51-39-864Z_pid27866_e7356a19.xcresult` (1 native UI scenario, 0 failures/skips). Original fixture bytes are unchanged; no production container or permissions were reset.
- **New release blocker:** the independent global-search scenario restored the same grant and read the same file, but the upper global name search did not return it within 45 seconds. Result: `test_macos_2026-09-19T12-54-29-972Z_pid28919_23f9fc46.xcresult`. The test stops there; global content search and the mutation matrix are not passed. The root-only FFF traversal is under investigation; no broad parent grant or permissive entitlement was added to make the test pass.
- The QA signature and actual sandbox entitlements passed inspection, with migration excluded for this copy and development signing explicitly retained. This increment adds acceptance tests/evidence only; app behavior is unchanged. See [NATIVE_SANDBOX_ACCEPTANCE.md](NATIVE_SANDBOX_ACCEPTANCE.md) for exact fixture/launch instructions, failed setup attempts, helper-extraction scope and remaining limits.
- The four focused sandbox/access/global-search background suites passed **42 tests, 0 failures/skips**, result `test_macos_2026-09-19T12-59-14-879Z_pid30468_92180c60.xcresult`. This is not a full background rerun and does not supersede the native global-search failure.

### September 19 — Narrow-grant global search corrected

- Added direct searches of available bookmark roots plus the already-entitled Downloads location, rather than requiring FFF to discover them by walking from `/`. Spotlight matches are retained and deduplicated with direct results; content/regex uses the direct roots. Indexes remain lazy, pooled and cancellation-safe. Forget refreshes search membership without revoking scopes from in-flight file operations. No permission widening, entitlement change or AI-service change was made.
- Rebuilt and re-preflighted the same separate Release QA copy without resetting its container or changing the synthetic fixture. Strict bundle/FFF signing checks pass; native sandbox entitlements remain unchanged with no XCTest exceptions. Migration remains deliberately excluded from QA and development `get-task-allow` remains true.
- The complete background target passed **640 tests in 88 suites, 0 failures/skips**, result `test_macos_2026-09-19T13-43-05-487Z_pid51523_b3ff54e4.xcresult`.
- The two native file-consumer cases passed **2 UI tests, 0 failures/skips**, result `test_macos_2026-09-19T13-46-11-845Z_pid52617_502084cd.xcresult`. Upper name and plain-content search now discover the restored narrow grant. Preview exact bytes, local names/content/regex and absent-query/clear regressions also pass. The previous failure above is retained as history, not the current name/content status. Details, artifacts and limitations are in [NATIVE_SANDBOX_ACCEPTANCE.md](NATIVE_SANDBOX_ACCEPTANCE.md).
- The expanded global case also passed its separate repeat (**1 test, 0 failures/skips**), result `test_macos_2026-09-19T13-49-13-761Z_pid54332_f76ccfd4.xcresult`: an absent query clears old content results, and global regex finds the same file under the restored narrow native grant. No timeout increase or parent grant was used. Original fixture hashes remain unchanged and the QA app is closed.
- Final full background regression, including the additional shutdown/access-change/fallback/routing assertions: **643 tests, 0 failures/skips**, result `test_macos_2026-09-19T13-51-11-586Z_pid54971_46e4ea40.xcresult` (101.2 seconds MCP elapsed). Existing test-target accessibility deprecation warnings are unchanged. The native-tested production source was not modified after its Release build.

### September 19 — Native copy/move partial evidence; ZIP pending

- Added opt-in native mutation tests for the separately signed, normally launched Files QA app. Only new synthetic `/private/tmp/fe-native-m*` roots are granted; no production files, defaults, entitlements or permissions were changed.
- The initial combined native case passed copy, collision-safe repeated copy and moving the generated duplicate, then failed because XCTest could not find the visible move-collision alert. Its QA-window screenshot shows the correct destination-collision warning; the original and generated files remain intact. A repeat hit a test-driver exception from a speculative system-service lookup, which has been removed. Neither run is counted as a passing UI case, and neither reached ZIP.
- The tests are now separated into positive copy/move, move-collision and ZIP cases. They compile; independent native runs remain pending. A fresh ZIP fixture is ready, with foreground readiness requested after releasing the user's keyboard/mouse. The native alert accessibility/dismissal gap remains explicit, not suppressed. See [NATIVE_SANDBOX_ACCEPTANCE.md](NATIVE_SANDBOX_ACCEPTANCE.md) for exact artifacts, fixture safety and coverage limits.
- The four focused file-operation/archive suites passed **75 background tests, 0 failures/skips**, including a final rerun after the test split: `test_macos_2026-09-19T14-50-32-656Z_pid73305_e023d4a7.xcresult`. Production code is unchanged; this is not a new full 643-test or release-readiness pass.

### September 19 — Independent ZIP UI attempt

- The independent native ZIP case created `Package.zip` through the custom context menu, then failed because the verification subprocess rendered Unicode names as question marks under the C locale. Result: `test_macos_2026-09-19T15-07-46-604Z_pid74624_f839849d.xcresult`. Read-only UTF-8 listing/CRC/payload-hash checks prove the retained archive's Unicode and hidden-file contents are intact; all originals are unchanged. Repeated-name preservation and single-file ZIP were not reached, so the complete native ZIP gate remains open.
- Pinned UTF-8 only for the test's read-only unzip verifier. Compilation and **75 focused background tests passed** (`test_macos_2026-09-19T15-10-22-753Z_pid75207_edc69ac2.xcresult`). Production app behavior/permissions are unchanged. A fresh fixture is ready for the native rerun; renewed foreground readiness is pending. The QA app is closed. Details and safety evidence are in [NATIVE_SANDBOX_ACCEPTANCE.md](NATIVE_SANDBOX_ACCEPTANCE.md).

### September 19 — Native ZIP acceptance passed

- The full standalone right-click ZIP scenario now passes in the normally launched sandboxed Release QA app: **1 UI test, 0 failures/skips**, result `test_macos_2026-09-19T15-45-47-840Z_pid94365_f828f911.xcresult` (57.2 seconds MCP elapsed). Folder root structure, hidden and Unicode file contents, preservation of the first ZIP when creating a second, and single-file archives without an extra parent are all verified. Original hashes are unchanged, the final QA-window screenshot was inspected, and teardown closed QA.
- A preceding repeat exposed decomposed-versus-precomposed Unicode in the verifier's command arguments (`test_macos_2026-09-19T15-42-12-411Z_pid92872_ebd2eb8b.xcresult`). The test now checks payload bytes after extraction into its own unique temporary directory, while preserving CRC and exact entry-name/count assertions. Production app code and permissions are unchanged. The failed run remains documented, not counted as a pass.
- Final focused background rerun passed **75 tests, 0 failures/skips**: `test_macos_2026-09-19T15-47-19-699Z_pid94796_e7833d97.xcresult`. This completes the native ZIP success-path/collision increment, not cancellation/low-space, the separate move-collision alert gap, the complete file-operation matrix or overall release readiness. Current user icon/project edits remain outside this QA artifact's scope.

### September 19 — Native move-collision acceptance passed

- Corrected the XCTest selector: macOS exposes this warning as a Sheet labeled `alert`, not an Alert. The test now matches the exact message and full destination path within the QA application's alerts/dialogs/sheets, without guessing a service, dismissing blindly, widening permissions or increasing the timeout. Production code is unchanged.
- The standalone collision case passed in the normally launched sandboxed Release QA app: **1 UI test, 0 failures/skips**, result `test_macos_2026-09-19T16-18-14-232Z_pid2453_6c94f304.xcresult` (57.4 seconds MCP elapsed). The warning appeared, its enabled/hittable `OK` button dismissed it, both pane paths/file rows remained usable, and selecting another destination file succeeded. Original/copy bytes and exact directory contents were preserved. Before/after QA-window screenshots were inspected; teardown closed QA.
- The four focused file-operation/archive suites also passed **75 background tests, 0 failures/skips**, result `test_macos_2026-09-19T16-16-47-720Z_pid1944_b895c1f7.xcresult`. The earlier full 643-test and ZIP UI results were not rerun. This closes the specific move-collision warning/dismissal gap, not the separate positive copy/move case or remaining release matrix. Current icon/project edits are preserved and remain outside the installed QA artifact's scope. Details are in [NATIVE_SANDBOX_ACCEPTANCE.md](NATIVE_SANDBOX_ACCEPTANCE.md).

## Remaining review items

- **Native access coverage:** upper name/plain-content/regex discovery, context-menu ZIP success/Unicode/hidden-file/name-collision/single-file behavior, and move-collision warning/dismissal with preserved files and usable panes through narrow grants now pass. A complete independent positive copy/move run, explicit unselected-sibling denial, external volumes/reconnection, AI consumers and the remaining native file-operation matrix are still open.

- **App icon:** fill the empty AppIcon asset and verify the compiled icon resources at all required sizes. The website's small identity mark is not a replacement for the app's icon asset.
- **Shipping artifact:** archive/export and inspect the actual sandboxed, distribution-signed Release app, including embedded FFF signing/resources. Require sandbox entitlements and no `get-task-allow` in the distributed artifact. The current locally built Release app still has development `get-task-allow = true`; do not distribute it. Build success alone is not submission readiness.
- **Public legal/support URLs:** publish only after user approval and legal/provider checks; verify every URL before entering App Store Connect. Re-test the app's offline documents and live web access.
- **Commerce:** decide paid-up-front versus an in-app lifetime unlock/trial. Do not add a paywall or price until the commercial terms are confirmed. If IAP is chosen, implement and test purchase, restore, entitlement persistence, failure/cancel, and offline behavior.
- **Metadata and reviewer notes:** match screenshots and descriptions to the shipping sandboxed feature set; disclose macOS/model/language requirements and disabled Nearby Transfer. No account is required by the current app.
- **Remaining foreground UI pass:** policy/terms/license sheets, scrolling and Escape/Done, selectable support address, AI toggles after switching tabs, existing Tools keyboard regressions, and the complete native permission/file-consumer matrix above. Direct XCTest interaction is now available; announce again before continuing foreground control in a later session.

## Verification record

- Website: four static pages and 72 local references pass validation; layout-switch state tests pass; all four localhost routes return HTTP 200.
- The first full app regression caught AI Settings expanding to a 1061-point intrinsic width after its width constraint was removed. The explicit 580-point width was restored while allowing the height to fit the Settings tab.
- Step 2 full background regression: **582 tests passed across 81 suites, 0 failures/skips** using XcodeBuildMCP. Result bundle: `test_macos_2026-09-13T11-20-39-277Z_pid81896_37159a36.xcresult`. Includes existing file/search/AI and offscreen presentation regressions plus the new legal-resource and metadata tests. This is not a new interactive UI pass.
- XcodeBuildMCP **Release build succeeded**. Log: `build_macos_2026-09-13T11-22-29-978Z_pid82183_b783dc27.log`. Inspected `Build/Products/Release/FinallyExplorer.app`: Privacy Policy, Terms, Devicon and FFF notices are in `Contents/Resources`; FFF notice matches `Vendor/FFF/LICENSE` byte for byte; category, copyright, and Downloads description are present in the built Info.plist.
- The inspected Release build is still **unsandboxed and missing its app icon**. It is not an archived/exported App Store candidate, and the public legal website is not deployed. These remain submission gates, regardless of the successful build.
- Step 3A full background regression: **603 tests passed, 0 failures/skips** using XcodeBuildMCP. Result bundle: `test_macos_2026-09-13T11-55-14-775Z_pid86286_05eddc42.xcresult`. Includes 21 new access tests: persistence/relaunch, native macOS bookmark codec and real fixture rename, duplicate scopes, balanced release, panel cancel/failure, stale/missing/denied records, storage rollback/corruption, repeated/nested moves, reused old paths, remote-URL rejection, and named-account Home lookup. These tests ran with the current **unsandboxed** app host and synthetic fixtures; they do not establish sandboxed cross-process grant/relaunch behavior or replace native-panel UI testing.
- Step 3A XcodeBuildMCP **Release build succeeded**. Log: `build_macos_2026-09-13T11-57-53-343Z_pid86592_af84fed5.log`. This is a build check, not an archive/export, App Store validation, or foreground UI pass. No push, deployment, or submission was performed.
- Step 3B first targeted run: **62 tests passed** with the sandboxed XCTest host. The subsequent full run caught a container-based Home lookup, an unwanted parent directory in single-file ZIPs, and a directory-URL hint mismatch in a new narrow-parent test. These were corrected. The first real scanned-PDF OCR attempt hit the existing 15-second page timeout; the unchanged timeout passed on the targeted rerun and final full run. No test was disabled or expectation weakened to suppress that timeout.
- The installed Xcode/macOS 27 SDK reproducibly reported an invalid inferred `nonisolated` modifier on an unchanged OCR test actor only in batch compilation. The same sources compile per-file. `SWIFT_ENABLE_BATCH_MODE = NO` is set **only on FinallyExplorerTests**, in both configurations; app compilation and actor-isolation checks are unchanged. Revisit this build-time workaround after updating the toolchain.
- Step 3B final full background regression: **618 tests across 85 suites passed, 0 failures/skips**, through XcodeBuildMCP with the project defaults (only parallel test execution was disabled). Result bundle: `test_macos_2026-09-13T15-59-38-234Z_pid1820_31c826f5.xcresult`; log: `test_macos_2026-09-13T15-59-38-233Z_pid1820_8a3a59ec.log`. Includes lease ownership after Clear/deallocation, replacement and balanced stop; global refresh/lifecycle/pool behavior; narrow-parent catalog and verified copy; real `ditto` round trips, Unicode/hidden files and symlinks, collision preservation, cancellation before work, and a 2 MB diagnostics drain with a 4 KiB retained prefix. This remains background/model/existing window-hosted regression coverage, not the pending native chooser/relaunch acceptance.
- Step 3B XcodeBuildMCP **Release build succeeded**. Log: `build_macos_2026-09-13T16-02-03-565Z_pid2494_893935b2.log`. Artifact: `/tmp/FinallyExplorer-Sandbox-XcodeBuildMCP/Build/Products/Release/FinallyExplorer.app`. `codesign --verify --deep --strict` passes, including embedded `libFFF.dylib`; the first restricted-environment trust check failed, and the identical read-only check with normal certificate access passed. No signing/trust setting was changed.
- Release entitlement inspection confirms App Sandbox, app-scoped bookmarks, user-selected read/write and Downloads read/write. **No XCTest filesystem/Mach exceptions are present in Release.** Development `get-task-allow = true` is still present; this is not a distribution-signed archive/export. The legal documents and narrowly scoped migration manifest are bundled; the FFF notice matches the vendored license byte for byte. App icon, fresh permission/relaunch acceptance and distribution validation remain open.
- Local website privacy disclosure is synchronized with the app and passes `node scripts/validate.mjs` (four pages, 72 references, layout state/accessibility checks). Website commit: `2476411`. Nothing was pushed, deployed or submitted; the paused foreground input tests were not resumed.

## Official references

- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) — Mac App Store sandbox, completeness, privacy, and support expectations.
- [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).
- [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox).
- [Migrating your app's files to its App Sandbox container](https://developer.apple.com/documentation/security/migrating-your-app-s-files-to-its-app-sandbox-container).
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/).
- [Apple Standard EULA](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/).

Required-reason API manifest guidance must be checked against the app's actual platform. Do not incorrectly treat the iOS-family required-reason API list as a universal native-macOS submission blocker.
