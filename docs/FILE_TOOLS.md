# Local File Tools

Open a folder, then choose **File Tools** (the wrench icon) in the window toolbar. The tools use the active panel's folder, not the entire Mac. They need no Apple Intelligence model, account, API or network service. Nothing runs at startup or on each search keystroke. Ask AI still cannot execute file-changing commands.

## Find Duplicates

1. Choose **Find Duplicates…**, inspect the selected folder, and click **Scan Folder**.
2. Review groups of files with identical contents. No copies are selected automatically. Select the copies to remove; at least one copy per group must remain unselected.
3. **Review Removal…** lists every selected path and a matching copy that will remain. **Cancel** changes nothing. Only **Move to Trash** authorizes removal.

The scanner first groups regular, nonempty files by byte size, hashes only same-size candidates with streaming SHA-256, then checks candidate matches byte for byte. Names/extensions and modification dates need not match. Dates, tags, permissions and other metadata are not compared. It reads bounded chunks, not entire files into memory.

Hidden items are opt-in. Hard links, nonempty/unreadable resource forks, symlinks, packages, special files, cloud placeholders and nested mounts are excluded. Package contents are not traversed. Root `/` and package roots are rejected; the shared scanner has a 50,000-entry / 64-level limit. Changing/unreadable trees can stop a scan rather than produce actionable results from an incomplete view.

The displayed duplicate-data size is **logical file data**, not a promise of disk space recovered. APFS clones/shared storage can reduce that amount, and moving items to Trash does not empty Trash.

Before any removal the service revalidates every selected file and its retained copy, including identity, change tokens, SHA-256, resource-fork policy and matching bytes. It checks again at each removal boundary and uses no-follow child traversal. The operation uses the existing Finder-style recycler and shared file-operation mutation gate, not permanent deletion or shell cleanup commands. Normal copy/paste, rename and clipboard behavior remain independent.

Cancellation stops at safe boundaries. Already completed removals are reported and directory views are refreshed; remaining files are left alone. If cancellation arrives while Finder is completing a removal, that completed item is still counted. After success, failure or cancellation, rescan before another removal. These checks are not a transactional filesystem lock or a guarantee against concurrent external modifications between validation and Finder's path-based recycle operation.

## Organize Folder — preview only

Choose **Organize Folder (Preview)…** and group by **File Type** or **Modified Month**. **Preview Changes** shows source → destination paths inside the selected root.

- Only immediate regular files are considered. Existing folders and their contents stay in place; project trees are not recursively reorganized.
- File type uses the application's existing extension/UTType classification. It does not infer document topics.
- Dates use filesystem modification time and the Mac's calendar/timezone, not photo capture or download/import dates.
- Existing target names and unsafe destination folders are listed as skipped; no overwrite or automatic renaming is proposed.
- This delivery is deliberately read-only: **no files move and no folders are created**. Applying a reviewed organization plan is the next phase and needs fresh validation and explicit approval at execution time.

## Validation and design

Use XcodeBuildMCP for builds and tests. Synthetic fixtures cover grouping, size prefiltering, hard links/resource forks, hidden entries, traversal exclusions, bounds, cancellation, changed keepers/sources/parents, partial completion, confirmation guards, directory refresh, grouping rules and no-write previews.

Offscreen light/dark renders check sheet sizing. XCTest covers selection, keeping one copy, cancelling and approving removal, refreshing the file panel, and the read-only organization preview. Interactive tests operate on temporary fixtures, never the user's working files.

Delivery validation (2026-09-08): **435 tests passed, zero failures or skips** in the final XcodeBuildMCP run: 425 unit/integration/offscreen tests across 57 suites, plus 10 interactive UI scenarios. The UI selection covers both new tools, Ask AI, folder comparison, split/reset layout, copy/paste feedback, rename, cancelling new-folder creation, content-search controls and compact-name matching. All three new sheets were also rendered and inspected in light/dark appearances.

Final result bundle: `test_macos_2026-09-08T10-48-22-770Z_pid46433_a95b7f96.xcresult` in the XcodeBuildMCP workspace. UI diagnostics use app-window accessibility text instead of explicit desktop screenshots, which can capture an unrelated monitor on multi-display Macs. Offscreen render fixtures provide visual artifacts without capturing other applications.

The SwiftUI, Swift Concurrency and Swift Testing guides informed the shared theme, explicit accessibility containers, lazy results, off-main bounded I/O, cancellation/generation guards and deterministic tests. Accessibility containers also fix identifier propagation in the existing Ask AI and folder-comparison sheets.
