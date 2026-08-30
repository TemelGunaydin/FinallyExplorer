//
//  WindowSidebarTitlebarButton.swift
//  FinallyExplorer
//

import AppKit
import SwiftUI

@MainActor
struct WindowSidebarTitlebarButton: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> WindowReaderView {
        let view = WindowReaderView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.install(in: window)
        }
        return view
    }

    func updateNSView(_ view: WindowReaderView, context: Context) {
        context.coordinator.action = action
        context.coordinator.install(in: view.window)
    }

    static func dismantleNSView(
        _ view: WindowReaderView,
        coordinator: Coordinator
    ) {
        view.onWindowChange = nil
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void

        private weak var installedWindow: NSWindow?
        private var accessoryController: NSTitlebarAccessoryViewController?

        init(action: @escaping () -> Void) {
            self.action = action
        }

        func install(in window: NSWindow?) {
            guard let window else { return }
            guard installedWindow !== window else { return }

            uninstall()

            let symbol = NSImage(
                systemSymbolName: "sidebar.leading",
                accessibilityDescription: "Toggle Sidebar"
            )?.withSymbolConfiguration(
                .init(pointSize: 16, weight: .semibold)
            )
            let button = NSButton(
                image: symbol ?? NSImage(),
                target: self,
                action: #selector(toggleSidebar)
            )
            button.bezelStyle = .shadowlessSquare
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.controlSize = .large
            button.contentTintColor = NSColor.white.withAlphaComponent(0.88)
            button.focusRingType = .none
            button.toolTip = "Show or hide the sidebar"
            button.setAccessibilityIdentifier("window-sidebar-toggle")
            button.setAccessibilityLabel("Toggle Sidebar")
            button.frame = NSRect(x: 4, y: 3, width: 36, height: 32)
            button.wantsLayer = true
            button.layer?.cornerRadius = 10
            button.layer?.backgroundColor = NSColor.white
                .withAlphaComponent(0.10)
                .cgColor
            button.layer?.borderColor = NSColor.white
                .withAlphaComponent(0.13)
                .cgColor
            button.layer?.borderWidth = 0.75

            let container = NSView(frame: NSRect(x: 0, y: 0, width: 44, height: 38))
            container.addSubview(button)

            let accessory = NSTitlebarAccessoryViewController()
            accessory.layoutAttribute = .left
            accessory.view = container
            window.addTitlebarAccessoryViewController(accessory)

            installedWindow = window
            accessoryController = accessory
        }

        func uninstall() {
            guard
                let window = installedWindow,
                let accessoryController,
                let index = window.titlebarAccessoryViewControllers.firstIndex(
                    where: { $0 === accessoryController }
                )
            else {
                installedWindow = nil
                accessoryController = nil
                return
            }

            window.removeTitlebarAccessoryViewController(at: index)
            installedWindow = nil
            self.accessoryController = nil
        }

        @objc private func toggleSidebar() {
            action()
        }
    }
}

final class WindowReaderView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}
