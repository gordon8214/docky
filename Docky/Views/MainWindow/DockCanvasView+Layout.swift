import AppKit
import QuartzCore

extension DockCanvasView {
    func layoutCanvas() {
        guard !isLayingOut else { return }
        isLayingOut = true
        defer { isLayingOut = false }
        layoutWindowsTaskbar()
    }
    /// Hosts a section's document view in a scroll view that keeps it clipped to `frame`.
    func configureSectionHost(_ document: NSView, id: String, frame: CGRect, vertical: Bool) {
        let scroll = scrollViews[id] ?? DockSectionScrollView()
        (scroll as? DockSectionScrollView)?.isVertical = vertical
        if scrollObservers[id] == nil {
            scroll.contentView.postsBoundsChangedNotifications = true
            scrollObservers[id] = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshFrames() }
            }
        }
        scrollViews[id] = scroll
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        if scroll.superview !== self { addSubview(scroll) }
        if scroll.documentView !== document {
            document.removeFromSuperview()
            scroll.documentView = document
        }
        scroll.frame = frame
    }
}
