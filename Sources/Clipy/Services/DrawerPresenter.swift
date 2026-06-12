import AppKit
import SwiftUI

@MainActor
final class DrawerPresenter {

    private enum DisplayMode { case expanded, minimized }

    private var panel: NSPanel?
    private var contentContainer: ClipyContentContainer?
    private var hostingView: ClipyHostingView?
    private var widgetOverlay: WidgetOverlayView?
    private let contentView: () -> AnyView
    private let settings: UserSettings

    private var displayMode: DisplayMode = .expanded
    private var observersInstalled = false
    private var suppressResignMinimize = false
    private var isPresentingDrawer = false
    private var blockAutoMinimize = false
    private var drawerDragInProgress = false

    private let defaultHeight: CGFloat = 320
    private let pillWidth: CGFloat = 108
    private let pillHeight: CGFloat = 34
    private let edgePadding: CGFloat = 14

    init(settings: UserSettings = .shared, contentView: @escaping () -> AnyView) {
        self.settings = settings
        self.contentView = contentView
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if !isVisible {
            show()
        } else if displayMode == .minimized {
            expand(userInitiated: true)
        } else {
            minimize()
        }
    }

    func show() {
        let panel = makeOrReusePanel()

        if !panel.isVisible {
            panel.orderFront(nil)
            expand(userInitiated: true)
        } else if displayMode == .minimized {
            expand(userInitiated: true)
        } else {
            suppressResignMinimize = true
            isPresentingDrawer = true
            setInteraction(.drawer, on: panel)
            NotificationCenter.default.post(name: .clipyDrawerWillShow, object: nil)
            presentExpanded(panel, userInitiated: true)
            finishPresentingDrawer()
        }
    }

    func hide() {
        suppressResignMinimize = true
        panel?.resignKey()
        panel?.orderOut(nil)
        suppressResignMinimize = false
        displayMode = .expanded
    }

    func minimize() {
        guard let panel, panel.isVisible else { return }
        if displayMode == .minimized {
            NotificationCenter.default.post(name: .clipyDrawerDidMinimize, object: nil)
            return
        }

        displayMode = .minimized
        suppressResignMinimize = true
        NotificationCenter.default.post(name: .clipyDrawerDidMinimize, object: nil)
        setInteraction(.widget, on: panel)
        applyFrame(to: panel, mode: .minimized)
        panel.hasShadow = false
        panel.orderFront(nil)
        panel.resignKey()
        DispatchQueue.main.async { [weak self] in
            self?.suppressResignMinimize = false
        }
    }

    func expand(userInitiated: Bool = true) {
        guard let panel else { return }

        suppressResignMinimize = true
        isPresentingDrawer = true
        displayMode = .expanded

        setInteraction(.drawer, on: panel)
        NotificationCenter.default.post(name: .clipyDrawerDidExpand, object: nil)
        NotificationCenter.default.post(name: .clipyDrawerWillShow, object: nil)
        applyFrame(to: panel, mode: .expanded)
        panel.hasShadow = true
        presentExpanded(panel, userInitiated: userInitiated)
        finishPresentingDrawer()
    }

