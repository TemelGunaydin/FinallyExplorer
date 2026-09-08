# Ask Documents — source-cited, on-device questions

## How to use

1. Select documents in an Explorer pane, then choose **File Tools → Ask Documents…**, or open **Ask AI → Ask Documents**. **Choose Documents…** also opens a native file picker.
2. Review the filenames and select **Read Documents**. Selecting files or opening the tool does not read their contents.
3. Ask a specific English question, such as `What is the payment deadline?` or `What is the invoice total?`.
4. Each answer statement includes a supporting quote and a source button. Click it to inspect the retrieved source text and its filename/PDF page, or reveal the file in Explorer.

Only the explicit selection is used. A different nonempty Explorer selection replaces the previous document context when opening the tool and requires reading again. An empty selection allows the previous in-memory context to be reopened. Questions are independent: name the subject instead of relying on pronouns such as `it`. This is not general chat or a whole-document summarizer.

## Supported inputs and retrieval limits

- **1–5** local PDF, TXT, MD, JSON or CSV files. Text formats must be valid UTF-8 without NUL bytes. No recursive folder reads, network volumes, file symlinks or cloud placeholders.
- At most **20 MB**, **100 PDF pages**, and **200,000 extracted text characters per file**, with **300,000 characters total**. Limit violations fail explicitly; the tool does not silently truncate a selected document or omit a failed selection.
- PDFKit extracts existing text; image-only/scanned PDFs need OCR elsewhere first. Textless PDF pages are counted and disclosed. Locked/malformed PDFs fail with an explanation.
- Page-preserving chunks are up to 900 characters with 100-character overlap. Retrieval ranks English word overlap with the question and keeps up to four relevant excerpts, each bounded to **600 UTF-8 bytes**. Filenames are not supporting evidence.
- Questions are at most 500 characters / 1,000 UTF-8 bytes. Model output is constrained to at most three source-cited claims. Inference has a 30-second cancellation deadline; no overlapping request starts while cancellation unwinds.

This initial retrieval is **lexical, not embeddings-based semantic search**. Synonyms/paraphrases can miss relevant material, and the selected excerpts need not represent every part of every document. Absence of a retrieved answer is not proof the complete documents lack the information. No cross-file totals, comparisons or conclusions are intentionally inferred beyond the excerpts.

## Source validation and safety

The model receives only the question and numbered source excerpts — no filenames or filesystem paths. The app maps IDs back to the selected documents. Every cited source ID must exist, and every normalized quote must be a contiguous substring of its retrieved source. Unknown IDs, fabricated/paraphrased quotes, empty claims or insufficient evidence reject the answer. No unverified new answer is shown; a previous verified answer can remain under its original question. Retrieved passages identify the question they belong to.

**An existing quote does not prove the model's statement logically follows from it.** The UI explicitly asks users to check the supporting quotes. This is not a guarantee of factual correctness or a substitute for reviewing important documents.

Question/document strings are untrusted data in a bounded prompt, never trusted instructions. The session has no tools, shell execution, file-operation capability or cloud fallback. This follows Apple's guidance on separating untrusted input and validating output in [Improving the safety of generative model output](https://developer.apple.com/documentation/FoundationModels/improving-the-safety-of-generative-model-output). The small excerpt budget and fresh per-question session account for the shared instructions/input/output context described in [TN3193: Managing the on-device foundation model’s context window](https://developer.apple.com/documentation/Technotes/tn3193-managing-the-on-device-foundation-model-s-context-window); a context/model error is surfaced, not answered from external knowledge.

Files are read off the main actor with descriptor-relative, no-follow, bounded reads, not memory mapping. Identity/change tokens are checked around reads, before answering, after model generation and before revealing a source. Changed, removed or link-swapped sources invalidate the prepared documents/answers and require another read. This is a read-only freshness check, not a lock preventing later changes by another app.

## Availability, controls and privacy

- Requires an Apple Intelligence-capable Mac with Apple's on-device model ready. No API key, Gemini/Qwen download, server integration or separately purchased model is required. This uses `SystemLanguageModel(useCase: .general)`, not a cloud model.
- **AI Settings → Enable Document Questions** is independent of Smart Rename and Ask AI/Smart Search. Disabling it cancels work and clears prepared documents/answers, even if the tool is closed.
- Source text, retrieved passages, questions and answers live only in the current Explorer window's memory. There is no new content index, chat database or app-created disk cache. No startup analysis occurs.
- Closing the panel cancels work and preserves completed context for reopening. **Clear**, changing the selection, disabling Document Questions, or closing the Explorer window forgets the prepared/displayed context. Pending completion cannot repopulate cleared data; temporary inputs of an in-flight read/model request can remain until cancellation unwinds. This is not a secure-memory-erasure guarantee, and ordinary system memory management is outside this app-level lifetime guarantee.
- Existing FFF/grep, Spotlight search, rename, copy/paste, grid, USB, comparison, duplicates, organization and offline catalogs retain their own workflows. AI cannot execute file-changing operations from a document answer.

## Validation

XcodeBuildMCP is used for builds and tests. Tests include synthetic real PDF page extraction and actual on-device answer generation, missing-fact handling, forged quote/ID rejection, byte/page/total-text limits, malformed input and symlinks, source mutation during inference/reveal, explicit read approval, selection changes, cancellation, opt-out and late completion. The macOS UI scenario reads a synthetic selected document, asks a real on-device question, opens its citation and clears the context while checking the original file is unchanged.

Light/dark document-answer, citation, photo-description and AI-settings layouts are rendered into offscreen windows. No unrelated desktop screenshots are captured. SwiftUI, Swift Concurrency and Swift Testing guidance informed accessibility-labelled themed controls, off-main bounded work, cancellation ownership and deterministic gate-based tests.

Validated on 2026-09-08 using XcodeBuildMCP: **521 unit/integration/presentation tests and 21 distinct selected macOS UI scenarios passed across the final regression batches**. Actual on-device integration tests ran; none were skipped. Coverage includes normal name/content search, copy/paste, rename, New Folder cancellation, grid reset, USB listing/eject, comparison, duplicates, organization, offline catalogs, visual analysis, natural photo routing, source-cited answers and AI preference persistence.

- Broad regression: **540 passed, 0 failures/skips** (521 + 19 UI), bundle `test_macos_2026-09-08T16-30-05-294Z_pid48916_00aef492.xcresult`.
- Final production-code recheck after error-copy, citation-contrast and accessibility polish: all **521 unit tests**, both feature UI flows and document opt-out passed, bundle `test_macos_2026-09-08T16-38-25-058Z_pid53163_a2c6c203.xcresult`. An older Smart Rename preference test did not reach the Rename sheet through its context-menu click after the Settings-window focus transition. Its setting/persistence assertions were retained and the entry path changed to the already-tested native **File → Rename** command; this is not a claim that the original right-click attempt passed.
- Final preference recheck: **2 passed, 0 failures/skips** (Smart Rename persistence + document opt-out while closed/relaunch), bundle `test_macos_2026-09-08T16-43-06-826Z_pid55502_dd07e3d1.xcresult`.

The photo tests verify the actual model's concept interpretation and synthetic Vision/OCR execution; they do not establish real-world scene recall or Siri parity. Document tests establish extraction, citation existence and lifecycle behavior, not universal semantic correctness of generated statements.
