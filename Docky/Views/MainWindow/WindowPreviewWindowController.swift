//
//  WindowPreviewWindowController.swift
//  Docky
//
//  Hover-driven per-tile counterpart to WindowSwitcherOverlayWindowController.
//  Mirrors WidgetExpansionWindowController's mechanics: a singleton custom
//  borderless NSWindow at .mainMenu level that slide+fades into place over
//  the source tile's frame. The native content (thumbnails or list) is the
//  same as the global switcher's so the two presentations stay coherent
//  without coupling their state.
//

import AppKit
import Combine
import Observation

@MainActor
final class WindowPreviewWindowController: NSWindowController, ObservableObject {
    static let shared = WindowPreviewWindowController()

    @Published private(set) var activeSourceTileID: String?

    fileprivate static let contentPadding: CGFloat = 6
    private static let animationDuration: TimeInterval = 0.18
    private static let slideOffset: CGFloat = 12
    private static let dismissGrace: Duration = .milliseconds(120)

    private var currentTileID: String?
    private var currentBundleIdentifier: String?
    private var isPreviewHovered = false
    private var isHoldingDockVisible = false
    private weak var heldMainWindow: MainWindow?
    private var pendingDismissTask: Task<Void, Never>?
    private var dismissAnimationTask: Task<Void, Never>?

    private init() {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .mainMenu
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
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
        guard let window else { return false }

        let didLoad = WindowPreviewService.shared.present(
            forBundleIdentifiers: bundleIDs,
            sourceTileID: sourceTileID
        )
        guard didLoad else { return false }

        // Already showing for this tile — keep it, just refresh the frame in
        // case the dock layout shifted (magnification, edit mode exit, etc.).
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

        let browser = NativeWindowBrowserController(source: .preview)
        let count = WindowPreviewService.shared.windows.count
        let usesList = WindowPreviewService.shared.resolvedLayout == .list
        let windowSize = CGSize(
            width: usesList ? 340 : CGFloat(min(max(count, 1), 4)) * 228 + 24,
            height: usesList ? CGFloat(min(max(count, 1), 8)) * 52 + 24 : 200)
        browser.view.frame = CGRect(origin: .zero, size: windowSize)
        (browser.view as? NativeHoverMaterialView)?.onHover = { isHovered in
            WindowPreviewWindowController.shared.setPreviewHovered(isHovered, sourceTileID: sourceTileID)
        }
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
            context.duration = Self.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(finalFrame, display: true)
            window.animator().alphaValue = 1
        }

        return true
    }

    func dismiss(sourceTileID: String) {
        guard currentTileID == sourceTileID else { return }
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
                        context.duration = Self.animationDuration
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
        guard !isPreviewHovered else { return }

        pendingDismissTask?.cancel()
        pendingDismissTask = Task { @MainActor in
            try? await Task.sleep(for: Self.dismissGrace)
            guard !Task.isCancelled else { return }
            guard self.currentTileID == sourceTileID, !self.isPreviewHovered else { return }
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
    /// native cards and rows since they only know about the window they
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
        mainWindow.beginInteraction()
        heldMainWindow = mainWindow
        isHoldingDockVisible = true
    }

    private func endDockVisibilityHoldIfNeeded() {
        guard isHoldingDockVisible else { return }
        heldMainWindow?.endInteraction()
        heldMainWindow = nil
        isHoldingDockVisible = false
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
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(sourceFrame) } ?? NSScreen.main
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
        return DockPresentationGeometry.origin(for: .init(size: size, source: sourceFrame, visible: visibleFrame, edge: edge))
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