    private func presentExpanded(_ panel: NSPanel, userInitiated: Bool) {
        if userInitiated {
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    private func finishPresentingDrawer() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isPresentingDrawer = false
                self.suppressResignMinimize = false
            }
        }
    }

    func repositionIfNeeded() {
        guard let panel, panel.isVisible else { return }
        switch displayMode {
        case .expanded:
            applyFrame(to: panel, mode: .expanded)
        case .minimized:
            if settings.hasCustomWidgetPosition, let origin = settings.widgetCustomOrigin {
                let size = minimizedPillSize()
                let clamped = clampOrigin(origin, size: size, on: screenVisibleFrame())
                panel.setFrame(CGRect(origin: clamped, size: size), display: true, animate: false)
            } else {
                applyFrame(to: panel, mode: .minimized)
            }
        }
    }


    private func moveWidget(to origin: CGPoint) {
        guard let panel, displayMode == .minimized else { return }
        let size = panel.frame.size
        let clamped = clampOrigin(origin, size: size, on: screenVisibleFrame())
        panel.setFrame(CGRect(origin: clamped, size: size), display: true, animate: false)
    }

    private func finishWidgetMove() {
        guard let panel, displayMode == .minimized else { return }
        settings.widgetCustomOrigin = panel.frame.origin
    }


    private func makeOrReusePanel() -> NSPanel {
        if let existing = panel { return existing }

        let hosting = ClipyHostingView(rootView: contentView())

        let overlay = WidgetOverlayView(frame: .zero)
        overlay.onClick = { [weak self] in
            MainActor.assumeIsolated { self?.expand(userInitiated: true) }
        }
        overlay.onMove = { [weak self] origin in
            MainActor.assumeIsolated { self?.moveWidget(to: origin) }
        }
        overlay.onMoveEnd = { [weak self] in
            MainActor.assumeIsolated { self?.finishWidgetMove() }
        }

        let container = ClipyContentContainer(hostingView: hosting, widgetOverlay: overlay)

        let newPanel = ClipyPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.titlebarAppearsTransparent = true
        newPanel.titleVisibility = .hidden
        newPanel.hasShadow = true
        newPanel.acceptsMouseMovedEvents = true
        newPanel.contentView = container
        newPanel.isReleasedWhenClosed = false
        newPanel.hidesOnDeactivate = false

        installObservers(for: newPanel)
        self.contentContainer = container
        self.hostingView = hosting
        self.widgetOverlay = overlay
        self.panel = newPanel
        return newPanel
    }

    private enum InteractionMode { case drawer, widget }

    private func setInteraction(_ mode: InteractionMode, on panel: NSPanel) {
        guard let widgetOverlay else { return }

        switch mode {
        case .widget:
            contentContainer?.layoutSubtreeIfNeeded()
            widgetOverlay.isHidden = false
        case .drawer:
            widgetOverlay.isHidden = true
        }

        var mask = panel.styleMask
        switch mode {
        case .drawer:
            mask.remove(.nonactivatingPanel)
        case .widget:
            mask.insert(.nonactivatingPanel)
        }
        panel.styleMask = mask
    }


    private func installObservers(for panel: NSPanel) {
        guard !observersInstalled else { return }
        observersInstalled = true

        NotificationCenter.default.addObserver(
            forName: .closeClipyDrawer, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.hide() }
        }

        NotificationCenter.default.addObserver(
            forName: .minimizeClipyDrawer, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.minimize() }
        }

        NotificationCenter.default.addObserver(
            forName: .clipyDrawerExpand, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let userInitiated = (notification.userInfo?["userInitiated"] as? Bool) ?? true
            MainActor.assumeIsolated { self.expand(userInitiated: userInitiated) }
        }

        NotificationCenter.default.addObserver(
            forName: .clipyDrawerPositionChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.repositionIfNeeded() }
        }

        NotificationCenter.default.addObserver(
            forName: .clipyBlockAutoMinimize, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let blocked = (notification.userInfo?["blocked"] as? Bool) ?? false
            MainActor.assumeIsolated { self.blockAutoMinimize = blocked }
        }

        NotificationCenter.default.addObserver(
            forName: .clipyDrawerDragDidBegin, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.drawerDragInProgress = true }
        }

        NotificationCenter.default.addObserver(
            forName: .clipyDrawerDragDidEnd, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let raw = notification.userInfo?["operation"] as? UInt ?? 0
            MainActor.assumeIsolated {
                self.drawerDragInProgress = false
                let operation = NSDragOperation(rawValue: raw)
                guard operation != [], self.isVisible, self.displayMode == .expanded else { return }
                self.minimize()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.handleDrawerResignedKey() }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard self.isVisible, self.displayMode == .expanded else { return }
                guard !self.shouldBlockAutoMinimize() else { return }
                guard let pid else { return }
                if pid != ProcessInfo.processInfo.processIdentifier {
                    self.minimize()
                }
            }
        }
    }

    private func shouldBlockAutoMinimize() -> Bool {
        if drawerDragInProgress || blockAutoMinimize || suppressResignMinimize || isPresentingDrawer { return true }
        if NSApp.modalWindow != nil { return true }
        guard let panel else { return false }
        return NSApp.windows.contains { window in
            window.isVisible && (window.sheetParent === panel || window.parent === panel)
        }
    }

    private func handleDrawerResignedKey() {
        guard !shouldBlockAutoMinimize() else { return }
        guard isVisible, displayMode == .expanded else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel else { return }
            guard !self.shouldBlockAutoMinimize() else { return }
            guard self.isVisible, self.displayMode == .expanded else { return }
            guard !panel.isKeyWindow else { return }
            self.minimize()
        }
    }


    private func screenVisibleFrame() -> CGRect {
        (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
    }

    private func minimizedPillSize() -> CGSize {
        CGSize(width: pillWidth, height: pillHeight)
    }

    private func defaultMinimizedOrigin(size: CGSize, on sf: CGRect) -> CGPoint {
        let pad = edgePadding
        switch settings.preferredPosition {
        case .bottom:
            return CGPoint(x: sf.minX + pad, y: sf.minY + pad)
        case .top:
            return CGPoint(x: sf.minX + pad, y: sf.maxY - size.height - pad)
        }
    }

    private func clampOrigin(_ origin: CGPoint, size: CGSize, on sf: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, sf.minX), sf.maxX - size.width),
            y: min(max(origin.y, sf.minY), sf.maxY - size.height)
        )
    }

    private func applyFrame(to panel: NSPanel, mode: DisplayMode) {
        let sf = screenVisibleFrame()
        guard sf != .zero else { return }
        let pad = edgePadding
        let position = settings.preferredPosition

        let size: CGSize
        let origin: CGPoint

        switch mode {
        case .expanded:
            size = CGSize(width: sf.width - pad * 2, height: defaultHeight)
            switch position {
            case .top:
                origin = CGPoint(x: sf.midX - size.width / 2, y: sf.maxY - size.height - pad)
            case .bottom:
                origin = CGPoint(x: sf.midX - size.width / 2, y: sf.minY + pad)
            }
        case .minimized:
            size = minimizedPillSize()
            if let custom = settings.widgetCustomOrigin {
                origin = clampOrigin(custom, size: size, on: sf)
            } else {
                origin = defaultMinimizedOrigin(size: size, on: sf)
            }
        }

        panel.setFrame(CGRect(origin: origin, size: size), display: true, animate: false)
    }
}
