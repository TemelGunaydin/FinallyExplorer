import AppKit

/// Handles navigation only while this menu is visible in the active window.
@MainActor
final class ExplorerToolsKeyboardAttachmentView: NSView {
    enum Command: Equatable { case move(Int), activate, close }

    private var onMove: (Int) -> Void
    private var onActivate: () -> Void
    private var onClose: () -> Void
    private var eventMonitor: Any?
    private weak var monitoredWindow: NSWindow?
    private weak var ownerWindow: NSWindow?
    var isMonitoring: Bool { eventMonitor != nil }

    init(onMove: @escaping (Int) -> Void, onActivate: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onMove = onMove
        self.onActivate = onActivate
        self.onClose = onClose
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { .zero }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installIfNeeded()
    }

    func update(onMove: @escaping (Int) -> Void, onActivate: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onMove = onMove
        self.onActivate = onActivate
        self.onClose = onClose
        installIfNeeded()
    }

    func uninstall() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        monitoredWindow = nil
        ownerWindow = nil
    }

    isolated deinit { uninstall() }

    private func installIfNeeded() {
        guard let window else { uninstall(); return }
        guard monitoredWindow !== window || eventMonitor == nil else { return }
        uninstall()
        monitoredWindow = window
        // Toolbar popovers can leave their presenting window as the key window.
        // Capture that owner now, never whichever window becomes main later.
        ownerWindow = window.parent ?? (NSApp.mainWindow === window ? nil : NSApp.mainWindow)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // AppKit documents local event callbacks as main-thread callbacks.
            let handled = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.handle(event)
            }
            return handled ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let window = monitoredWindow, window.isVisible, NSApp.isActive,
              Self.targetsMenu(eventWindow: event.window, keyWindow: NSApp.keyWindow, menu: window, owner: ownerWindow),
              let command = Self.command(for: event) else { return false }
        switch command {
        case .move(let offset): onMove(offset)
        case .activate:
            guard event.isARepeat == false else { return true }
            uninstall()
            onActivate()
        case .close:
            uninstall()
            onClose()
        }
        return true
    }

    static func targetsMenu(eventWindow: NSWindow?, keyWindow: NSWindow?, menu: NSWindow, owner: NSWindow?) -> Bool {
        guard let keyWindow, keyWindow === menu || keyWindow === owner else { return false }
        return eventWindow == nil || eventWindow === menu || eventWindow === owner
    }

    static func command(for event: NSEvent) -> Command? {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return nil }
        if event.keyCode == 48 { return .move(event.modifierFlags.contains(.shift) ? -1 : 1) }
        guard event.modifierFlags.contains(.shift) == false else { return nil }
        switch event.keyCode {
        case 125: return .move(1)
        case 126: return .move(-1)
        case 36, 76, 49: return .activate
        case 53: return .close
        default: return nil
        }
    }
}
