//
//  WindowPreviewWindowController.swift
//  Docky
//
//  Hover-driven per-tile counterpart to WindowSwitcherOverlayWindowController.
//  Mirrors WidgetExpansionWindowController's mechanics: a singleton custom
//  borderless NSWindow at .mainMenu level that slide+fades into place over
//  the source tile's frame. The content is `WindowsWindowPreviewController`'s
//  row of window thumbnails.
//

import AppKit
import Combine

@MainActor
final class WindowPreviewWindowController: NSWindowController, ObservableObject {
    static let shared = WindowPreviewWindowController()

    @Published private(set) var activeSourceTileID: String?

    fileprivate static let contentPadding: CGFloat = 6
    private static let slideOffset: CGFloat = 12
    private static let dismissGrace: Duration = .milliseconds(120)

    private var currentTileID: String?
    private var currentBundleIdentifier: String?
    private var isPreviewHovered = false
    private var isHoldingDockVisible = false
    private var interactionToken: UUID?
    private weak var heldMainWindow: MainWindow?
    private var pendingDismissTask: Task<Void, Never>?
    private var dismissAnimationTask: Task<Void, Never>?
    private weak var previousKeyWindow: NSWindow?
    private weak var previousFirstResponder: NSResponder?

    private init() {
        let window = WindowsTaskbarPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .mainMenu
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        // Key-capable so the preview can take arrow keys once focused from its tile.
        window.acceptsKeys = true
        window.hidesOnDeactivate = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Presents the preview anchored next to `sourceFrame` on the inward
    /// side of the dock. Returns false when the bundle has no windows so
    /// callers can keep the tooltip up in that case.
    @discardableResult
    func present(
        forBundleIdentifier bundleID: String,
        sourceTileID: String,
        sourceFrame: CGRect,
        preferredEdge: NSRectEdge
    ) -> Bool {
        present(
            forBundleIdentifiers: [bundleID],
            sourceTileID: sourceTileID,
            sourceFrame: sourceFrame,
            preferredEdge: preferredEdge
        )
    }

    /// Multi-bundle variant used by app-folder tiles. Aggregates windows
    /// from every contained app into a single preview.
    @discardableResult
    func present(
        forBundleIdentifiers bundleIDs: [String],
        sourceTileID: String,
        sourceFrame: CGRect,
        preferredEdge: NSRectEdge
    ) -> Bool {
        guard NSApp.windows.compactMap({ $0 as? MainWindow }).first?.permitsPassivePresentation != false,
              let window else { return false }

        let didLoad = WindowPreviewService.shared.present(
            forBundleIdentifiers: bundleIDs,
            sourceTileID: sourceTileID
        )
        guard didLoad else { return false }

        // Already showing for this tile: keep it and cancel any pending dismiss.
        if currentTileID == sourceTileID, window.isVisible {
            activeSourceTileID = sourceTileID
            pendingDismissTask?.cancel()
            pendingDismissTask = nil
            return true
        }

        currentTileID = sourceTileID
        currentBundleIdentifier = bundleIDs.count == 1 ? bundleIDs.first : nil
        activeSourceTileID = sourceTileID
        pendingDismissTask?.cancel()
        pendingDismissTask = nil
        dismissAnimationTask?.cancel()
        dismissAnimationTask = nil
        beginDockVisibilityHoldIfNeeded()

        let (browser, windowSize) = previewBrowser(sourceTileID: sourceTileID)
        let finalOrigin = frameOrigin(
            for: windowSize,
            sourceFrame: sourceFrame,
            preferredEdge: preferredEdge
        )
        let initialOrigin = initialOrigin(from: finalOrigin, preferredEdge: preferredEdge)
        let finalFrame = CGRect(origin: finalOrigin, size: windowSize)
        let initialFrame = CGRect(origin: initialOrigin, size: windowSize)

        window.contentViewController = browser
        window.setFrame(initialFrame, display: false)
        window.alphaValue = 0
        window.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = WindowsTaskbarStyle.reducesMotion ? 0 : WindowsTaskbarStyle.popupDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(finalFrame, display: true)
            window.animator().alphaValue = 1
        }

        return true
    }
    private func previewBrowser(sourceTileID: String) -> (NSViewController, CGSize) {
        WindowsTaskbarTooltip.shared.dismiss()
        let browser = WindowsWindowPreviewController()
        let count = WindowPreviewService.shared.windows.count
        let size = CGSize(width: CGFloat(min(max(count, 1), 4)) * 228 + 24, height: 200)
        browser.view.frame = CGRect(origin: .zero, size: size)
        browser.onHover = { [weak self] hovered in
            self?.setPreviewHovered(hovered, sourceTileID: sourceTileID)
        }
        return (browser, size)
    }

