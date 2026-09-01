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

    init(
        request: FileRenameRequest,
        coordinator: FileOperationCoordinator
    ) {
        self.request = request
        self.coordinator = coordinator
        let originalName = request.originalName
        _name = State(initialValue: originalName)
        _nameSelection = State(initialValue: nil)
    }

    private var validationMessage: String? {
        FileRenameNameValidator.validationMessage(for: name)
    }

    private var canSubmit: Bool {
        validationMessage == nil
            && (request.isNewFolder || name != request.originalName)
            && coordinator.isPerforming == false
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
        .frame(width: 440)
        .background(theme.elevatedPanel)
        .task {
            isNameFocused = true
            await Task.yield()
            nameSelection = TextSelection(range: name.startIndex..<name.endIndex)
        }
        .onDisappear {
            coordinator.cancelRename(request)
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
}
