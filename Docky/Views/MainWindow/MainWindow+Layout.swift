import AppKit
import Combine
import QuartzCore

extension MainWindow {
    func applyCurrentFrame(animated: Bool) {
        applyCurrentFrame(animated: animated, duration: nil)
    }

    func applyCurrentFrame(animated: Bool, duration: TimeInterval?) {
        let resolvedScreen = targetScreen() ?? screen ?? NSScreen.main
        let screenBounds = resolvedScreen?.frame ?? .zero
        lastPointerScreenFrame = screenBounds
        let position = preferences.effectiveWindowPosition.resolved(systemOrientation: dockSettings.orientation)
        // Use menu-bar clearance without subtracting our own reservation.
        // A top-edge fullscreen reveal also stays below the menu bar.
        let layoutBounds = resolvedScreen.map {
            NativeDockIntegration.unreservedFrame(
                $0, fullscreen: isFullscreenActiveOnTargetScreen && position != .top)
        } ?? screenBounds
        let size = taskbarSize(in: layoutBounds, position: position)
        layout.setChromeSize(size)
        let origin = frameOrigin(
            in: visibilityState == .hidden ? screenBounds : layoutBounds,
            size: size,
            position: position,
            visibilityState: visibilityState
        )

        let frame = CGRect(origin: origin, size: size)
        revealTriggerZone = makeRevealTriggerZone(in: screenBounds, frame: frame, position: position)
        // The taskbar's content lays out at a new size at once, so animating the
        // window to that size would clip it until the animation finished.
        let taskbarHeight = WindowsTaskbarStyle.metrics.height
        let taskbarHeightChanged = lastTaskbarHeight != nil && taskbarHeight != lastTaskbarHeight
        lastTaskbarHeight = taskbarHeight
        applyFrame(frame, animated: animated && !isResizingTaskbar && !taskbarHeightChanged, duration: duration)
        // Each published reservation spawns a verification probe and reflows
        // other apps' windows, so a resize drag publishes once, when it ends.
        guard !isResizingTaskbar else { return }
        updateReservation(screen: resolvedScreen, bounds: layoutBounds, size: size, position: position)
    }

    /// The taskbar spans the whole screen edge it sits on.
    func taskbarSize(in bounds: CGRect, position: ResolvedDockWindowPosition) -> CGSize {
        let thickness = WindowsTaskbarStyle.metrics.height
        return position.isVertical
            ? CGSize(width: thickness, height: bounds.height)
            : CGSize(width: bounds.width, height: thickness)
    }

    func updateReservation(screen resolvedScreen: NSScreen?, bounds layoutBounds: CGRect,
                           size: CGSize, position: ResolvedDockWindowPosition) {
        if let resolvedScreen {
            let restingOrigin = frameOrigin(in: layoutBounds, size: size, position: position, visibilityState: .visible)
            let restingFrame = CGRect(origin: restingOrigin, size: size)
            let chromeSize = layout.chromeSize
            let chrome = DockSystemGeometry.restingChrome(window: restingFrame, size: chromeSize, edge: position)
            WindowReservationService.shared.update(
                screen: resolvedScreen, chrome: chrome, edge: position,
                reserves: !effectivelyAutohides && isVisible && chromeSize.width > 0 && chromeSize.height > 0)
        }
    }

    func applyFrame(_ frame: CGRect, animated: Bool, duration: TimeInterval?) {
        let shouldAnimate = animated && hasResolvedInitialFrame
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        guard shouldAnimate else {
            setFrame(frame, display: true, animate: false)
            revealAfterInitialFrameIfNeeded()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration ?? WindowsTaskbarStyle.layoutDuration
            context.timingFunction = WindowsTaskbarStyle.timingFunction
            animator().setFrame(frame, display: true)
        }
    }

    func revealAfterInitialFrameIfNeeded() {
        guard !hasResolvedInitialFrame else { return }
        hasResolvedInitialFrame = true
        alphaValue = 1
    }

    func frameOrigin(
        in screenBounds: CGRect,
        size: CGSize,
        position: ResolvedDockWindowPosition,
        visibilityState: VisibilityState
    ) -> CGPoint {
        let hidden = visibilityState == .hidden

        switch position {
        case .top:
            return CGPoint(
                x: screenBounds.minX + (screenBounds.width - size.width) / 2,
                y: hidden ? screenBounds.maxY : screenBounds.maxY - size.height
            )
        case .left:
            return CGPoint(
                x: hidden ? screenBounds.minX - size.width : screenBounds.minX,
                y: screenBounds.minY + (screenBounds.height - size.height) / 2
            )
        case .right:
            return CGPoint(
                x: hidden ? screenBounds.maxX : screenBounds.maxX - size.width,
                y: screenBounds.minY + (screenBounds.height - size.height) / 2
            )
        case .bottom:
            return CGPoint(
                x: screenBounds.minX + (screenBounds.width - size.width) / 2,
                y: hidden ? screenBounds.minY - size.height : screenBounds.minY
            )
        }
    }

    func makeRevealTriggerZone(
        in screenBounds: CGRect,
        frame: CGRect,
        position: ResolvedDockWindowPosition
    ) -> CGRect {
        let thickness = revealTriggerThickness

        switch position {
        case .top:
            return CGRect(x: frame.minX, y: screenBounds.maxY - thickness, width: frame.width, height: thickness)
        case .bottom:
            return CGRect(x: frame.minX, y: screenBounds.minY, width: frame.width, height: thickness)
        case .left:
            return CGRect(x: screenBounds.minX, y: frame.minY, width: thickness, height: frame.height)
        case .right:
            return CGRect(x: screenBounds.maxX - thickness, y: frame.minY, width: thickness, height: frame.height)
        }
    }

    func targetScreen() -> NSScreen? {
        // Keep the taskbar on its display while its top edge is dragged, even
        // when the pointer crosses into a display stacked above it.
        if isResizingTaskbar, let screen { return screen }
        switch preferences.windowDisplayTarget {
        case .primaryDisplay:
            return NSScreen.screens.first ?? NSScreen.main
        case .displayContainingPointer:
            let mouseLocation = NSEvent.mouseLocation
            return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
                ?? screen
                ?? NSScreen.main
                ?? NSScreen.screens.first
        }
    }

}
