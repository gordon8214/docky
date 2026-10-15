import AppKit

@MainActor
protocol DockWindowInteractionHolding: AnyObject {
    @discardableResult func beginInteraction() -> UUID?
    func endInteraction(_ token: UUID?)
}

/// A window whose Windows taskbar resizes from its top edge.
@MainActor
protocol WindowsTaskbarResizing: AnyObject {
    func beginTaskbarResize()
    func applyTaskbarResize(height: CGFloat)
    func endTaskbarResize()
}

@MainActor
protocol DockSearchFocusWindow: AnyObject {
    func setSearchFocus(_ focused: Bool)
}
