import AppKit
import SwiftUI

final class CopyDockPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class CopyDockHostingView: NSHostingView<AnyView> {
    override func makeBackingLayer() -> CALayer {
        let layer = super.makeBackingLayer()
        layer.backgroundColor = CGColor(gray: 0, alpha: 0)
        layer.isOpaque = false
        return layer
    }

    override var isOpaque: Bool { false }
}

final class CopyDockContentContainer: NSView {
    let hostingView: CopyDockHostingView
    let widgetOverlay: WidgetOverlayView

    init(hostingView: CopyDockHostingView, widgetOverlay: WidgetOverlayView) {
        self.hostingView = hostingView
        self.widgetOverlay = widgetOverlay
        super.init(frame: .zero)

        hostingView.autoresizingMask = [.width, .height]
        widgetOverlay.autoresizingMask = [.width, .height]
        widgetOverlay.isHidden = true

        addSubview(hostingView)
        addSubview(widgetOverlay)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        hostingView.frame = bounds
        widgetOverlay.frame = bounds
    }
}

final class WidgetOverlayView: NSView {
    var onClick: (() -> Void)?
    var onMove: ((CGPoint) -> Void)?
    var onMoveEnd: (() -> Void)?

    private var pressDate: Date?
    private var pressOrigin: CGPoint?
    private var pressMouseLocation: NSPoint?
    private var isDragging = false
    private let holdDuration: TimeInterval = 0.35

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressDate = Date()
        pressOrigin = window?.frame.origin
        pressMouseLocation = NSEvent.mouseLocation
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pressDate, let origin = pressOrigin, let start = pressMouseLocation else { return }
        guard Date().timeIntervalSince(pressDate) >= holdDuration else { return }
        isDragging = true
        let current = NSEvent.mouseLocation
        onMove?(CGPoint(x: origin.x + (current.x - start.x), y: origin.y + (current.y - start.y)))
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            onMoveEnd?()
        } else if let pressDate, Date().timeIntervalSince(pressDate) < holdDuration {
            onClick?()
        }
        pressDate = nil
        pressOrigin = nil
        pressMouseLocation = nil
        isDragging = false
    }
}