    func updateSourceFrame(_ frame: CGRect, sourceTileID: String) {
        guard currentTileID == sourceTileID, let window, window.isVisible else { return }
        let origin = frameOrigin(for: window.frame.size, sourceFrame: frame, preferredEdge: .maxY)
        if window.frame.origin != origin { window.setFrameOrigin(origin) }
    }
    func dismissImmediately() {
        restoreKeyboardFocus()
        pendingDismissTask?.cancel()
        pendingDismissTask = nil
        dismissAnimationTask?.cancel()
        dismissAnimationTask = nil
        isPreviewHovered = false
        endDockVisibilityHoldIfNeeded()
        currentTileID = nil
        activeSourceTileID = nil
        currentBundleIdentifier = nil
        WindowPreviewService.shared.dismiss()
        window?.orderOut(nil)
        close()
    }

    func dismiss(sourceTileID: String) {
        guard currentTileID == sourceTileID else { return }
        restoreKeyboardFocus()
        pendingDismissTask?.cancel()
        pendingDismissTask = nil
        isPreviewHovered = false
        endDockVisibilityHoldIfNeeded()
        currentTileID = nil
        currentBundleIdentifier = nil
        activeSourceTileID = nil

        // Don't clear WindowPreviewService state yet — the native views
        // observes it, and emptying it synchronously would blank the popover
        // content before the alpha animation has a chance to play. We clear
        // it in the completion handler so the user sees a real fade-out.

        guard let window, window.isVisible else {
            WindowPreviewService.shared.dismiss()
            close()
            return
        }

        dismissAnimationTask?.cancel()
        dismissAnimationTask = Task { @MainActor in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                NSAnimationContext.runAnimationGroup(
                    { context in
                        context.duration = WindowsTaskbarStyle.reducesMotion ? 0 : WindowsTaskbarStyle.popupDuration
                        context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                        window.animator().alphaValue = 0
                    },
                    completionHandler: {
                        continuation.resume()
                    })
            }
            if Task.isCancelled { return }
            guard self.currentTileID == nil else { return }
            WindowPreviewService.shared.dismiss()
            self.close()
        }
    }

    func requestDismiss(sourceTileID: String) {
        guard currentTileID == sourceTileID else { return }
        guard !isPreviewHovered, !WindowPreviewService.shared.isContextMenuPresented else { return }

        pendingDismissTask?.cancel()
        pendingDismissTask = Task { @MainActor in
            try? await Task.sleep(for: Self.dismissGrace)
            guard !Task.isCancelled else { return }
            guard self.currentTileID == sourceTileID, !self.isPreviewHovered,
                !WindowPreviewService.shared.isContextMenuPresented else { return }
            self.dismiss(sourceTileID: sourceTileID)
        }
    }

    fileprivate func setPreviewHovered(_ isHovered: Bool, sourceTileID: String) {
        guard currentTileID == sourceTileID else { return }
        isPreviewHovered = isHovered

        if isHovered {
            pendingDismissTask?.cancel()
            pendingDismissTask = nil
        } else {
            requestDismiss(sourceTileID: sourceTileID)
        }
    }

    /// Closes whichever tile's preview is currently showing. Used by the
    /// preview's thumbnails, which only know about the window they
    /// represent, not which source tile spawned the preview.
    func dismissCurrent() {
        guard let currentTileID else { return }
        dismiss(sourceTileID: currentTileID)
    }

    /// Tap-to-confirm: tear down the preview and focus the chosen window.
    func confirm(_ window: AppWindow) {
        dismissCurrent()
        _ = WorkspaceService.shared.focus(window: window)
    }

    var isShowing: Bool { window?.isVisible == true }
    var presentedSourceTileID: String? { currentTileID }

    private func beginDockVisibilityHoldIfNeeded() {
        guard !isHoldingDockVisible else { return }
        guard let mainWindow = NSApp.windows.compactMap({ $0 as? MainWindow }).first else { return }
        interactionToken = mainWindow.beginInteraction()
        heldMainWindow = mainWindow
        isHoldingDockVisible = true
    }

    private func endDockVisibilityHoldIfNeeded() {
        guard isHoldingDockVisible else { return }
        heldMainWindow?.endInteraction(interactionToken)
        heldMainWindow = nil
        isHoldingDockVisible = false
    }

}

