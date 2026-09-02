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
    private var consumesBackMouseUp = false

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
        consumesBackMouseUp = false
    }

    private func installIfNeeded() {
        guard let window else { return }
        guard monitoredWindow !== window || eventMonitor == nil else { return }

        uninstall()
        monitoredWindow = window
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.otherMouseDown, .otherMouseUp, .keyDown]
        ) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let monitoredWindow,
              eventBelongsToMonitoredWindow(event, window: monitoredWindow) else {
            return event
        }

        switch event.type {
        case .otherMouseDown:
            guard event.buttonNumber == Self.backButtonNumber,
                  navigateBack() else {
                return event
            }

            consumesBackMouseUp = true
            return nil

        case .otherMouseUp:
            guard event.buttonNumber == Self.backButtonNumber else {
                return event
            }

            if consumesBackMouseUp {
                consumesBackMouseUp = false
                return nil
            }

            // Some mouse drivers emit only the release event for a Back action.
            return navigateBack() ? nil : event

        case .keyDown:
            guard event.isARepeat == false,
                  isBackKeyboardEvent(event),
                  navigateBack() else {
                return event
            }

            // Mouse utilities commonly translate Back to Command-[ or
            // Command-Left Arrow, so accept those standard macOS shortcuts too.
            return nil

        default:
            return event
        }
    }

    private func eventBelongsToMonitoredWindow(
        _ event: NSEvent,
        window: NSWindow
    ) -> Bool {
        guard NSApp.isActive,
              window.attachedSheet == nil else {
            return false
        }

        if event.window === window || event.windowNumber == window.windowNumber {
            return true
        }

        // Events synthesized by mouse utilities can omit their source window.
        return event.window == nil
            && (NSApp.keyWindow === window || window.isKeyWindow || window.isMainWindow)
    }

    private func isBackKeyboardEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
        let disallowedModifiers: NSEvent.ModifierFlags = [.control, .option, .shift]

        guard modifiers.contains(.command),
              modifiers.intersection(disallowedModifiers).isEmpty else {
            return false
        }

        return event.charactersIgnoringModifiers == "[" || event.keyCode == 123
    }
}
