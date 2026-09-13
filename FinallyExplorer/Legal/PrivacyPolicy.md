Pre-release policy draft — September 13, 2026. Publication and service-provider details are still being finalized.

FinallyExplorer does not upload your files, document excerpts, image analyses, or AI questions to our servers or an external AI API. Some settings and disk catalogs are saved locally. Visiting a hosted website or sending us an email is separate from using the local app.

## 1. Who we are and what this covers

FinallyExplorer is developed by Temel Gunaydin under Build & Runs (“we”, “us”). This policy describes the FinallyExplorer macOS app, its product website, and information you choose to send for support. Contact [support@buildandruns.com](mailto:support@buildandruns.com).

The current app does not require a FinallyExplorer account. It does not include advertising, cross-app tracking, or an analytics or crash-reporting SDK operated by us. We do not sell personal information or use your file contents to train our own models.

## 2. Files, previews and search

FinallyExplorer reads filenames, folder paths, sizes, dates, and other file information to display your workspace, search, compare items, and provide previews. Content search reads eligible file contents. File actions can create, copy, move, rename, compress, hide, or move items to Trash when you request them.

Global name search can use the existing macOS Spotlight index. Fallback and content searches can build a local in-memory file index as needed. The app does not send that search index or your queries to a search server. macOS manages its own Spotlight data separately.

Opening a file with another app or a folder in a terminal passes the selected file or folder to that app at your request. Its handling of the data is governed by its own practices. Files in folders managed by iCloud Drive or another sync provider may be synchronized by that provider independently of FinallyExplorer.

## 3. Image analysis and on-device AI

Ask AI / Smart Search: your request is interpreted on your Mac to form a file search. This interpretation does not send the contents of the search results to the language model.

Visual Search: the folder you choose is analyzed only after you start analysis. Apple Vision produces visual labels and recognized image text locally. Natural descriptions may use Apple’s on-device language model to interpret your request.

Ask Documents: selected documents are read after you choose Read Documents. Bounded text excerpts, OCR text from supported scan pages, questions, and relevant follow-up context are processed locally to produce answers and citations.

Smart Rename: a suggestion is generated only when requested. If use of file contents is enabled, a short supported text/PDF/image excerpt may be included. You can turn that option off and review a suggestion before applying it.

The current implementation uses Apple’s on-device Foundation Models and Vision frameworks, not a third-party cloud AI API. macOS controls Apple Intelligence availability, model preparation, and system services under [Apple’s privacy policy](https://www.apple.com/legal/privacy/). We cannot access your locally processed prompts or documents merely because you use these features.

## 4. What is saved and for how long

Preferences and favorites: settings, favorite locations, sidebar visibility, and terminal preferences are stored locally until you change or remove them. Any saved folder-access permissions are local macOS access records, not copies of the folder contents.

Document and visual-analysis context: analyzed text, labels, questions, and answers remain in the owning Explorer window’s memory. Closing a tool panel alone may preserve this context. Clear forgets it; closing the owning window releases it. Turning off Document Questions also clears that document context.

Offline Catalogs: if you explicitly save a catalog, the app stores a local metadata snapshot containing relative filenames/paths, sizes, dates, folder flags, volume identity, and scan information. It does not store file contents, thumbnails, or AI answers in these catalogs. A catalog remains until you remove or replace it.

Files you create or change: your original files, copies, ZIP archives, and other output remain in their selected locations. Clearing an analysis or removing a catalog does not remove these files. Items moved to Trash remain subject to macOS Trash behavior.

Temporary file-operation data: ZIP creation stages a local copy of the selected item and an archive in the app's temporary storage. The app attempts to remove these working copies when the operation finishes or is cancelled. A crash or cleanup failure can leave temporary data until it is removed by macOS or the user. Compression requires additional free disk space and does not upload these copies.

Removing the app does not necessarily remove its local preferences or support data. macOS backups, swap, filesystem behavior, and synchronized storage are outside the app’s direct control. “Clear” is not a promise of forensic or secure disk erasure.

## 5. Permissions and your choices

macOS may ask for access to protected folders or removable volumes. FinallyExplorer needs access to the files you want to browse or modify; it does not bypass denied permissions. You can review applicable permissions in System Settings and choose which folders or files to work with.

You can disable Smart Search, Document Questions, or Smart Rename in the app’s AI Settings; choose whether rename suggestions use file contents; leave hidden items excluded; cancel an analysis; clear its context; and remove offline catalogs. Ordinary file management does not require enabling Apple Intelligence.

Nearby Transfer is disabled in this release. No nearby discovery or receiving session is started by that feature.

## 6. Website visits and support messages

The product website’s code does not set cookies, use browser storage for tracking, load third-party analytics, or embed external fonts, videos, or advertising. Its layout example is illustrative and cannot read your local files.

When the website is publicly hosted, its hosting infrastructure may process ordinary request information, such as an IP address, requested URL, timestamp, user agent, and error/security logs, to deliver and protect the site. Hosting-provider identity, logging configuration, and retention must be confirmed before publication; the local preview does not make a fixed retention promise.

If you email support, we receive the email address, message, and any attachments or diagnostic information you voluntarily provide. We use this to answer your request, troubleshoot the issue, and maintain necessary support records. Do not send private documents, credentials, or screenshots containing sensitive information unless needed; redact them first.

Support correspondence is retained only as reasonably needed to handle the request, related follow-ups, security, and applicable legal obligations. You can request deletion; we will explain any records that must be retained. Our email provider processes messages to deliver this correspondence.

## 7. Sharing, service providers and security

We do not sell personal information or share it for targeted advertising. Local app content is not transmitted to us. Information from website delivery or support may be handled by the hosting and email providers needed for those services, or disclosed when legally required or reasonably necessary to protect rights and security.

Where providers process information on our behalf, we are responsible for using appropriate contractual and security safeguards. Provider selection, processing locations, and any required international-transfer safeguards must be confirmed for the production website before it is published.

We use platform protections and limited access appropriate to the feature. No software or storage system can guarantee absolute security. Keep macOS updated and maintain backups of important files.

## 8. Your privacy rights

Depending on applicable law, you may have rights to access, correct, delete, or obtain a copy of personal information we hold; object to or restrict processing; withdraw consent where processing relies on consent; and raise a concern with a relevant supervisory authority.

Email [support@buildandruns.com](mailto:support@buildandruns.com) to make a request. We may ask for the minimum information needed to verify and answer it. We do not need your documents to delete a support email, and we cannot remotely inspect or erase data that exists only on your Mac.

The product is not directed specifically to children. If you believe a child has sent personal information to us through support, contact us so we can review and address it.

## 9. Updates and contact

We will update this policy when relevant practices change and identify the revised date. Material changes should be communicated before new processing begins where required.

Temel Gunaydin · Build & Runs
[support@buildandruns.com](mailto:support@buildandruns.com)
