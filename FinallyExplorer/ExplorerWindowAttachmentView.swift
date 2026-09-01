//
//  ExplorerWindowAttachmentView.swift
//  FinallyExplorer
//

import AppKit
import SwiftUI

@MainActor
final class ExplorerWindowAttachmentView: NSView {
    private weak var configuredWindow: NSWindow?
    private var accessoryController: NSTitlebarAccessoryViewController?
    private var nativeControlVisibility: (close: Bool, minimize: Bool, zoom: Bool)?

    override var intrinsicContentSize: NSSize {
        .zero
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            uninstall()
        } else {
            installIfNeeded()
        }
    }

    func installIfNeeded() {
        guard let window else { return }
        guard configuredWindow !== window || accessoryController == nil else {
            hideNativeControls(in: window)
            return
        }

        uninstall()

        guard let closeButton = window.standardWindowButton(.closeButton),
              let minimizeButton = window.standardWindowButton(.miniaturizeButton),
              let zoomButton = window.standardWindowButton(.zoomButton) else {
            return
        }

        nativeControlVisibility = (
            close: closeButton.isHidden,
            minimize: minimizeButton.isHidden,
            zoom: zoomButton.isHidden
        )

        let controls = ExplorerTrafficLightControls(
            closeWindow: { [weak window] in
                window?.performClose(nil)
            },
            minimizeWindow: { [weak window] in
                window?.performMiniaturize(nil)
            },
            toggleFullScreen: { [weak window] in
                guard let window else { return }
                if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                    window.performZoom(nil)
                } else {
                    window.toggleFullScreen(nil)
                }
            }
        )
        let hostingView = NSHostingView(rootView: controls)
        hostingView.frame = NSRect(x: 0, y: 0, width: 104, height: 36)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let accessoryController = NSTitlebarAccessoryViewController()
        accessoryController.layoutAttribute = .left
        accessoryController.view = hostingView
        window.addTitlebarAccessoryViewController(accessoryController)

        configuredWindow = window
        self.accessoryController = accessoryController
        hideNativeControls(in: window)
    }

    func uninstall() {
        if let configuredWindow,
           let accessoryController,
           let index = configuredWindow.titlebarAccessoryViewControllers
            .firstIndex(where: { $0 === accessoryController }) {
            configuredWindow.removeTitlebarAccessoryViewController(at: index)
        }

        if let configuredWindow, let nativeControlVisibility {
            configuredWindow.standardWindowButton(.closeButton)?.isHidden =
                nativeControlVisibility.close
            configuredWindow.standardWindowButton(.miniaturizeButton)?.isHidden =
                nativeControlVisibility.minimize
            configuredWindow.standardWindowButton(.zoomButton)?.isHidden =
                nativeControlVisibility.zoom
        }
        accessoryController = nil
        nativeControlVisibility = nil
        configuredWindow = nil
    }

    private func hideNativeControls(in window: NSWindow) {
        setNativeControlsHidden(true, in: window)
    }

    private func setNativeControlsHidden(_ isHidden: Bool, in window: NSWindow) {
        window.standardWindowButton(.closeButton)?.isHidden = isHidden
        window.standardWindowButton(.miniaturizeButton)?.isHidden = isHidden
        window.standardWindowButton(.zoomButton)?.isHidden = isHidden
    }
}
