//
//  TerminalToolbarButton.swift
//  FinallyExplorer
//

import SwiftUI

struct TerminalToolbarButton: View {
    @Environment(TerminalApplicationCoordinator.self) private var coordinator

    let directoryURL: URL?

    @State private var isChooserPresented = false

    var body: some View {
        Button("Open in Terminal", systemImage: "terminal") {
            openOrChooseTerminal()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(ExplorerPaneUtilityButtonStyle())
        .disabled(
            directoryURL == nil
                || coordinator.installedApplications.isEmpty
                || coordinator.isOpening
        )
        .help(helpText)
        .accessibilityIdentifier("pane-terminal-button")
        .contextMenu {
            Button("Choose Terminal…", systemImage: "terminal") {
                isChooserPresented = true
            }
            .disabled(coordinator.installedApplications.isEmpty)

            if coordinator.preferredApplicationID != nil {
                Button("Ask Every Time", systemImage: "arrow.counterclockwise") {
                    coordinator.forgetPreferredApplication()
                }
            }
        }
        .popover(isPresented: $isChooserPresented, arrowEdge: .bottom) {
            TerminalChooserPopover(
                directoryURL: directoryURL,
                coordinator: coordinator,
                dismiss: dismissChooser
            )
        }
    }

    private var helpText: String {
        if let preferredApplication = coordinator.preferredApplication {
            return "Open this folder in \(preferredApplication.name)"
        }
        if coordinator.installedApplications.isEmpty {
            return "No terminal application was found"
        }
        return "Choose a terminal for this folder"
    }

    private func openOrChooseTerminal() {
        guard let directoryURL else { return }

        if coordinator.preferredApplication != nil {
            coordinator.openPreferred(directoryURL)
        } else {
            isChooserPresented = true
        }
    }

    private func dismissChooser() {
        isChooserPresented = false
    }
}

private struct TerminalChooserPopover: View {
    @Environment(\.explorerTheme) private var theme

    let directoryURL: URL?
    let coordinator: TerminalApplicationCoordinator
    let dismiss: () -> Void

    @State private var remembersSelection = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Open in Terminal")
                .font(ExplorerTheme.paneTitleFont)
                .foregroundStyle(theme.textPrimary)

            Text("Choose an installed terminal for this folder.")
                .font(.callout)
                .foregroundStyle(theme.textSecondary)

            VStack(spacing: 6) {
                ForEach(coordinator.installedApplications) { application in
                    Button {
                        open(in: application)
                    } label: {
                        Label(application.name, systemImage: "terminal.fill")
                            .font(ExplorerTheme.actionFont)
                            .foregroundStyle(theme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .frame(height: 38)
                            .background(theme.control, in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("terminal-choice-\(application.id)")
                }
            }

            Toggle("Always use the selected terminal", isOn: $remembersSelection)
                .toggleStyle(.checkbox)
                .foregroundStyle(theme.textSecondary)
                .accessibilityIdentifier("remember-terminal-choice")

            if coordinator.preferredApplicationID != nil {
                Button("Ask Every Time", systemImage: "arrow.counterclockwise") {
                    coordinator.forgetPreferredApplication()
                    remembersSelection = false
                }
                .buttonStyle(.link)
            }
        }
        .padding(14)
        .frame(width: 310)
        .background(theme.elevatedPanel)
        .onAppear {
            remembersSelection = coordinator.preferredApplicationID != nil
        }
    }

    private func open(in application: TerminalApplication) {
        guard let directoryURL else { return }
        if remembersSelection {
            coordinator.remember(application)
        }
        coordinator.open(directoryURL, in: application)
        dismiss()
    }
}
