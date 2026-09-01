//
//  SidebarSplitViewAttachmentView.swift
//  FinallyExplorer
//

import AppKit

@MainActor
final class SidebarSplitViewAttachmentView: NSView {
    private let minimumThickness: CGFloat
    private let maximumThickness: CGFloat
    private var configurationTask: Task<Void, Never>?

    init(minimumThickness: CGFloat, maximumThickness: CGFloat) {
        self.minimumThickness = minimumThickness
        self.maximumThickness = maximumThickness
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        .zero
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scheduleConfiguration()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleConfiguration()
    }

    func scheduleConfiguration() {
        configurationTask?.cancel()
        configurationTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard Task.isCancelled == false else { return }
            self?.configureSidebarItemIfAvailable()
        }
    }

    private func configureSidebarItemIfAvailable() {
        guard let sidebarItem = enclosingSidebarItem else { return }

        sidebarItem.minimumThickness = minimumThickness
        sidebarItem.maximumThickness = maximumThickness
        sidebarItem.canCollapse = false
        sidebarItem.canCollapseFromWindowResize = false
    }

    private var enclosingSidebarItem: NSSplitViewItem? {
        var responder: NSResponder? = self

        while let currentResponder = responder {
            if let controller = currentResponder as? NSSplitViewController,
               let item = sidebarItem(in: controller) {
                return item
            }
            responder = currentResponder.nextResponder
        }

        var candidate: NSView? = self

        while let view = candidate {
            if let splitView = view as? NSSplitView,
               let controller = splitView.delegate as? NSSplitViewController,
               let item = sidebarItem(in: controller) {
                return item
            }
            candidate = view.superview
        }

        if let rootController = window?.contentViewController {
            for controller in splitViewControllers(in: rootController) {
                if let item = sidebarItem(in: controller) {
                    return item
                }
            }
        }

        return nil
    }

    private func splitViewControllers(
        in rootController: NSViewController
    ) -> [NSSplitViewController] {
        var controllers: [NSSplitViewController] = []

        func collect(from controller: NSViewController) {
            if let splitController = controller as? NSSplitViewController {
                controllers.append(splitController)
            }
            for child in controller.children {
                collect(from: child)
            }
        }

        collect(from: rootController)
        return controllers
    }

    private func sidebarItem(
        in controller: NSSplitViewController
    ) -> NSSplitViewItem? {
        controller.splitViewItems.first { item in
            isContained(in: item.viewController.view)
        }
    }

    private func isContained(in rootView: NSView) -> Bool {
        var candidate: NSView? = self

        while let view = candidate {
            if view === rootView { return true }
            candidate = view.superview
        }

        return false
    }
}
