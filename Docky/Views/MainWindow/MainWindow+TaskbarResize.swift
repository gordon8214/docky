import AppKit

/// Live resizing of the Windows taskbar from its top edge.
extension MainWindow: WindowsTaskbarResizing {
    func beginTaskbarResize() {
        isResizingTaskbar = true
    }

    /// Applies the frame without animation so the bar's top edge tracks the pointer.
    func applyTaskbarResize(height: CGFloat) {
        let clamped = WindowsTaskbarMetrics.clampedHeight(height)
        guard clamped != preferences.windowsTaskbarHeight else { return }
        preferences.windowsTaskbarHeight = clamped
        applyCurrentFrame(animated: false)
    }

    /// Publishes the screen reservation for the final size.
    func endTaskbarResize() {
        guard isResizingTaskbar else { return }
        isResizingTaskbar = false
        applyCurrentFrame(animated: false)
    }
}
