# Ask Documents: actionable read failures — September 21, 2026

## Scope

- Replace the combined permission/encoding/password guess with distinct errors for access denial, a missing file, a cloud placeholder, a link, a locked PDF, a PDF that cannot be parsed, unsupported text encoding, and byte/page/text limits. Each read failure identifies the affected filename and offers a next step; raw system paths and comparison/copy-specific errors are not displayed.
- Keep all existing read limits: 20 MiB and 100 PDF pages per file, 200,000 characters per document, 300,000 characters per selection, and the existing OCR limits/deadline. No truncation, automatic file conversion, password handling or user-file mutation is added.
- A synthetic 416-page PDF now produces: “This PDF has 416 pages; the limit is 100. Choose a shorter PDF or export just the pages you need.” The reported user document was previously inspected read-only with PDFKit: 416 pages, unlocked, and readable text. Exceeding the limit is confirmed, but the original screenshot's generic failure cannot be attributed to that limit: the old page-limit message was different. The original UI failure has not been reproduced in this increment.
- Ask Documents now opens the parent directory for **search**, not directory-content reading. This keeps descriptor-relative `openat`/`fstatat`, no-follow checks, file/parent identity validation and scoped-access lifetime while avoiding a directory-listing requirement for a selected-file workflow. The change is confined to this reader; shared folder comparison/copy behavior and entitlements are unchanged. [`O_SEARCH` is documented by Apple](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/man/man2/open.2).
- Permission loss during source validation clears cached document context and answers, and reports access recovery. Cancellation remains silent. Failed multi-document reads do not publish partial context.
- Error banners can wrap vertically. Existing controls, English UI, AI behavior and document limits remain unchanged.

## Verification

- XcodeBuildMCP macOS tests use generated temporary fixtures only. The user's PDF is not copied into the repository or modified.
- Added regression coverage for the 416-page message before OCR, encrypted versus malformed PDFs, missing versus permission-denied files, parent replacement, source-permission loss, Cocoa/POSIX error classification, failed-file identification, retry recovery and no partial publication.
- The search-only parent test removes directory read permission from a disposable fixture, proves the old read-directory open fails, and verifies reading/validating its known file still works. This is a POSIX regression test, **not** proof of a native file-picker sandbox grant.
- Offscreen presentation checks exercise page-limit, permission and password errors with five selected documents in both themes. Page-limit/light and permission/dark renders were visually inspected; the banner and recovery copy fit. No foreground window or mouse/keyboard automation was used.
- The initial test build failed only on an incompletely qualified PDFKit option name in the new encrypted-PDF fixture. That fixture was corrected; no production fallback or weakened assertion was used.
- First executable batch: **55 passed, 2 failed, 0 skipped**, bundle `test_macos_2026-09-20T21-23-54-074Z_pid73210_9f6c1d0d.xcresult`. Both failures were actual Vision recognition timeouts (`mixedDocument` and `blankScan`); deterministic OCR safety, read/model and presentation checks passed. The Vision implementation and timeout were not changed. This batch is not recorded as green.
- Final deterministic read/model/OCR-safety/presentation batch, including permission-loss handling: **53 passed, 0 failed, 0 skipped**, bundle `test_macos_2026-09-20T21-26-02-329Z_pid74905_7110f9b3.xcresult`.
- Separate actual PDF/OCR repeat: **4 passed, 1 failed, 0 skipped**, bundle `test_macos_2026-09-20T21-26-53-620Z_pid75385_d06d0ba1.xcresult`. The blank scan passed on this repeat; `mixedDocument` still timed out. Actual OCR reliability remains open, not fixed by the error-message/access correction. No timeout was increased and no failure was skipped or reclassified as success.

Native picker acceptance with the separately signed QA app remains pending. Do not infer that the original user PDF has been read successfully in the app, or that a full release regression passed, from these focused checks.
