//
//  MouseBackNavigationAttachmentView.swift
//  FinallyExplorer
//

import AppKit

@MainActor
final class MouseBackNavigationAttachmentView: NSView {
    private static let backButtonNumber = 3

    private var navigateBack: () -> Bool
    private var eventMonitor: Any?
    private weak var monitoredWindow: NSWindow?

    init(navigateBack: @escaping () -> Bool) {
        self.navigateBack = navigateBack
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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

    func update(navigateBack: @escaping () -> Bool) {
        self.navigateBack = navigateBack
        installIfNeeded()
    }

    func uninstall() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }

        eventMonitor = nil
        monitoredWindow = nil
    }

    private func installIfNeeded() {
        guard let window else { return }
        guard monitoredWindow !== window || eventMonitor == nil else { return }

        uninstall()
        monitoredWindow = window
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .otherMouseDown
        ) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.buttonNumber == Self.backButtonNumber,
              let monitoredWindow,
              event.window === monitoredWindow,
              monitoredWindow.isKeyWindow,
              monitoredWindow.attachedSheet == nil,
              navigateBack() else {
            return event
        }

        return nil
    }
}
