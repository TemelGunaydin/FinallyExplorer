# App Store preparation — September 13, 2026

This is an incremental implementation record, not a declaration that the app is ready for submission. The App Sandbox and app-icon blockers are still open. Do not upload this build as a release candidate yet.

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

This is a tested prerequisite, **not a completed sandbox migration**. Debug and Release still have `ENABLE_APP_SANDBOX = NO`. No foreground mouse/keyboard UI test was resumed.

### Next — Step 3B: finish access consumers, then enable and validate Sandbox

Before the shipping sandbox switch:

- Complete temporary file-selection and external drag/paste scope ownership, including cancellation while document reading is still unwinding. Do not assume the persistent folder owner covers unrelated individually chosen files.
- Refresh existing global FFF indexes after access changes without creating an eager whole-disk index. Pane-local invalidation is already connected.
- Update Offline Catalog's selected-subfolder validation: `LocalOfflineVolumeAccess.scopedSource` currently opens the volume root before traversing into the selected folder. A narrow sandbox grant must not require access to that unselected parent. Preserve volume identity, inode, symlink, and placeholder checks.
- Validate standard Desktop/Documents/Downloads/media paths, preference/container migration, terminal/Open With handoff, and ZIP subprocess behavior with sandbox entitlements. The named-user Home change alone is not proof of all sandboxed standard-folder behavior.
- Enable the minimal entitlements only after these consumers are ready. Check fresh sandboxed Release launch and relaunch with synthetic fixtures. The user-paused foreground UI session still requires explicit resumption.

### Full sandbox acceptance checklist

This is the next substantial implementation step. It must be completed as a coherent change before enabling App Sandbox in both shipping and development configurations.

1. Add a small security-scoped bookmark store and explicit user-selected-folder grant flow. Handle cancel, stale bookmarks, moved folders, and revocation without losing favorites or misreporting an inaccessible folder as empty.
2. Restore valid grants before browsing/search/tool models start. URLs alone are not persistent access. Verify the real user-home location separately from the sandbox container.
3. Carry scope through browsing, previews, search, drag/drop, file operations, catalogs, and document/image analysis; balance start/stop access. Do not silently replace a narrow grant with a whole-disk request.
4. Replace permission dead ends with a folder chooser/retry path. Retain System Settings guidance only for applicable macOS privacy denial.
5. Enable the minimum app-sandbox and user-selected read/write entitlements, then test a fresh install and relaunch with the **sandboxed Release build**. Check archive subprocess behavior and terminal/Open With handoff explicitly.
6. Regression matrix: grant/deny/cancel; stale/missing volume; Desktop/Documents/Downloads; 1–4 panes; copy/move/rename/Trash/ZIP; search/preview; Tools and AI with unavailable models. Use synthetic fixtures, not private user data.

This migration is not complete. A working unsandboxed Debug build is not evidence that the Mac App Store build will work.

## Remaining review items

- **App icon:** fill the empty AppIcon asset and verify the compiled icon resources at all required sizes. The website's small identity mark is not a replacement for the app's icon asset.
- **Archive error handling:** `compressItem` currently waits for the process before draining stderr. Add bounded concurrent draining and a regression that produces more than a pipe buffer of diagnostics, plus cancellation/cleanup tests. The risk was found in code review, not reproduced in the UI.
- **Shipping artifact:** archive/export and inspect the actual sandboxed, distribution-signed Release app, including embedded FFF signing/resources. Require sandbox entitlements and no `get-task-allow` in the distributed artifact. The current locally built Release app still has development `get-task-allow = true`; do not distribute it. Build success alone is not submission readiness.
- **Public legal/support URLs:** publish only after user approval and legal/provider checks; verify every URL before entering App Store Connect. Re-test the app's offline documents and live web access.
- **Commerce:** decide paid-up-front versus an in-app lifetime unlock/trial. Do not add a paywall or price until the commercial terms are confirmed. If IAP is chosen, implement and test purchase, restore, entitlement persistence, failure/cancel, and offline behavior.
- **Metadata and reviewer notes:** match screenshots and descriptions to the shipping sandboxed feature set; disclose macOS/model/language requirements and disabled Nearby Transfer. No account is required by the current app.
- **Foreground UI pass (pending user resumption):** Settings tabs, policy/terms/license sheets, scrolling and Escape/Done, selectable support address, AI toggles after switching tabs, and existing Tools keyboard regressions. Do not automatically resume the paused mouse/keyboard session.

## Verification record

- Website: four static pages and 72 local references pass validation; layout-switch state tests pass; all four localhost routes return HTTP 200.
- The first full app regression caught AI Settings expanding to a 1061-point intrinsic width after its width constraint was removed. The explicit 580-point width was restored while allowing the height to fit the Settings tab.
- Step 2 full background regression: **582 tests passed across 81 suites, 0 failures/skips** using XcodeBuildMCP. Result bundle: `test_macos_2026-09-13T11-20-39-277Z_pid81896_37159a36.xcresult`. Includes existing file/search/AI and offscreen presentation regressions plus the new legal-resource and metadata tests. This is not a new interactive UI pass.
- XcodeBuildMCP **Release build succeeded**. Log: `build_macos_2026-09-13T11-22-29-978Z_pid82183_b783dc27.log`. Inspected `Build/Products/Release/FinallyExplorer.app`: Privacy Policy, Terms, Devicon and FFF notices are in `Contents/Resources`; FFF notice matches `Vendor/FFF/LICENSE` byte for byte; category, copyright, and Downloads description are present in the built Info.plist.
- The inspected Release build is still **unsandboxed and missing its app icon**. It is not an archived/exported App Store candidate, and the public legal website is not deployed. These remain submission gates, regardless of the successful build.
- Step 3A full background regression: **603 tests passed, 0 failures/skips** using XcodeBuildMCP. Result bundle: `test_macos_2026-09-13T11-55-14-775Z_pid86286_05eddc42.xcresult`. Includes 21 new access tests: persistence/relaunch, native macOS bookmark codec and real fixture rename, duplicate scopes, balanced release, panel cancel/failure, stale/missing/denied records, storage rollback/corruption, repeated/nested moves, reused old paths, remote-URL rejection, and named-account Home lookup. These tests ran with the current **unsandboxed** app host and synthetic fixtures; they do not establish sandboxed cross-process grant/relaunch behavior or replace native-panel UI testing.
- Step 3A XcodeBuildMCP **Release build succeeded**. Log: `build_macos_2026-09-13T11-57-53-343Z_pid86592_af84fed5.log`. This is a build check, not an archive/export, App Store validation, or foreground UI pass. No push, deployment, or submission was performed.

## Official references

- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) — Mac App Store sandbox, completeness, privacy, and support expectations.
- [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).
- [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox).
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/).
- [Apple Standard EULA](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/).

Required-reason API manifest guidance must be checked against the app's actual platform. Do not incorrectly treat the iOS-family required-reason API list as a universal native-macOS submission blocker.
