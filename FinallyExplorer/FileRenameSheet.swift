//
//  FileRenameSheet.swift
//  FinallyExplorer
//

import SwiftUI

struct FileRenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.explorerTheme) private var theme
    @FocusState private var isNameFocused: Bool

    let request: FileRenameRequest
    let coordinator: FileOperationCoordinator

    @State private var name: String
    @State private var nameSelection: TextSelection?
    @State private var smartRenameModel: SmartRenameModel
    @State private var smartRenameAvailability: SmartRenameAvailability?
    @State private var includesFileContents = true

    private let sourceIsDirectory: Bool
    private let sourceIsPackage: Bool
    private let sourceIsRegularFile: Bool
    private let sourceIsSymbolicLink: Bool

    init(
        request: FileRenameRequest,
        coordinator: FileOperationCoordinator,
        smartRenameService: any SmartRenameServicing =
            FoundationModelsSmartRenameService()
    ) {
        self.request = request
        self.coordinator = coordinator
        let itemMetadata = Self.itemMetadata(at: request.sourceURL)
        sourceIsDirectory = itemMetadata.isDirectory
        sourceIsPackage = itemMetadata.isPackage
        sourceIsRegularFile = itemMetadata.isRegularFile
        sourceIsSymbolicLink = itemMetadata.isSymbolicLink
        let originalName = request.originalName
        _name = State(initialValue: originalName)
        _nameSelection = State(initialValue: nil)
        _smartRenameModel = State(
            initialValue: SmartRenameModel(service: smartRenameService)
        )
        _smartRenameAvailability = State(initialValue: nil)
    }

    private var validationMessage: String? {
        FileRenameNameValidator.validationMessage(for: name)
    }

    private var canSubmit: Bool {
        validationMessage == nil
            && (request.isNewFolder || name != request.originalName)
            && coordinator.isPerforming == false
    }

    private var supportsSmartRename: Bool {
        SmartRenameItemEligibility.isEligible(
            isNewFolder: request.isNewFolder,
            isRegularFile: sourceIsRegularFile,
            isSymbolicLink: sourceIsSymbolicLink
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.isNewFolder ? "New Folder" : "Rename Item")
                .font(ExplorerTheme.paneTitleFont)
                .foregroundStyle(theme.textPrimary)

            TextField(
                "Name",
                text: $name,
                selection: $nameSelection
            )
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .onSubmit(submit)
                .accessibilityIdentifier("rename-text-field")

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(theme.accent)
            }

            if supportsSmartRename {
                smartRenameSection
            }

            HStack {
                Spacer()

                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)

                Button(request.isNewFolder ? "Create" : "Rename", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(canSubmit == false)
                    .accessibilityIdentifier("rename-confirm-button")
            }
        }
        .padding(20)
        .frame(width: supportsSmartRename ? 480 : 440)
        .background(theme.elevatedPanel)
        .task {
            isNameFocused = true
            await Task.yield()
            nameSelection = TextSelection(range: name.startIndex..<name.endIndex)
            if supportsSmartRename {
                smartRenameAvailability = await smartRenameModel.availability()
            }
        }
        .onDisappear {
            smartRenameModel.cancelSuggestion()
            coordinator.cancelRename(request)
        }
    }

    private var smartRenameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Smart Rename", systemImage: "sparkles")
                    .font(ExplorerTheme.actionFont)
                    .foregroundStyle(theme.textPrimary)

                Spacer()

                Text("ON-DEVICE")
                    .font(.system(.caption2, design: .rounded).bold())
                    .foregroundStyle(theme.supportAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        theme.supportAccent.opacity(0.14),
                        in: .capsule
                    )
            }

            if smartRenameAvailability == .available {
                Text("Get a concise suggestion without uploading this item. Review it before applying it to the name field.")
                    .font(.callout)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            smartRenameControls

            if let errorMessage = smartRenameModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("smart-rename-error")
            } else if let suggestion = smartRenameModel.suggestion {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        suggestion.contentWasUsed
                            ? "Suggested from local file contents"
                            : "Suggested from the current name",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(theme.supportAccent)

                    HStack(spacing: 10) {
                        Text(suggestion.suggestedName)
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(2)
                            .textSelection(.enabled)

                        Spacer(minLength: 8)

                        Button("Use Suggestion", action: applySmartRenameSuggestion)
                            .buttonStyle(
                                ExplorerPanePrimaryButtonStyle(isCompact: false)
                            )
                            .accessibilityIdentifier("smart-rename-apply-button")
                    }
                }
                .accessibilityIdentifier("smart-rename-result")
            }
        }
        .padding(14)
        .background(theme.control.opacity(0.72), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.divider.opacity(0.8), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var smartRenameControls: some View {
        switch smartRenameAvailability {
        case .available:
            if sourceIsDirectory == false {
                Toggle("Use supported file contents", isOn: $includesFileContents)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.callout)
                    .foregroundStyle(theme.textPrimary)
                    .help("Reads a short local excerpt from supported text, PDF, or image files.")
                    .accessibilityIdentifier("smart-rename-content-toggle")
            }

            HStack(spacing: 10) {
                Button(action: requestSmartRenameSuggestion) {
                    Label(
                        smartRenameModel.isLoading ? "Suggesting…" : "Suggest Name",
                        systemImage: "sparkles"
                    )
                }
                .buttonStyle(ExplorerPanePrimaryButtonStyle(isCompact: false))
                .disabled(smartRenameModel.isLoading)
                .accessibilityIdentifier("smart-rename-suggest-button")

                if smartRenameModel.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(theme.accent)
                        .accessibilityLabel("Creating a name suggestion")
                }

                Spacer()
            }

        case let availability?:
            Label(
                SmartRenameServiceError.unavailable(availability)
                    .localizedDescription,
                systemImage: "info.circle.fill"
            )
            .font(.callout)
            .foregroundStyle(theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("smart-rename-unavailable")

        case nil:
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(theme.accent)

                Text("Checking on-device availability…")
                    .font(.callout)
                    .foregroundStyle(theme.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Checking Smart Rename availability")
        }
    }

    private func submit() {
        guard canSubmit,
              coordinator.commit(request, with: name) else {
            return
        }

        dismiss()
    }

    private func cancel() {
        coordinator.cancelRename(request)
        dismiss()
    }

    private func requestSmartRenameSuggestion() {
        smartRenameModel.generateSuggestion(
            for: SmartRenameRequest(
                itemURL: request.sourceURL,
                isDirectory: sourceIsDirectory,
                isPackage: sourceIsPackage,
                includesContent: includesFileContents
                    && sourceIsDirectory == false
            )
        )
    }

    private func applySmartRenameSuggestion() {
        guard let suggestion = smartRenameModel.suggestion else { return }

        name = suggestion.suggestedName
        smartRenameModel.clear()
        isNameFocused = true
        nameSelection = TextSelection(range: name.startIndex..<name.endIndex)
    }

    private static func itemMetadata(
        at url: URL
    ) -> (
        isDirectory: Bool,
        isPackage: Bool,
        isRegularFile: Bool,
        isSymbolicLink: Bool
    ) {
        let resourceValues = try? url.resourceValues(
            forKeys: [
                .isDirectoryKey,
                .isPackageKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        )
        return (
            resourceValues?.isDirectory ?? url.hasDirectoryPath,
            resourceValues?.isPackage ?? false,
            resourceValues?.isRegularFile ?? false,
            resourceValues?.isSymbolicLink ?? true
        )
    }
}
