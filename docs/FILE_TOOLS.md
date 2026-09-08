# Local File Tools

Choose **File Tools** (the wrench icon) in the window toolbar. Duplicate removal and organization use the active panel's folder, not the entire Mac. [Offline Catalogs](OFFLINE_CATALOGS.md) has its own explicit external-disk folder selection and saved-metadata search. These tools need no Apple Intelligence model, account, API or network service. No scans or file-changing operations run at startup or on each search keystroke. Ask AI still cannot execute file-changing commands.

## Find Duplicates

1. Choose **Find Duplicates…**, inspect the selected folder, and click **Scan Folder**.
2. Review groups of files with identical contents. No copies are selected automatically. Select the copies to remove; at least one copy per group must remain unselected.
3. **Review Removal…** lists every selected path and a matching copy that will remain. **Cancel** changes nothing. Only **Move to Trash** authorizes removal.

The scanner first groups regular, nonempty files by byte size, hashes only same-size candidates with streaming SHA-256, then checks candidate matches byte for byte. Names/extensions and modification dates need not match. Dates, tags, permissions and other metadata are not compared. It reads bounded chunks, not entire files into memory.

Hidden items are opt-in. Hard links, nonempty/unreadable resource forks, symlinks, packages, special files, cloud placeholders and nested mounts are excluded. Package contents are not traversed. Root `/` and package roots are rejected; the shared scanner has a 50,000-entry / 64-level limit. Changing/unreadable trees can stop a scan rather than produce actionable results from an incomplete view.

The displayed duplicate-data size is **logical file data**, not a promise of disk space recovered. APFS clones/shared storage can reduce that amount, and moving items to Trash does not empty Trash.

Before any removal the service revalidates every selected file and its retained copy, including identity, change tokens, SHA-256, resource-fork policy and matching bytes. It checks again at each removal boundary and uses no-follow child traversal. The operation uses the existing Finder-style recycler and shared file-operation mutation gate, not permanent deletion or shell cleanup commands. Normal copy/paste, rename and clipboard behavior remain independent.

Cancellation stops at safe boundaries. Already completed removals are reported and directory views are refreshed; remaining files are left alone. If cancellation arrives while Finder is completing a removal, that completed item is still counted. After success, failure or cancellation, rescan before another removal. These checks are not a transactional filesystem lock or a guarantee against concurrent external modifications between validation and Finder's path-based recycle operation.

## Organize Folder — reviewed moves

1. Choose **Organize Folder…** and group by **File Type** or **Modified Month**. **Preview Changes** shows source → destination paths inside the selected root. This step is read-only: no files move and no folders are created.
2. **Review Moves…** lists the files to move and the subfolders to create. **Cancel** changes nothing.
3. Only **Move Files** authorizes changes. Files stay on the same disk, inside the selected root; their names remain unchanged. A completion report lists the moves and created folders. Open panels and cached folder sizes are refreshed through the existing shared file-operation coordinator.

- Only immediate regular files are considered. Existing folders and their contents stay in place; project trees are not recursively reorganized.
- File type uses the application's existing extension/UTType classification. It does not infer document topics.
- Dates use filesystem modification time and the Mac's calendar/timezone, not photo capture or download/import dates.
- Existing target names and unsafe destination folders are listed as skipped; no overwrite or automatic renaming is proposed.
- Hidden files are opt-in. Hard-linked files, symlinks, packages, special files, cloud placeholders and nested mounts are excluded. Hidden destination folders are also excluded unless hidden items are enabled. Existing safe category folders are reused, including filesystem case aliases such as `documents`/`Documents`.

All approved sources and destinations are revalidated before the first write, then again at each move boundary. Source identity and change tokens must still match the preview; existing destination folders must keep their identity. A previously absent folder that appears after preview requires a new preview. Child directory traversal and source opens use no-follow descriptors. A same-volume, exclusive `renameatx_np(RENAME_EXCL)` moves each file without copying its data and preserves its inode, attributes and resource fork. There is no cross-volume copy/delete fallback, silent overwrite, or automatic renaming.

Cancellation and errors stop before the next file. **Completed moves and newly created folders remain in place**, including a created folder that is still empty; there is no automatic rollback or Undo in this delivery. The report records completed writes even if cancellation arrives immediately afterward. After success, cancellation or failure, generate a fresh preview before another operation. These checks are not a multi-file transaction or a filesystem lock against concurrent external changes in the interval between the final check and rename.

Organization shares the window's ordinary write gate, so it cannot overlap paste, rename, duplicate removal or verified copy in that window. It does not consume or replace the clipboard. Changes from other windows or applications are subject to the same revalidation limits above. Ask AI cannot trigger it, and no model or network access is involved.

## Validation and design

Use XcodeBuildMCP for builds and tests. Synthetic fixtures cover grouping, size prefiltering, hard links/resource forks, hidden entries, traversal exclusions, bounds, cancellation, changed keepers/sources/parents, partial completion, confirmation guards, directory refresh, grouping rules and no-write previews.

Offscreen light/dark renders check sheet sizing. XCTest covers selection, keeping one copy, cancelling and approving removal, the read-only organization preview, cancelling its review, confirming moves and refreshing the file panel. Interactive tests operate on temporary fixtures, never the user's working files.

Previous delivery validation (2026-09-08): **435 tests passed, zero failures or skips**: 425 unit/integration/offscreen tests across 57 suites, plus 10 interactive UI scenarios. The UI selection covers both tools, Ask AI, folder comparison, split/reset layout, copy/paste feedback, rename, cancelling new-folder creation, content-search controls and compact-name matching.

Reviewed-move validation (2026-09-08): **440 unit/integration/offscreen tests passed across 59 suites** in `test_macos_2026-09-08T12-27-13-030Z_pid65103_58f0060a.xcresult`. That run's UI checks failed with automation permission/connection errors. The two organization UI scenarios were then rerun successfully, with zero failures or skips, in `test_macos_2026-09-08T13-34-19-083Z_pid13719_c7f3ce09.xcresult`. They verify read-only preview, cancelled confirmation, approved moves and panel refresh. Previews, reviews and completion states were rendered and inspected in light/dark appearances.

Result bundles are in the XcodeBuildMCP workspace. UI diagnostics use app-window accessibility text instead of explicit desktop screenshots, which can capture an unrelated monitor on multi-display Macs. Offscreen render fixtures provide visual artifacts without capturing other applications.

Latest regression after [Offline Catalogs](OFFLINE_CATALOGS.md) (2026-09-08): **491 tests passed with zero failures or skips** — 476 unit/integration/offscreen tests and 15 UI scenarios, including both organization workflows and the previous file/search regressions. Result bundle: `test_macos_2026-09-08T14-20-28-403Z_pid44300_533ace45.xcresult`.

The SwiftUI, Swift Concurrency and Swift Testing guides informed the shared theme, explicit accessibility containers, lazy results, off-main bounded I/O, cancellation/generation guards and deterministic tests. Accessibility containers also fix identifier propagation in the existing Ask AI and folder-comparison sheets.
