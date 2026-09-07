# Compare Folders & Verified Copy

Open two different folders in workspace panels, then use **Compare Folders** in the window toolbar. Choose source and destination panels and click **Compare**. The feature is local and independent of Apple Intelligence; it needs no model, account, API or network connection.

## What the comparison means

- File paths are relative to the selected roots. Regular files are compared by streaming SHA-256 hashes, not just size or date. **Same Data** does not assert equal metadata, resource forks, permissions or tags.
- Hidden items are excluded by default. Enable **Include hidden items** to compare them.
- Packages (including applications), symlinks, special files, cloud placeholders and mounted subfolders are reported as **Not Compared**, not silently treated as equal. Links and nested mounts are never followed. Download cloud files first or compare a mounted folder directly.
- Each root has a 50,000-entry / 64-level safety limit. There is no automatic comparison at startup or on each keystroke. Reading large files can take time; progress is throttled and cancellation is available.
- A folder that changes while being read invalidates the comparison. Same/overlapping roots, including filesystem aliases, are rejected.

## Copy authorization and integrity

**Review Copy Missing…** shows an immutable list with the source, destination and counts. Nothing is written before **Copy & Verify**. Cancelling the review writes nothing.

This release adds only eligible source-side missing entries. It does not overwrite changed files, delete destination-only files, merge packages or automatically synchronize. Items underneath type-conflicting or skipped parents are not eligible. A newly created folder can contain only the eligible children listed in the review; skipped children are not copied.

All approved sources and destinations are preflighted before the first write. Directory descriptors, identity/change tokens and no-follow child opens protect traversal. Root and parent locations are revalidated before publishing files. A collision stops the operation; it never silently replaces the destination or chooses a different name.

For every regular file:

1. Copy data to an exclusively created hidden staging file in the destination parent, rechecking the source hash against the comparison.
2. Copy file metadata using Apple's `fcopyfile(COPYFILE_METADATA)` and flush the file.
3. Read the staged file back and compare its SHA-256 data hash.
4. Publish with exclusive atomic rename (`RENAME_EXCL`). There is no unsafe overwrite fallback on filesystems that do not support this operation.

Metadata is copied, but only the regular data fork is hash-verified. New directories use standard permissions. This is a copy tool, not a full-fidelity filesystem backup or a guarantee against later disk failures or external changes after completion.

Cancellation/failure removes owned unpublished staging where the filesystem permits it. If permissions prevent cleanup, the report identifies the remaining temporary file instead of claiming cleanup succeeded. Already verified files and created folders stay in the destination and are counted in the report. The old comparison is invalidated. Run **Compare Again** for a fresh view. Normal copy/paste behavior is unchanged; verified copying shares its mutation gate and directory-refresh pipeline.

## Validation

Swift Testing covers hashes, multi-chunk/empty files, xattrs, timestamps/permissions, hidden files, links/packages/special files, bounds, overlap aliases, changing trees, preflight/late collisions, moved roots/parents, corrupted staging, cancellation, confirmation/stale-plan guards, clipboard preservation and directory refresh.

The offscreen presentation tests render comparison and copy-review sheets in light/dark without activating a window. XCTest also includes `testFolderComparisonRequiresApprovalAndCopiesOnlyMissingFiles` for real two-panel navigation, review cancellation, copy approval and refreshed results. Run it only when foreground UI automation is authorized; compilation/offscreen rendering is not a substitute for this interactive test.

Build and test using XcodeBuildMCP, as required by the project owner.

Delivery validation (2026-09-07): 199 selected new and regression tests passed, with zero failures or skips. The regression selection includes file operations, rename, workspace layout/model, FFF/name/content search, Ask AI and Smart Rename. Both sheet appearances were rendered offscreen and visually inspected. The interactive XCTest was compiled but not executed; foreground automation approval was not provided.

The SwiftUI, Swift Concurrency and Swift Testing guides shaped theme/accessibility reuse, off-main bounded I/O, cancellable tasks with stale-result guards, and deterministic fixture-based tests.
