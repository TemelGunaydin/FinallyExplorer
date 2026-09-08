# Visual Search — first delivery

## Available now

Open **File Tools → Visual Search…**. The current Explorer folder is suggested, or choose another local folder. **Analyze Folder** is the explicit consent/start action: opening the panel or launching the app never starts this analysis.

Apple Vision classifies supported still images and recognizes English text inside them. Search the resulting **Visual Labels**, **Text in Images**, or both. Every query word must match observed evidence; filenames and paths are display/navigation metadata, not a fallback match. Results show the matching labels and/or a bounded OCR excerpt, along with a thumbnail and **Show in Explorer**.

This is a label/OCR search, not open-vocabulary visual conversation. Labels may be incomplete or wrong. Examples like `beach` or `cat` depend on the labels Vision actually observes. There is no person identification, Photos-library access, semantic embedding index, video search, or document Q&A in this delivery. No downloaded third-party model, API key, cloud service, or Apple Intelligence enablement is needed for this Vision-only tool.

## Privacy and lifetime

- Only the explicitly chosen folder and eligible subfolders are analyzed.
- Labels, up to 4,000 OCR characters per image, and small thumbnails are held in the current Explorer window's memory. No analysis database or disk thumbnail cache is created by this feature.
- Closing the panel cancels pending work and retains the last completed analysis for reopening. **Clear Analysis**, changing the source, or changing the hidden-items option forgets it. Closing the Explorer window/app releases the window's analysis. Cancellation may need to wait for an in-flight Vision request to unwind; cleared evidence cannot reappear afterward.
- Hidden items are excluded by default. Child symlinks, app/library packages, cloud placeholders, special files and nested volumes are not traversed. The Mac root, network folders and package roots are rejected. Only the explicitly selected root path is canonicalized.
- No file contents enter Ask AI or its Foundation Models session. Existing FFF/grep, Spotlight search, Smart Rename and Offline Catalogs remain separate.

## Limits and correctness

- Up to **300** supported image candidates per analysis; **25,000** tree entries, **64** path levels and **2 MB** of relative-path text. Exceeding a scan limit returns an error rather than a silently partial index.
- Supported extensions: JPEG/JPG, PNG, HEIC/HEIF, TIFF/TIF and BMP. Only single-image containers are accepted. No RAW, animated GIF, SVG, PDF, multi-page TIFF or Photos-library containers.
- Per image: at most **40 MB**, **80 megapixels**, and **20,000 pixels per edge** before decoding. Analysis uses an orientation-corrected image with a maximum edge of **1,600 px**; fine/small text may be missed. Retained JPEG thumbnails are at most **240 px** and **100 KB** each, with no source metadata copied.
- Retain at most 12 labels with a Vision confidence of at least 0.2. These are classifier scores, not presented as calibrated probabilities. The UI shows evidence instead of claiming certainty.
- ImageIO decode/size failures are listed under skipped images. A Vision/backend failure fails the new analysis and preserves the previous one. There is no silent cloud fallback.
- Input is read through descriptor-relative, no-follow, bounded reads, not memory mapping. File identity/change tokens are checked around reads and the entire enumerated snapshot is validated again before publication. A changed source invalidates the new snapshot.
- Show in Explorer rechecks the root identity, ancestor identities and exact image token; changed, removed, or link-swapped results are rejected. This is a read-only navigation check, not a filesystem lock against a later external change.
- Scans process one image at a time off the main actor. Cancel prevents publication and retains the busy gate until requests unwind. Search cancellation/generation checks prevent earlier queries from replacing newer results. Search is limited to 200 characters and displays the first 150 matches with the complete matching count.

## Validation

Use XcodeBuildMCP's macOS build/test workflow. New tests cover real Vision classification/OCR on generated receipt pixels, filename-independent evidence matching, case/diacritic handling, bounded snippets, scan limits, hidden/link/package exclusions, invalid input, stale-file/ancestor checks, explicit start, cancellation and late completion, memory clearing, and preserving previous analysis after failure.

The actual Vision integration and macOS UI tests use synthetic receipt images. They validate execution and text retrieval, **not real-world photo-scene recall or classification accuracy**. Broader photo evaluation remains necessary before claiming Siri-level scene retrieval. UI tests cover analysis, OCR search, reopen/clear/relaunch and rejecting changed results. Light/dark layout is rendered to offscreen windows; no unrelated desktop screenshot is captured.

The SwiftUI, Swift Concurrency and Swift Testing guides informed themed/accessibility-labelled controls, off-main bounded analysis, cancellable task ownership, generation guards, and deterministic tests.

Validated on 2026-09-08 with XcodeBuildMCP: **511 tests passed, zero failures/skips** — 494 unit/integration/presentation tests and 17 selected macOS UI regressions. These include normal name/content search, copy/paste, rename, New Folder cancellation, grid reset, USB listing/eject, comparison, duplicates, organization, offline catalogs and both new Visual Search UI scenarios. The existing Ask AI test actor's conformance was moved to an extension to avoid the beta compiler incorrectly inferring nonisolated actor isolation; its behavior is unchanged. Result bundle: `test_macos_2026-09-08T15-28-56-250Z_pid8580_e54e893e.xcresult`.

## Apple APIs

The implementation uses [ClassifyImageRequest](https://developer.apple.com/documentation/vision/classifyimagerequest) and [RecognizeTextRequest](https://developer.apple.com/documentation/vision/recognizetextrequest), with ImageIO downsampling. API signatures/availability were checked against the installed SDK; the app's macOS 26 deployment target was not raised.

## Next

Questions over explicitly selected documents: bounded local text/PDF extraction, relevant passage retrieval, and on-device answers with inspectable source references. No API integration or automatic whole-library scan is planned for that first scope.
