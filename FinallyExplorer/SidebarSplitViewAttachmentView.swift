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
    private weak var constrainedSidebarView: NSView?
    private var minimumWidthConstraint: NSLayoutConstraint?
    private var maximumWidthConstraint: NSLayoutConstraint?

    var isSidebarVisible = true {
        didSet {
            guard isSidebarVisible != oldValue else { return }
            minimumWidthConstraint?.isActive = isSidebarVisible
            scheduleConfiguration()
        }
    }

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

    override func layout() {
        super.layout()
        scheduleConfiguration()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scheduleConfiguration()
    }

    func scheduleConfiguration() {
        guard window != nil else {
            detach()
            return
        }
        // Layout can call this many times during a divider drag. Coalesce the
        // work instead of continually canceling the task before it can run.
        guard configurationTask == nil else { return }
        configurationTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard Task.isCancelled == false, let self else { return }
            configurationTask = nil
            guard window != nil else { return }
            configureSidebarIfAvailable()
        }
    }

    func detach() {
        configurationTask?.cancel()
        configurationTask = nil
        removeWidthConstraints()
    }

    private func configureSidebarIfAvailable() {
        if let sidebarItem = enclosingSidebarItem {
            // SwiftUI can reapply its split-item settings after initial setup.
            // Only write changed values to avoid triggering a layout loop.
            if sidebarItem.minimumThickness != minimumThickness {
                sidebarItem.minimumThickness = minimumThickness
            }
            if sidebarItem.maximumThickness != maximumThickness {
                sidebarItem.maximumThickness = maximumThickness
            }
            if sidebarItem.canCollapse { sidebarItem.canCollapse = false }
            if sidebarItem.canCollapseFromWindowResize {
                sidebarItem.canCollapseFromWindowResize = false
            }
        }

        guard let (splitView, sidebarView) = enclosingSplitColumn else { return }
        installWidthConstraints(on: sidebarView)

        // Also repair an oversized width restored before the attachment existed.
        guard isSidebarVisible, sidebarView.isHidden == false,
              sidebarView.frame.width > 0,
              let index = splitView.subviews.firstIndex(of: sidebarView) else { return }
        let width = sidebarView.frame.width
        let boundedWidth = min(max(width, minimumThickness), maximumThickness)
        guard abs(width - boundedWidth) > 0.5 else { return }

        if index < splitView.subviews.count - 1 {
            splitView.setPosition(sidebarView.frame.minX + boundedWidth, ofDividerAt: index)
        } else if index > 0 {
            splitView.setPosition(
                sidebarView.frame.maxX - boundedWidth - splitView.dividerThickness,
                ofDividerAt: index - 1
            )
        }
    }

    private func installWidthConstraints(on sidebarView: NSView) {
        guard constrainedSidebarView !== sidebarView else { return }
        removeWidthConstraints()
        constrainedSidebarView = sidebarView

        // The SwiftUI split delegate isn't always an NSSplitViewController.
        // Constrain the actual column, without replacing its native delegate.
        let minimum = sidebarView.widthAnchor.constraint(greaterThanOrEqualToConstant: minimumThickness)
        let maximum = sidebarView.widthAnchor.constraint(lessThanOrEqualToConstant: maximumThickness)
        minimum.identifier = "FinallyExplorer.sidebar.minimumWidth"
        maximum.identifier = "FinallyExplorer.sidebar.maximumWidth"
        minimumWidthConstraint = minimum
        maximumWidthConstraint = maximum
        minimum.isActive = isSidebarVisible
        maximum.isActive = true
    }

    private func removeWidthConstraints() {
        minimumWidthConstraint?.isActive = false
        maximumWidthConstraint?.isActive = false
        minimumWidthConstraint = nil
        maximumWidthConstraint = nil
        constrainedSidebarView = nil
    }

    private var enclosingSplitColumn: (NSSplitView, NSView)? {
        var candidate: NSView = self
        while let parent = candidate.superview {
            if let splitView = parent as? NSSplitView, splitView.isVertical {
                return (splitView, candidate)
            }
            candidate = parent
        }
        return nil
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
