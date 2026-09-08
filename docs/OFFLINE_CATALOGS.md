# Offline Catalogs — explicit metadata snapshots

Open **File Tools → Offline Catalogs…**. Choose a connected disk, or use **Choose Folder…** to select a smaller folder on it. Inspect the selected path and hidden-item option, then click **Scan & Save**. Merely choosing a source does not scan or create a cache.

## What is available

- Search the selected saved catalog by words in names/relative paths. All words must match; this is a literal, case/diacritic-insensitive metadata search, not FFF fuzzy search or grep.
- Combine extension, minimum file size and modification-date filters. Up to 200 matching rows are displayed, with the full match count. Folder sizes are not recursively calculated.
- Search saved metadata after the original disk is disconnected, including after relaunching the app. Every result is explicitly labelled as saved metadata, not a live folder view, and shows the last scan time.
- **Refresh Snapshot** explicitly scans the same saved scope, preserving its hidden-item choice. To choose a different scope or hidden-item option, choose the source again and use **Scan & Save**.
- **Show in Explorer** is available only with the original disk connected. The action rechecks the volume and item identity before revealing the location; it never executes or modifies the file. Replaced/moved items require a new scan.
- **Remove Saved Catalog** has a separate confirmation and removes only local catalog metadata. Original files are unchanged. Canceling the confirmation removes nothing.

There is no automatic scan on app startup, disk mount, or each search keystroke. Mount notifications update connection status only. Search runs off the main actor against the selected in-memory snapshot; ordinary FFF name search, grep/content search, Ask AI and the clipboard are not involved.

## Scope, identity and exclusions

This first delivery supports local external volumes that expose a persistent UUID. It rejects internal disks, network shares, package roots and unsupported volumes without that identifier. A user-selected subfolder is recorded relative to its volume root. The app uses Apple's [persistent volume UUID](https://developer.apple.com/documentation/foundation/urlresourcevalues/volumeuuidstring) and [local-volume flag](https://developer.apple.com/documentation/foundation/urlresourcevalues/volumeislocal), not the disk's display name, to establish this scope.

A disk can reconnect at a different mount path or with a different display name. A different disk with the same name is not accepted. Multiple connected disks with the same UUID are treated as ambiguous, disabling live actions until only the original remains. Root/item inode checks additionally reject a replaced item at the same path. These are filesystem identity checks, not cryptographic device authentication; filesystems that do not retain those identities may require choosing and scanning the folder again.

Enumeration uses the shared no-follow folder scanner. Child symlinks, packages, special files, cloud placeholders and nested mounts are skipped, not traversed or downloaded. Hidden entries are opt-in. Hard links may appear as separate metadata rows: this tool does not deduplicate or mutate them. The root and all enumerated change tokens are checked before accepting a snapshot; an unreadable or changing tree can stop the scan.

Limits per snapshot: **100,000 enumerated entries, 64 levels, 16 MB of relative-path UTF-8 data, 64 MB serialized payload**. Up to **32 catalogs** are retained. Larger trees require selecting a smaller subfolder; an incomplete/over-limit scan never replaces the prior snapshot.

## Storage and cancellation

Only relative paths/names, file byte counts, modification dates, directory flags, volume UUID/name, root/item inodes, scan time and exclusion counts are stored. No file contents, hashes, thumbnails, embeddings or model output are stored. There is no account, API, downloaded model or network service.

Snapshots live in `~/Library/Application Support/FinallyExplorer/OfflineCatalogs`, in an app-owned directory with owner-only permissions. The JSON metadata is **not separately encrypted**; filenames can be sensitive and normal system backups may retain copies. Removing a catalog is not secure erasure and does not remove external backups.

One shared actor serializes local registry changes across the app's windows. A new bounded payload is written first; an atomic registry replacement publishes it only after a successful scan. The old payload is then cleaned up. Errors/cancellation before publication preserve the old catalog. A save that already committed remains reported as successful even if cancellation arrives immediately afterward. Abrupt termination may leave an unreferenced payload; removing that catalog also removes its local payload directory.

Decoding is bounded and validates schema, counts, unique paths/scopes, relative-path safety and metadata. A malformed registry is reported instead of silently resetting the cache. A bad payload can be removed through its registry entry or replaced by an explicit successful scan. Removing a catalog first updates the registry; a later local cleanup failure is reported without leaving a stale row or touching source files.

The feature does not add a filesystem transaction or lock. Another application can change a source after the final validation. It adds no privileged helper, broad-disk entitlement, mount operation or permission bypass. A future sandboxed App Store build still needs its own security-scoped access/review validation; this implementation does not claim to solve that release work.

## Validation

Swift Testing fixtures cover metadata-only reads, selected subfolder scope, hidden/link/package exclusions, scan limits, changing trees, persistence, refresh, corruption, cancellation, name/UUID mismatches, reconnects at a new mount path, replaced entries, search filters/limits, stale queries, confirmation guards and post-commit cancellation. Light/dark sheets are rendered offscreen and inspected without capturing other applications.

XCTest uses isolated temporary volume and storage fixtures for explicit save, relaunch, simulated disconnect/reconnect, search, reveal, cancelled removal and confirmed metadata-only removal. This is not a hardware USB/eject certification. UI test mode never uses the production catalog store or live volume discovery, including when its fixture volume is absent.

Final validation (2026-09-08): **491 tests passed, zero failures or skips** — 476 unit/integration/offscreen tests across 63 suites, plus 15 interactive UI scenarios. The selection includes existing Ask AI, FFF/grep controls and compact-name matching, copy/paste, rename, cancel-new-folder, duplicates, comparison/verified copy, organization, split/reset layout and USB display/eject scenarios, as well as the two catalog flows. Result bundle: `test_macos_2026-09-08T14-20-28-403Z_pid44300_533ace45.xcresult` in the XcodeBuildMCP workspace. Offline, prepared-to-scan and removal states were inspected in light/dark offscreen renders.

On this macOS test runner, XCTest's `typeText("c")` dropped the character even in isolation, while `typeKey` delivered it. The catalog UI query helper therefore sends individual key events and asserts the complete field value before checking matches. Static text assertions use macOS accessibility values, not labels. The final regression run includes these corrected assertions.

The SwiftUI, Swift Concurrency and Swift Testing guides informed the themed accessible sheets, lazy bounded rows, off-main I/O/search, shared actor store, cancellation/generation guards and deterministic gate-based tests.
