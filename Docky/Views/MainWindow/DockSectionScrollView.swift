import AppKit

/// A wheel's vertical delta scrolls a horizontal Dock section along its only axis.
final class DockSectionScrollView: NSScrollView {
    var isVertical = false
    override func scrollWheel(with event: NSEvent) {
        guard !isVertical, let documentView else {
            super.scrollWheel(with: event)
            return
        }
        let delta =
            abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX : event.scrollingDeltaY
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
        let limit = max(0, documentView.bounds.width - contentSize.width)
        let offset = min(limit, max(0, contentView.bounds.minX - delta * scale))
        contentView.scroll(to: CGPoint(x: offset, y: 0))
        reflectScrolledClipView(contentView)
    }
}
