# Visual Search — labels, OCR and natural descriptions

## Available now

Open **File Tools → Visual Search…**. The current Explorer folder is suggested, or choose another local folder. **Analyze Folder** is the explicit consent/start action: opening the panel or launching the app never starts this analysis.

Apple Vision classifies supported still images and recognizes English text inside them. Search the resulting **Visual Labels**, **Text in Images**, or both. Every query word must match observed evidence; filenames and paths are display/navigation metadata, not a fallback match. Results show the matching labels and/or a bounded OCR excerpt, along with a thumbnail and **Show in Explorer**.

You can also type **`Find photos taken by the sea`** in **Ask AI**, or use its **Search Photos** button. This opens Visual Search with the description filled in. If the chosen folder has not been analyzed, **Analyze Folder** still requires an explicit click; afterward select **Find Photos**. Reopening with an already analyzed folder reuses its in-memory evidence without rescanning.

Natural descriptions are converted to small groups of English visual concepts. Alternatives within a group are OR matches (`beach / seashore / coast / coastal / ocean / sea`); separate concepts must all match, for example a dog AND a beach. Matches require whole-word observed labels, not OCR, filenames, or paths. The interpretation and the matching image labels are visible. Common exact seaside sentences have a fast deterministic path; other descriptions use Apple's on-device Foundation Models model. No images or OCR text enter that language-model session.

This remains **classifier-backed retrieval, not unrestricted visual understanding or Siri parity**. Labels may be incomplete or wrong; synonyms cannot retrieve a scene that Vision failed to label. There is no person identification, GPS/named-place filtering, Photos-library access, semantic embedding index, or video search. Natural photo descriptions do not combine capture-date, exclusion, count, relation, or file-operation filters; unsupported conditions produce an error instead of intentionally being dropped. The model's interpretation of more complex requests can still be imperfect. Explicit filename queries and date-only requests remain in the original Ask AI search.

No downloaded third-party model, API key or cloud service is used. Manual label/OCR search and the common seaside shortcut do not require Apple Intelligence. Other natural descriptions require an eligible Mac with Apple's on-device model ready. English is the supported initial language.

## Privacy and lifetime

- Only the explicitly chosen folder and eligible subfolders are analyzed.
- Labels, up to 4,000 OCR characters per image, and small thumbnails are held in the current Explorer window's memory. No analysis database or disk thumbnail cache is created by this feature.
- Closing the panel cancels pending work and retains the last completed analysis for reopening. **Clear Analysis**, changing the source, or changing the hidden-items option forgets it. Closing the Explorer window/app releases the window's analysis. Cancellation may need to wait for an in-flight Vision request to unwind; cleared evidence cannot reappear afterward.
- Hidden items are excluded by default. Child symlinks, app/library packages, cloud placeholders, special files and nested volumes are not traversed. The Mac root, network folders and package roots are rejected. Only the explicitly selected root path is canonicalized.
- No image bytes, OCR, labels, filenames or paths enter the photo-description Foundation Models session; it receives only the user's description. Existing FFF/grep, Spotlight search, Smart Rename and Offline Catalogs remain separate. [Document Questions](DOCUMENT_QUESTIONS.md) is a different, explicitly opted-in document-content workflow.
- Disabling **Ask AI & Smart Search** clears/cancels the natural description, including while its panel is closed. The manually approved Vision analysis remains usable through label/OCR search. Clear Analysis forgets both.

## Limits and correctness

- Up to **300** supported image candidates per analysis; **25,000** tree entries, **64** path levels and **2 MB** of relative-path text. Exceeding a scan limit returns an error rather than a silently partial index.
- Supported extensions: JPEG/JPG, PNG, HEIC/HEIF, TIFF/TIF and BMP. Only single-image containers are accepted. No RAW, animated GIF, SVG, PDF, multi-page TIFF or Photos-library containers.
- Per image: at most **40 MB**, **80 megapixels**, and **20,000 pixels per edge** before decoding. Analysis uses an orientation-corrected image with a maximum edge of **1,600 px**; fine/small text may be missed. Retained JPEG thumbnails are at most **240 px** and **100 KB** each, with no source metadata copied.
- Retain at most 12 labels with a Vision confidence of at least 0.2. These are classifier scores, not presented as calibrated probabilities. The UI shows evidence instead of claiming certainty.
- ImageIO decode/size failures are listed under skipped images. A Vision/backend failure fails the new analysis and preserves the previous one. There is no silent cloud fallback.
- Input is read through descriptor-relative, no-follow, bounded reads, not memory mapping. File identity/change tokens are checked around reads and the entire enumerated snapshot is validated again before publication. A changed source invalidates the new snapshot.
- Show in Explorer rechecks the root identity, ancestor identities and exact image token; changed, removed, or link-swapped results are rejected. This is a read-only navigation check, not a filesystem lock against a later external change.
- Scans process one image at a time off the main actor. Cancel prevents publication and retains the busy gate until requests unwind. Search cancellation/generation checks prevent earlier queries from replacing newer results. Manual search is limited to 200 characters; natural requests to 500 characters and four concepts with up to eight alternatives each. The UI displays the first 150 matches with the complete matching count. Natural inference has a 30-second cancellation deadline; the busy gate remains held while cancellation unwinds.

## Validation

Use XcodeBuildMCP's macOS build/test workflow. New tests cover real Vision classification/OCR on generated receipt pixels, filename-independent evidence matching, case/diacritic handling, bounded snippets, scan limits, hidden/link/package exclusions, invalid input, stale-file/ancestor checks, explicit start, cancellation and late completion, memory clearing, and preserving previous analysis after failure.

The actual Vision integration and macOS UI tests use synthetic receipt images. They validate execution and text retrieval, **not real-world photo-scene recall or classification accuracy**. Broader photo evaluation remains necessary before claiming Siri-level scene retrieval. UI tests cover analysis, OCR search, reopen/clear/relaunch and rejecting changed results. Light/dark layout is rendered to offscreen windows; no unrelated desktop screenshot is captured.

The SwiftUI, Swift Concurrency and Swift Testing guides informed themed/accessibility-labelled controls, off-main bounded analysis, cancellable task ownership, generation guards, and deterministic tests.

The earlier Vision-only delivery passed **511 tests** on 2026-09-08 (494 unit/integration/presentation + 17 macOS UI tests), result bundle `test_macos_2026-09-08T15-28-56-250Z_pid8580_e54e893e.xcresult`. Natural-description coverage now adds the exact seaside shortcut, real on-device dog/beach interpretation, AND/OR evidence matching, filename/date routing, unsupported-condition refusal, cancellation/opt-out, and Ask AI → approved analysis → description → reopen UI flow. See [Document Questions](DOCUMENT_QUESTIONS.md) for the combined delivery's final validation record.

## Apple APIs

The implementation uses [ClassifyImageRequest](https://developer.apple.com/documentation/vision/classifyimagerequest) and [RecognizeTextRequest](https://developer.apple.com/documentation/vision/recognizetextrequest), with ImageIO downsampling. API signatures/availability were checked against the installed SDK; the app's macOS 26 deployment target was not raised.

## Related tool

[Document Questions](DOCUMENT_QUESTIONS.md) provides bounded local text/PDF extraction, relevant passage retrieval, and on-device answers with inspectable source quotes. Neither tool starts an automatic whole-library scan.
