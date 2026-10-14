import AppKit

@MainActor
protocol DockWindowInteractionHolding: AnyObject {
    func beginInteraction()
    func endInteraction()
}

@MainActor
protocol DockSearchFocusWindow: AnyObject {
    func setSearchFocus(_ focused: Bool)
}
