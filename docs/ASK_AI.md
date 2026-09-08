# Ask AI — first delivery

## Available now

- The toolbar's **Ask AI** button opens a separate, themed search conversation. Existing FFF name search and grep/content search remain independent.
- Submit an English description, inspect the displayed filters, and reveal a result in the active Explorer pane.
- Follow-ups preserve the last successful plan. Exact shortcuts such as `Only PDFs`, `Only HEIC`, `In Documents instead`, and `Last week instead` are handled deterministically, without another inference. Other descriptions use Apple's on-device model.
- `New Search` clears the context. Closing cancels pending work. Disabling **Ask AI & Smart Search** in AI Settings clears the conversation when the panel observes the setting.
- Recent conversation history is bounded to 12 completed requests and held only in window memory. No chat database or cloud API is added.

## Correctness and privacy boundaries

The model produces a constrained filter schema, never executable code, shell commands, arbitrary paths, or file operations. Only the user's description and bounded previous filters enter its context; search result names and file contents do not. Calendar code resolves relative dates; follow-ups preserve the resolved interval unless the date filter changes.

Every request is cancellable, and generation checks reject late completions. A failed follow-up retains the previous successful results with an explicit notice. Interpretation can still be imperfect: visible filter labels let the user inspect the actual search, rather than presenting model prose as proof of a match.

Photo capture dates are separate from filesystem creation/modification dates. Spotlight's indexed content-creation date supplies candidates, then ImageIO reads original EXIF `DateTimeOriginal` and optional `OffsetTimeOriginal`. Only EXIF dates inside the half-open requested interval are returned. Unknown/unreadable metadata is skipped; a missing timezone is explicitly identified as an assumption using the Mac's timezone. Cloud placeholders are not intentionally downloaded for verification.

This is **not a complete photo-library search**. It cannot find Photos-library-only or unindexed assets, and incorrect/missing Spotlight content dates can omit otherwise valid images. Searches remain bounded to the existing Spotlight candidate limit and 120 displayed results. There is no new full-disk scan.

Visual scene/person recognition, document Q&A, download/import dates, size/exclusion filters, and file-changing commands are not implemented in this delivery. Common unsupported requests are rejected before inference; image-topic requests require an explicit filename query rather than masquerading as visual search.

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

## Next deliveries (not implemented here)

1. An offline catalog for disconnected drives.
2. Visual search / richer document questions with a separately scoped local index and explicit permission boundaries.
