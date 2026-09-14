# App Store preparation — September 14, 2026

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

### Native sandbox acceptance — pending; automation connection blocked

XCTest injects a read-only `/` exception and testmanager Mach exceptions into its host. Runtime entitlement assertions prove the sandbox is on, **not** that a normal Release app has the same access. No foreground input was automated in this step.

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
- **Native interaction is unverified.** The process launched and remained running, but agent-device 0.21.1 could not resolve the QA application's bundle identifier through Launch Services. Direct-path and fresh frontmost inspection attempts also failed; explicitly registering only the QA bundle did not resolve the connection. The alternative computer-use surface returned `CUA_REPL_ENABLED_SURFACES is required` before any UI state was available.
- No chooser, grant, cancel, relaunch, file operation, search or visual UI assertion passed in this attempt. The September 13 count of 618 passing tests is historical background coverage, not a new run or proof of this acceptance matrix. No user container, favorites, catalogs, preferences or permissions were reset. Stop before foreground input until a working UI connection is available and the user is notified again.

## Remaining review items

- **App icon:** fill the empty AppIcon asset and verify the compiled icon resources at all required sizes. The website's small identity mark is not a replacement for the app's icon asset.
- **Shipping artifact:** archive/export and inspect the actual sandboxed, distribution-signed Release app, including embedded FFF signing/resources. Require sandbox entitlements and no `get-task-allow` in the distributed artifact. The current locally built Release app still has development `get-task-allow = true`; do not distribute it. Build success alone is not submission readiness.
- **Public legal/support URLs:** publish only after user approval and legal/provider checks; verify every URL before entering App Store Connect. Re-test the app's offline documents and live web access.
- **Commerce:** decide paid-up-front versus an in-app lifetime unlock/trial. Do not add a paywall or price until the commercial terms are confirmed. If IAP is chosen, implement and test purchase, restore, entitlement persistence, failure/cancel, and offline behavior.
- **Metadata and reviewer notes:** match screenshots and descriptions to the shipping sandboxed feature set; disclose macOS/model/language requirements and disabled Nearby Transfer. No account is required by the current app.
- **Foreground UI pass (automation connection blocked):** Settings tabs, policy/terms/license sheets, scrolling and Escape/Done, selectable support address, AI toggles after switching tabs, and existing Tools keyboard regressions. The September 14 resumption did not reach UI interaction; announce again before taking mouse/keyboard control when the connection is restored.

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
