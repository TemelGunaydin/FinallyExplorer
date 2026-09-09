import SwiftUI

struct AskAISearchSheet: View {
    @Environment(\.explorerTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var model: AskAISearchModel
    @Bindable var settings: ExplorerAISettings
    @FocusState private var isInputFocused: Bool
    let rootURL: URL
    let onReveal: (ExplorerSearchResult) -> Void
    var visualSearch: VisualSearchModel? = nil
    var photoRoot: URL? = nil
    var documentQuestions: DocumentQuestionModel? = nil
    var documentSelection: [URL] = []
    @State private var isPhotosPresented = false
    @State private var isDocumentsPresented = false
    @State private var isPhotoConversation = false

    var body: some View {
        VStack(spacing: 16) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if isPhotoConversation, let plan = visualSearch?.naturalPlan {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Photo search context").font(.headline)
                                Text(plan.explanation).font(.callout).lineLimit(2)
                                if plan.filters.summary.isEmpty == false {
                                    Text(plan.filters.summary).font(.callout)
                                }
                                Text("“Only HEIC” or “Yesterday instead” refines these photos. Use New Search to reset the context.")
                                    .font(.caption).foregroundStyle(theme.textSecondary)
                                Button("Return to Photo Results") { presentPhotos("") }
                            }
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.control, in: .rect(cornerRadius: 12))
                        }
                        if model.turns.isEmpty { introduction }
                        ForEach(model.turns) { turn in
                            AskAISearchTurnView(turn: turn)
                        }
                        if let pending = model.pendingRequest {
                            Text(pending)
                                .font(.body.weight(.semibold))
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(theme.accentSoft.opacity(0.4), in: .rect(cornerRadius: 12))
                                .id("pending-request")
                        }
                        if let plan = model.plan {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Current results · \(model.results.count)")
                                    .font(.headline)
                                Text(plan.filterLabels().joined(separator: " · "))
                                    .font(.callout)
                                    .foregroundStyle(theme.textSecondary)
                                    .textSelection(.enabled)
                                    .accessibilityIdentifier("ask-ai-current-filters")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(theme.control, in: .rect(cornerRadius: 12))
                            if model.results.isEmpty {
                                Text("No indexed files match these filters. Try a different date, type, or folder.")
                                    .foregroundStyle(theme.textSecondary)
                                    .padding(.vertical, 16)
                            }
                        }
                        if let message = model.message {
                            Label(message.text, systemImage: message.isError ? "exclamationmark.circle" : "info.circle")
                                .font(.callout)
                                .foregroundStyle(theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("ask-ai-message")
                        }
                        LazyVStack(spacing: 6) {
                            ForEach(model.results) { result in
                                AskAISearchResultRow(result: result) {
                                    onReveal(result)
                                    dismiss()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }
                .onChange(of: model.turns.last?.id) {
                    if let id = model.turns.last?.id { proxy.scrollTo(id, anchor: .top) }
                }
                .onChange(of: model.pendingRequest) {
                    if model.pendingRequest != nil { proxy.scrollTo("pending-request", anchor: .top) }
                }
            }
            Divider().overlay(theme.divider)
            composer
        }
        .padding(22)
        .frame(width: 700, height: 600)
        .foregroundStyle(theme.textPrimary)
        .background(theme.panel)
        .tint(theme.accent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ask-ai-sheet")
        .sheet(isPresented: $isPhotosPresented) {
            if let visualSearch {
                VisualSearchSheet(model: visualSearch, onReveal: { url in
                    onReveal(ExplorerSearchResult(id: url.path, item: FileItem(url: url, isDirectory: false, isImage: true, fileSize: nil, modificationDate: nil),
                        relativePath: url.lastPathComponent, contentMatch: nil))
                    dismiss()
                }, settings: settings)
                .environment(\.explorerTheme, theme)
            }
        }
        .sheet(isPresented: $isDocumentsPresented) {
            if let documentQuestions {
                DocumentQuestionSheet(model: documentQuestions, settings: settings) { url in
                    onReveal(ExplorerSearchResult(id: url.path, item: FileItem(url: url, isDirectory: false, isImage: false, fileSize: nil, modificationDate: nil),
                        relativePath: url.lastPathComponent, contentMatch: nil))
                    dismiss()
                }.environment(\.explorerTheme, theme)
            }
        }
        .task {
            model.setEnabled(settings.isSmartSearchEnabled)
            isInputFocused = true
            await settings.refreshAvailability()
        }
        .onChange(of: settings.isSmartSearchEnabled) {
            model.setEnabled(settings.isSmartSearchEnabled)
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await settings.refreshAvailability() } }
        }
        .onDisappear { model.cancel() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label("Ask AI", systemImage: "sparkles")
                .font(.system(.title2, design: .rounded).weight(.semibold))
            Text("ON-DEVICE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
            Spacer()
            if visualSearch != nil {
                Button("Search Photos", systemImage: "photo.badge.magnifyingglass") { presentPhotos("") }
                    .labelStyle(.iconOnly).buttonStyle(ExplorerPaneUtilityButtonStyle())
                    .help("Describe photos in a chosen folder")
                    .accessibilityIdentifier("ask-ai-photos")
            }
            if let documentQuestions {
                Button("Ask Documents", systemImage: "text.bubble") {
                    model.cancel()
                    if documentSelection.isEmpty == false, Set(documentSelection) != Set(documentQuestions.selection) {
                        documentQuestions.select(documentSelection)
                    }
                    isDocumentsPresented = true
                }
                .labelStyle(.iconOnly).buttonStyle(ExplorerPaneUtilityButtonStyle())
                .help("Ask questions using explicitly selected documents")
                .accessibilityIdentifier("ask-ai-documents")
            }
            Button("New Search") {
                model.startNewSearch()
                visualSearch?.startNewPhotoSearch()
                isPhotoConversation = false
                isInputFocused = true
            }
            .accessibilityIdentifier("ask-ai-new-search")
            SettingsLink { Label("AI Settings", systemImage: "gearshape") }
                .labelStyle(.iconOnly)
                .buttonStyle(ExplorerPaneUtilityButtonStyle())
                .help("Manage on-device AI")
            Button("Close Ask AI", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .buttonStyle(ExplorerPaneUtilityButtonStyle())
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("ask-ai-close")
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Find files, then refine your search.")
                .font(.title3.weight(.semibold))
            Text("Try an example, or describe what you need in English. Follow up with “Only PDFs” or “In Documents instead”.")
                .foregroundStyle(theme.textSecondary)
            ForEach(["PDFs in Downloads from last week", "Photos taken three days ago", "Find the accounting report from two days ago"], id: \.self) { example in
                Button(example, systemImage: "arrow.up.left") {
                    model.draft = example
                    isInputFocused = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.textPrimary)
                .disabled(model.isEnabled == false)
            }
            Text("Search only: no files are changed. File searches use Spotlight. Describe a visual scene to open photo search in a chosen folder, or use the Photos button. Nothing is uploaded; photo analysis requires your approval.")
                .font(.callout)
                .foregroundStyle(theme.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.control, in: .rect(cornerRadius: 14))
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.isEnabled == false {
                Text("Ask AI is off. Enable Ask AI & Smart Search in AI Settings.")
                    .font(.callout)
            } else if let availability = settings.availability, availability != .available {
                Text(SmartSearchError.unavailable(availability).localizedDescription)
                    .font(.callout)
            }
            if let activity = model.activity {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).tint(theme.textPrimary)
                    Text(activity).font(.callout)
                    Spacer()
                    Button("Cancel", action: model.cancel)
                        .accessibilityIdentifier("ask-ai-cancel")
                }
            }
            HStack(spacing: 12) {
                TextField(model.plan == nil ? "Describe the files you want to find…" : "Refine these results…", text: $model.draft)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(12)
                    .background(theme.control, in: .rect(cornerRadius: 10))
                    .focused($isInputFocused)
                    .disabled(model.isEnabled == false)
                    .onSubmit(submit)
                    .accessibilityLabel("Ask AI request")
                    .accessibilityIdentifier("ask-ai-input")
                Button("Search", systemImage: "arrow.up", action: submit)
                    .buttonStyle(ExplorerPanePrimaryButtonStyle(isCompact: false))
                    .disabled(model.canSubmit == false)
                    .accessibilityIdentifier("ask-ai-submit")
            }
        }
    }

    private func submit() {
        if visualSearch != nil, settings.isSmartSearchEnabled,
           VisualDescriptionRouting.isVisualRequest(model.draft)
            || (isPhotoConversation && VisualPhotoRequest.isFollowUp(model.draft)) {
            presentPhotos(model.draft)
        } else {
            isPhotoConversation = false
            model.submit(rootURL: rootURL)
        }
    }

    private func presentPhotos(_ description: String) {
        guard let visualSearch else { return }
        model.cancel()
        isPhotoConversation = true
        if visualSearch.sourceURL == nil, let photoRoot { visualSearch.setSource(photoRoot) }
        visualSearch.naturalDraft = description
        isPhotosPresented = true
        if description.isEmpty == false { visualSearch.findPhotos() }
    }
}
