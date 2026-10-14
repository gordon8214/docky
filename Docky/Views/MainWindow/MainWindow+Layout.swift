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
        let position = preferences.windowPosition.resolved(systemOrientation: dockSettings.orientation)
        // Use menu-bar clearance without subtracting our own reservation.
        // A top-edge fullscreen reveal also stays below the menu bar.
        let visibleBounds = resolvedScreen.map {
            NativeDockIntegration.unreservedFrame(
                $0, fullscreen: isFullscreenActiveOnTargetScreen && position != .top)
        } ?? screenBounds
        // Window-frame math needs the *total* horizontal and vertical
        // padding the chrome view leaves around itself inside the panel.
        // Per-edge insets live in `DockyPreferences`; full-axis mode
        // forces them to zero in `MainWindowContainerView` and we
        // mirror that here so the panel sizing stays in sync.
        let fullAxis = preferences.effectiveWindowAxisSizing == .fullAxis
        let horizontalContentPadding: CGFloat =
            fullAxis
            ? 0
            : preferences.effectiveWindowContentInsetLeading + preferences.effectiveWindowContentInsetTrailing
        let verticalContentPadding: CGFloat =
            fullAxis
            ? 0
            : preferences.effectiveWindowContentInsetTop + preferences.effectiveWindowContentInsetBottom
        let layoutBounds = visibleBounds
        let contentLayout = resolveContentLayout(
            bounds: layoutBounds, position: position,
            horizontalPadding: horizontalContentPadding, verticalPadding: verticalContentPadding)
        let availableAxisLength = contentLayout.availableAxisLength
        let displayedContentSize = contentLayout.size
        let contentScale = contentLayout.scale
        // Keep the chrome stretched across the current dock axis even when the
        // tile layout itself remains content-sized.
        let windowContentSize = magnifiedWindowContentSize(
            displayedContentSize, scale: contentScale, position: position)
        let width = displayedWindowWidth(
            for: windowContentSize,
            displayedAxisLength: availableAxisLength,
            availableAxisLength: availableAxisLength,
            horizontalContentPadding: horizontalContentPadding,
            position: position
        )
        let height = displayedWindowHeight(
            for: windowContentSize,
            displayedAxisLength: availableAxisLength,
            verticalContentPadding: verticalContentPadding,
            position: position
        )
        let size = CGSize(width: width, height: height)
        let origin = frameOrigin(
            in: visibilityState == .hidden ? screenBounds : layoutBounds,
            size: size,
            position: position,
            visibilityState: visibilityState
        )

        let frame = CGRect(origin: origin, size: size)
        revealTriggerZone = makeRevealTriggerZone(in: screenBounds, frame: frame, position: position)
        applyFrame(frame, animated: animated, duration: duration)
        updateReservation(screen: resolvedScreen, bounds: layoutBounds, size: size, position: position)
    }

    func magnifiedWindowContentSize(_ displayedContentSize: CGSize, scale contentScale: CGFloat,
                                    position: ResolvedDockWindowPosition) -> CGSize {
        // Magnified icons render beyond the chrome's natural cross-axis
        // extent. We grow only the window, not the chrome rect, so the
        // chrome itself keeps its resting shape and the icons spill into
        // the headroom above (or beside, on a vertical dock) it. Peak
        // size is the UNscaled `largeSize` even when overflow has shrunk
        // the resting tiles, so headroom is measured from the scaled
        // chrome height up to that fixed peak.
        let scaledBaseTileSize = dockSettings.tileSize * contentScale
        let magnificationHeadroom: CGFloat =
            (dockSettings.magnification && dockSettings.largeSize > scaledBaseTileSize)
            ? dockSettings.largeSize - scaledBaseTileSize
            : 0
        return {
            guard magnificationHeadroom > 0 else { return displayedContentSize }
            return position.isVertical
                ? CGSize(width: displayedContentSize.width + magnificationHeadroom, height: displayedContentSize.height)
                : CGSize(width: displayedContentSize.width, height: displayedContentSize.height + magnificationHeadroom)
        }()
    }

    func updateReservation(screen resolvedScreen: NSScreen?, bounds layoutBounds: CGRect,
                           size: CGSize, position: ResolvedDockWindowPosition) {
        if let resolvedScreen {
            let restingOrigin = frameOrigin(in: layoutBounds, size: size, position: position, visibilityState: .visible)
            let restingFrame = CGRect(origin: restingOrigin, size: size)
            let chromeSize = layout.chromeSize
            let chrome = DockSystemGeometry.restingChrome(
                window: restingFrame, size: chromeSize, edge: position, edgeGap: chromeEdgeGap(position))
            WindowReservationService.shared.update(
                screen: resolvedScreen, chrome: chrome, edge: position,
                reserves: !effectivelyAutohides && isVisible && chromeSize.width > 0 && chromeSize.height > 0)
        }
    }

    func chromeEdgeGap(_ position: ResolvedDockWindowPosition) -> CGFloat {
        guard preferences.effectiveWindowAxisSizing != .fullAxis else { return 0 }
        switch position {
        case .bottom: return preferences.effectiveWindowContentInsetBottom
        case .top: return preferences.effectiveWindowContentInsetTop
        case .left: return preferences.effectiveWindowContentInsetLeading
        case .right: return preferences.effectiveWindowContentInsetTrailing
        }
    }

    func applyFrame(_ frame: CGRect, animated: Bool, duration: TimeInterval?) {
        let shouldAnimate = animated && hasResolvedInitialFrame

        guard shouldAnimate else {
            setFrame(frame, display: true, animate: false)
            revealAfterInitialFrameIfNeeded()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration ?? autohideAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(frame, display: true)
        }
    }

    func revealAfterInitialFrameIfNeeded() {
        guard !hasResolvedInitialFrame else { return }
        hasResolvedInitialFrame = true
        alphaValue = 1
    }

    var autohideAnimationDuration: TimeInterval {
        min(max(0, preferences.autohideAnimationDuration), 1)
    }

    func overflowContentScale(
        for contentSize: CGSize,
        availableAxisLength: CGFloat,
        position: ResolvedDockWindowPosition
    ) -> CGFloat {
        guard preferences.overflowBehavior == .rescale, availableAxisLength > 0 else {
            return 1
        }

        let contentAxisLength = axisLength(of: contentSize, position: position)
        guard contentAxisLength > 0 else { return 1 }
        return min(1, availableAxisLength / contentAxisLength)
    }

    func shouldCompactWidgetsForOverflow(
        contentSize: CGSize,
        availableAxisLength: CGFloat,
        position: ResolvedDockWindowPosition
    ) -> Bool {
        guard preferences.overflowBehavior == .rescale, availableAxisLength > 0 else {
            return false
        }

        return axisLength(of: contentSize, position: position) > availableAxisLength
    }

    func axisLength(of size: CGSize, position: ResolvedDockWindowPosition) -> CGFloat {
        position.isVertical ? size.height : size.width
    }

    func shouldReserveStatusBarLength(
        for contentSize: CGSize,
        availableAxisLength: CGFloat,
        position: ResolvedDockWindowPosition
    ) -> Bool {
        axisLength(of: contentSize, position: position) > availableAxisLength
    }

    var reservedStatusBarLength: CGFloat {
        NSStatusBar.system.thickness * 4
    }

    func displayedWindowWidth(
        for contentSize: CGSize,
        displayedAxisLength: CGFloat,
        availableAxisLength: CGFloat,
        horizontalContentPadding: CGFloat,
        position: ResolvedDockWindowPosition
    ) -> CGFloat {
        if position.isVertical {
            return contentSize.width + horizontalContentPadding
        }

        let visibleAxisLength =
            availableAxisLength > 0
            ? min(max(minimumWidth, displayedAxisLength), availableAxisLength)
            : max(minimumWidth, displayedAxisLength)
        return visibleAxisLength + horizontalContentPadding
    }

    func displayedWindowHeight(
        for contentSize: CGSize,
        displayedAxisLength: CGFloat,
        verticalContentPadding: CGFloat,
        position: ResolvedDockWindowPosition
    ) -> CGFloat {
        if position.isVertical {
            return displayedAxisLength + verticalContentPadding
        }

        return contentSize.height + verticalContentPadding
    }

    func displayedChromeSize(
        for contentSize: CGSize,
        displayedAxisLength: CGFloat,
        position: ResolvedDockWindowPosition
    ) -> CGSize {
        if position.isVertical {
            return CGSize(width: contentSize.width, height: displayedAxisLength)
        }

        return CGSize(width: displayedAxisLength, height: contentSize.height)
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
