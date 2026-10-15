import AppKit

/// The strip along the Windows taskbar's top edge. Dragging it resizes the
/// bar, the way dragging the Dock's divider resizes the Dock.
final class WindowsTaskbarResizeHandle: NSView {
    private struct Drag {
        let startY: CGFloat
        let startHeight: CGFloat
        let interaction: UUID?
    }

    private var tracking: NSTrackingArea?
    private var drag: Drag?
    private var isPointerInside = false
    private var showsResizeCursor = false
    var isDragging: Bool { drag != nil }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Settings' Taskbar Size field is the accessible way to resize the bar.
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        showResizeCursor()
    }

    override func mouseMoved(with event: NSEvent) {
        if isPointerInside { showResizeCursor() }
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        if drag == nil { restoreCursor() }
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
            return
        }
        guard drag == nil else { return }
        let interaction = (window as? any DockWindowInteractionHolding)?.beginInteraction()
        drag = Drag(
            startY: event.locationInWindow.y, startHeight: DockyPreferences.shared.windowsTaskbarHeight,
            interaction: interaction)
        (window as? any WindowsTaskbarResizing)?.beginTaskbarResize()
        showResizeCursor()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        // The bar is pinned to the screen's bottom edge, so the window's origin
        // stays put and window coordinates track the pointer's screen position.
        let height = drag.startHeight + event.locationInWindow.y - drag.startY
        (window as? any WindowsTaskbarResizing)?.applyTaskbarResize(height: WindowsTaskbarMetrics.clampedHeight(height))
        showResizeCursor()
    }

    override func mouseUp(with event: NSEvent) {
        endDrag()
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            showResizeCursor()
        } else {
            isPointerInside = false
            restoreCursor()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        // The taskbar's background menu belongs to the root view.
        superview?.rightMouseDown(with: event)
    }

    override func viewDidHide() {
        super.viewDidHide()
        cancel()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { cancel() }
        super.viewWillMove(toWindow: newWindow)
    }

    private func cancel() {
        endDrag()
        isPointerInside = false
        restoreCursor()
    }

    private func endDrag() {
        guard let drag else { return }
        self.drag = nil
        (window as? any WindowsTaskbarResizing)?.endTaskbarResize()
        (window as? any DockWindowInteractionHolding)?.endInteraction(drag.interaction)
    }

    /// Arrows show only the directions the bar can still grow or shrink.
    private var resizeCursor: NSCursor {
        let height = DockyPreferences.shared.windowsTaskbarHeight
        let range = WindowsTaskbarMetrics.heightRange
        let directions: NSCursor.FrameResizeDirection.Set =
            height >= range.upperBound ? .inward : height <= range.lowerBound ? .outward : .all
        return .frameResize(position: .top, directions: directions)
    }

    private func showResizeCursor() {
        if !showsResizeCursor {
            showsResizeCursor = true
            setsCursorInBackground(true)
        }
        resizeCursor.set()
    }

    private func restoreCursor() {
        guard showsResizeCursor else { return }
        showsResizeCursor = false
        NSCursor.arrow.set()
        setsCursorInBackground(false)
    }
}