extension WindowPreviewWindowController {
    func focusForKeyboardInteraction() {
        guard let window, window.isVisible else { return }
        if !window.isKeyWindow {
            previousKeyWindow = NSApp.keyWindow
            previousFirstResponder = previousKeyWindow?.firstResponder
        }
        window.makeKey()
        window.makeFirstResponder(window.contentViewController?.view)
    }
    private func restoreKeyboardFocus() {
        if window?.isKeyWindow == true, let previousKeyWindow {
            previousKeyWindow.makeKey()
            previousKeyWindow.makeFirstResponder(previousFirstResponder)
        }
        previousKeyWindow = nil
        previousFirstResponder = nil
    }
    func contextMenuPresentationChanged(_ presented: Bool, sourceTileID: String) {
        // Native menus run their action before reporting the close, and the action may
        // already have dismissed this preview, so always clear the flag on close.
        if !presented { WindowPreviewService.shared.setContextMenuPresented(false) }
        guard currentTileID == sourceTileID else { return }
        if presented {
            WindowPreviewService.shared.setContextMenuPresented(true)
            pendingDismissTask?.cancel()
            pendingDismissTask = nil
        } else { requestDismiss(sourceTileID: sourceTileID) }
    }

    /// Positions the preview window against the inward edge of the dock so
    /// it sits between the tile and the screen interior, mirroring
    /// WidgetExpansionWindowController's overflow handling per dock side.
    private func frameOrigin(
        for size: CGSize,
        sourceFrame originalSourceFrame: CGRect,
        preferredEdge: NSRectEdge
    ) -> CGPoint {
        // The canvas reports top-left coordinates relative to
        // the dock canvas. Convert to AppKit screen bottom-left
        // before placing this NSWindow — otherwise vertical docks see a Y flip
        // and centered docks see an X offset (bottom docks happened to work by
        // coincidence when the tile sat at the dock window's vertical center).
        let sourceFrame = convertToScreen(originalSourceFrame)
        let screens = NSScreen.screens
        let index = DockPresentationGeometry.screenIndex(containing: sourceFrame, frames: screens.map(\.frame))
        let screen = index.map { screens[$0] } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            return CGPoint(x: sourceFrame.midX - size.width / 2, y: sourceFrame.maxY)
        }

        let edge: ResolvedDockWindowPosition
        switch preferredEdge {
        case .minY: edge = .top
        case .maxX: edge = .left
        case .minX: edge = .right
        default: edge = .bottom
        }
        return DockPresentationGeometry.origin(
            for: .init(size: size, source: sourceFrame, visible: visibleFrame, edge: edge))
    }
    private func convertToScreen(_ frame: CGRect) -> CGRect {
        guard let dockFrame = NSApp.windows.compactMap({ $0 as? MainWindow }).first?.frame else { return frame }
        return DockPresentationGeometry.screenFrame(fromTopLeft: frame, windowFrame: dockFrame)
    }

    private func initialOrigin(from final: CGPoint, preferredEdge: NSRectEdge) -> CGPoint {
        switch preferredEdge {
        case .maxY: return CGPoint(x: final.x, y: final.y - Self.slideOffset)
        case .minY: return CGPoint(x: final.x, y: final.y + Self.slideOffset)
        case .maxX: return CGPoint(x: final.x - Self.slideOffset, y: final.y)
        case .minX: return CGPoint(x: final.x + Self.slideOffset, y: final.y)
        @unknown default: return CGPoint(x: final.x, y: final.y - Self.slideOffset)
        }
    }
}
