import AppKit

@MainActor
protocol DockWindowInteractionHolding: AnyObject {
    @discardableResult func beginInteraction() -> UUID?
    func endInteraction(_ token: UUID?)
}

@MainActor
protocol DockSearchFocusWindow: AnyObject {
    func setSearchFocus(_ focused: Bool)
}
