# Ask AI — file search and explicit local tools

## Available now

- The toolbar's **Ask AI** button opens a separate, themed search conversation. Existing FFF name search and grep/content search remain independent.
- Submit an English description, inspect the displayed filters, and reveal a result in the active Explorer pane.
- Follow-ups preserve the last successful plan. Exact shortcuts such as `Only PDFs`, `Only HEIC`, `In Documents instead`, and `Last week instead` are handled deterministically, without another inference. Other descriptions use Apple's on-device model.
- `New Search` clears the context. Closing cancels pending work. Disabling **Ask AI & Smart Search** in AI Settings clears the conversation when the panel observes the setting.
- Recent conversation history is bounded to 12 completed requests and held only in window memory. No chat database or cloud API is added.
- English scene requests such as `Find photos taken by the sea` open [Visual Search](VISUAL_SEARCH.md), carrying the description. Its first folder analysis still requires explicit approval. The **Search Photos** button opens the same tool directly.
- **Ask Documents** opens [Document Questions](DOCUMENT_QUESTIONS.md) with the active file selection. Select **Read Documents** before asking. This is a separate, source-cited Q&A tool; document contents do not enter the Spotlight search conversation.

## Correctness and privacy boundaries

The model produces a constrained filter schema, never executable code, shell commands, arbitrary paths, or file operations. Only the user's description and bounded previous filters enter its context; search result names and file contents do not. Calendar code resolves relative dates; follow-ups preserve the resolved interval unless the date filter changes.

Every request is cancellable, and generation checks reject late completions. A failed follow-up retains the previous successful results with an explicit notice. Interpretation can still be imperfect: visible filter labels let the user inspect the actual search, rather than presenting model prose as proof of a match.

Photo capture dates are separate from filesystem creation/modification dates. Spotlight's indexed content-creation date supplies candidates, then ImageIO reads original EXIF `DateTimeOriginal` and optional `OffsetTimeOriginal`. Only EXIF dates inside the half-open requested interval are returned. Unknown/unreadable metadata is skipped; a missing timezone is explicitly identified as an assumption using the Mac's timezone. Cloud placeholders are not intentionally downloaded for verification.

This is **not a complete photo-library search**. It cannot find Photos-library-only or unindexed assets, and incorrect/missing Spotlight content dates can omit otherwise valid images. Searches remain bounded to the existing Spotlight candidate limit and 120 displayed results. There is no new full-disk scan.

Scene requests are routed to the separately scoped Visual Search tool before the normal file-search interpreter runs. Explicit filename searches and date-only photo searches stay in the original conversation. Visual Search now combines a scene with EXIF capture dates and supported image extensions: `Find beach photos from last week` → `Only HEIC`. These explicit follow-ups also reopen the active photo context from Ask AI. A full photo request starts its own filters; it does not inherit earlier Spotlight conditions. Use **New Search** to clear both contexts. See [supported photo clauses and limitations](VISUAL_SEARCH.md#capture-dates-image-types-and-follow-ups). There is no person identification, arbitrary Photos-library access, download/import-date filtering, or file-changing command execution. Unsupported conditions are rejected rather than deliberately weakened. Inspect visible filters and visual evidence because model interpretations and classifier labels can still be imperfect.

Document Questions has independent selection, permission, context, and memory. Follow-ups can refer to the last two successful document questions and their verified source quotes. The visible self-contained interpretation drives fresh hybrid keyword/semantic retrieval over the explicitly read selection. **New Conversation** resets this context without rereading; **Clear** also forgets the documents and in-memory vectors. It does not claim full-document comprehension.

## Validation

Use XcodeBuildMCP's macOS build/test workflow. Regression suites cover:

- Explicit submission, conversation state, cancellation, reset, opt-out, and late results.
- Filter merges, exact shortcuts, calendar boundaries, extension validation, native Spotlight predicates, and symlink scope checks.
- Real JPEG EXIF metadata, malformed dates/offsets, and missing capture metadata.
- Apple's installed model for initial descriptions and a non-shortcut follow-up (conditional on availability).
- Off-screen light/dark sheet layout without bringing a window forward.
- A macOS UI test for opening the panel, explicit submission controls, clearing, closing, and returning to normal search. Interactive execution requires desktop focus/automation permission.

The SwiftUI, Swift Concurrency, and Swift Testing guides informed the themed/accessibility-labelled panel, off-main metadata reads, cancellation/generation guards, injected test doubles, and explicit task-completion assertions.

## Related tools — second delivery

[Compare Folders & Verified Copy](FOLDER_COMPARISON.md) is now available as a separate toolbar tool. It compares regular file data between open panes and adds missing items only after review and confirmation. It does not require AI, and Ask AI cannot invoke file-changing commands.

## Related tools — third delivery

Exact duplicates and read-only organization previews were introduced through [Local File Tools](FILE_TOOLS.md). Duplicate removal requires manual selection and a separate confirmation. The next delivery below adds reviewed organization moves.

## Related tools — fourth delivery

**Organize Folder** now applies a reviewed plan only after a separate **Move Files** confirmation. Immediate files move into file-type or modification-month subfolders on the same disk, with fresh change/collision checks and no overwrites. Cancellation reports partial completion; completed moves remain in place. The preview is still read-only, and Ask AI cannot execute these operations. See [Local File Tools](FILE_TOOLS.md) for exclusions and safety limits.

## Related tools — fifth delivery

[Offline Catalogs](OFFLINE_CATALOGS.md) keeps explicit metadata snapshots of selected external disk folders searchable when the disk is disconnected. It has its own name/path, extension, size and modification-date filters; normal FFF/grep and Ask AI remain unchanged. No file contents are copied or sent to a model.

## Related tools — sixth delivery

[Visual Search](VISUAL_SEARCH.md) analyzes up to 300 supported still images in an explicitly chosen local folder using Vision classification and English OCR. It searches observed evidence rather than filenames and shows why each result matched. Analysis is opt-in and memory-only, with cancel/clear controls and no startup scan.

## Related tools — seventh delivery

Natural photo descriptions now open Visual Search from Ask AI, with visible concepts and observed-label matches. [Document Questions](DOCUMENT_QUESTIONS.md) now answers specific questions over up to five explicitly selected documents with verified source quotes and PDF page references. Neither tool adds a cloud API, automatic scan, or file-changing AI command. Offline Catalogs remains metadata-only.

## Related tools — eighth delivery

Photo scenes now combine with EXIF capture dates and image types, with exact follow-ups that retain the scene and unchanged filters. Real-photo, real-model and full interaction regressions accompany the change. The [validation record](DOCUMENT_QUESTIONS.md#september-9-accuracy-and-interaction-regressions) includes the right-click Rename and Cmd+A fixes found along the way.

Document follow-up questions and local hybrid keyword/semantic passage retrieval are now implemented; see [Document Questions](DOCUMENT_QUESTIONS.md) for bounds and validation. Scanned-PDF OCR and an optional persistent visual index remain future work.
