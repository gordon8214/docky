//
//  MainWindow.swift
//  Docky
//
//  Created by Jose Quintero on 17/04/26.
//

import AppKit
import Combine
import Observation

final class MainWindowContainerView: NSView {
    private let contentView = DockRootView(frame: .zero)
    private var trackingArea: NSTrackingArea?
    private var topConstraint: NSLayoutConstraint!
    private var bottomConstraint: NSLayoutConstraint!
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        topConstraint = contentView.topAnchor.constraint(equalTo: topAnchor)
        bottomConstraint = bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        leadingConstraint = contentView.leadingAnchor.constraint(equalTo: leadingAnchor)
        trailingConstraint = trailingAnchor.constraint(equalTo: contentView.trailingAnchor)

        NSLayoutConstraint.activate([
            topConstraint, bottomConstraint, leadingConstraint, trailingConstraint
        ])

        applyContentInsets()
        observePreferencesForInsets()
    }

    /// Re-applies the per-edge content padding. Full-axis mode forces
    /// every edge to 0 so the chrome bleeds to the panel border; in
    /// fit-content mode each edge picks up its own theme/user override
    /// from `DockyPreferences`.
    private func applyContentInsets() {
        let prefs = DockyPreferences.shared
        let fullAxis = prefs.effectiveWindowAxisSizing == .fullAxis
        let top = fullAxis ? 0 : prefs.effectiveWindowContentInsetTop
        let leading = fullAxis ? 0 : prefs.effectiveWindowContentInsetLeading
        let bottom = fullAxis ? 0 : prefs.effectiveWindowContentInsetBottom
        let trailing = fullAxis ? 0 : prefs.effectiveWindowContentInsetTrailing
        topConstraint.constant = top
        bottomConstraint.constant = bottom
        leadingConstraint.constant = leading
        trailingConstraint.constant = trailing
    }

    /// Observation-framework wiring: every read inside the closure is
    /// tracked; the `onChange` callback fires once per change, then we
    /// re-register by recursing. Same pattern AppKit code elsewhere in
    /// the project uses to bridge from `@Observable` into NSView land.
    private func observePreferencesForInsets() {
        withObservationTracking {
            _ = DockyPreferences.shared.effectiveWindowAxisSizing
            _ = DockyPreferences.shared.effectiveWindowContentInsetTop
            _ = DockyPreferences.shared.effectiveWindowContentInsetLeading
            _ = DockyPreferences.shared.effectiveWindowContentInsetBottom
            _ = DockyPreferences.shared.effectiveWindowContentInsetTrailing
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.applyContentInsets()
                self.observePreferencesForInsets()
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        (window as? MainWindow)?.pointerDidEnterWindow()
        forwardMagnificationPointer(from: event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        forwardMagnificationPointer(from: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        (window as? MainWindow)?.pointerDidExitWindow()
        DockMagnificationService.shared.clearPointer()
    }

    /// Pushes the live pointer position into the magnification service in
    /// the hosting view's top-left origin coordinate space, same as what
    /// native tile views report. Caller flips Y
    /// when the underlying DockRootView isn't already flipped.
    ///
    /// We only forward when the cursor is within the chrome's cross-axis
    /// strip. The window is taller (or wider, for side docks) than the
    /// chrome to make room for magnified icons, so a window-wide tracking
    /// area would magnify tiles as soon as the pointer entered the empty
    /// headroom above the chrome, well before it ever touched a tile.
    private func forwardMagnificationPointer(from event: NSEvent) {
        let inHosting = contentView.convert(event.locationInWindow, from: nil)
        let topLeft: CGPoint =
            contentView.isFlipped
            ? inHosting
            : CGPoint(x: inHosting.x, y: contentView.bounds.height - inHosting.y)
        guard cursorIsAtChromeFringe(topLeft, canvasSize: contentView.bounds.size) else {
            DockMagnificationService.shared.clearPointer()
            return
        }
        DockMagnificationService.shared.updatePointer(at: topLeft)
    }

    /// Cross-axis bounds check against the resting chrome. We don't gate
    /// on the along-axis (proximity to dock edge in that direction is the
    /// whole point of the cosine falloff), only the cross-axis fringe.
    private func cursorIsAtChromeFringe(_ point: CGPoint, canvasSize: CGSize) -> Bool {
        let chromeSize = DockLayoutService.shared.chromeSize
        guard chromeSize.width > 0, chromeSize.height > 0 else { return true }
        let position = DockyPreferences.shared.windowPosition
            .resolved(systemOrientation: DockSettingsService.shared.orientation)
        switch position {
        case .bottom:
            return point.y >= canvasSize.height - chromeSize.height
        case .top:
            return point.y <= chromeSize.height
        case .left:
            return point.x <= chromeSize.width
        case .right:
            return point.x >= canvasSize.width - chromeSize.width
        }
    }
}

/// NSPanel (not NSWindow) so the `.nonactivatingPanel` style mask actually
/// takes effect, that's the only way to keep clicks on the dock from
/// activating Docky as a foreground app, which would otherwise break
/// frontmost-tracked behaviors (cycle windows on tile click, hide-on-second-click).
final class MainWindow: NSPanel {
    /// We default to `false` so tile clicks don't bring Docky to the
    /// foreground (frontmost-tracked behaviors like cycle-on-click rely
    /// on the previously-frontmost app staying key). Embedded controls
    /// that need keyboard input, currently only the Search widget's
    /// 2x/3x text field, set `allowsKeyWindow` to `true` while focused
    /// so AppKit can route keystrokes into them, then flip it back off
    /// on resign.
    static var allowsKeyWindow: Bool = false
    override var canBecomeKey: Bool { Self.allowsKeyWindow }
    override var canBecomeMain: Bool { false }

    enum VisibilityState {
        case visible
        case hidden
    }

    let backgroundBlurRadius = 10
    let revealTriggerThickness: CGFloat = 2
    let tileMutationAnimationDuration: TimeInterval = 0.18
    let dockSettings = DockSettingsService.shared
    let preferences = DockyPreferences.shared
    let layout = DockLayoutService.shared
    let tileStore = TileStore.shared
    let editMode = DockEditModeService.shared
    let minimumWidth: CGFloat = 120
    var cancellables: Set<AnyCancellable> = []
    var hideWorkItem: DispatchWorkItem?
    var fullscreenRecheckWorkItem: DispatchWorkItem?
    var fullscreenRevealWorkItem: DispatchWorkItem?
    var globalPointerMonitor: Any?
    var localPointerMonitor: Any?
    var globalDragRevealMonitor: Any?
    var localDragRevealMonitor: Any?
    var revealTriggerZone: CGRect = .zero
    var isPointerInsideWindow = false
    var interactionTokens: Set<UUID> = []
    var activeInteractionCount: Int { interactionTokens.count }
    var visibilityState: VisibilityState
    var hasCompletedSetup = false
    var hasResolvedInitialFrame = false
    var lastPointerScreenFrame: CGRect?
    var isFullscreenActiveOnTargetScreen = false
    var fullscreenRevealAuthorized = false

    var isFullscreenActive: Bool { isFullscreenActiveOnTargetScreen }
    var permitsPassivePresentation: Bool { !isFullscreenActiveOnTargetScreen || fullscreenRevealAuthorized }

    var showsPassiveCompanions: Bool { visibilityState == .visible && permitsPassivePresentation }

    var effectivelyAutohides: Bool {
        preferences.autohidesWindow || isFullscreenActiveOnTargetScreen
    }

    var isContentOverlapActive: Bool { isFullscreenActiveOnTargetScreen }

    /// Screen-coordinate rect of the visible chrome (the dock pill itself,
    /// not the magnification headroom around it). Built from `chromeSize`
    /// rather than crossing the view/window coordinate boundary, since the
    /// chrome is always centered along-axis within the window (in
    /// full-axis mode it just happens to span edge-to-edge), and pinned
    /// to the inward cross-axis edge with magnification headroom on the
    /// other side. Overlays that need to align to chrome edges read this.
    func chromeScreenFrame() -> CGRect? {
        let chromeSize = DockLayoutService.shared.chromeSize
        guard chromeSize.width > 0, chromeSize.height > 0 else { return nil }
        let position = DockyPreferences.shared.windowPosition
            .resolved(systemOrientation: DockSettingsService.shared.orientation)
        return DockSystemGeometry.restingChrome(
            window: frame, size: chromeSize, edge: position, edgeGap: chromeEdgeGap(position))
    }

    override init(
        contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        visibilityState = DockyPreferences.shared.autohidesWindow ? .hidden : .visible
        // Force `.nonactivatingPanel` regardless of what the XIB hands us so
        // tile clicks never bring Docky to the foreground. Other bits stay
        // intact (the XIB-supplied mask covers titled/resizable/etc.).
        super.init(
            contentRect: contentRect,
            styleMask: style.union(.nonactivatingPanel),
            backing: backingStoreType,
            defer: flag
        )
        performSetupIfNeeded()
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {
            applyCurrentFrame(animated: false)
        }
    }

    func performSetupIfNeeded() {
        guard !hasCompletedSetup else { return }
        hasCompletedSetup = true

        isFloatingPanel = false
        // AppKit resets the level when isFloatingPanel changes. Set the
        // actual Dock level afterward so WindowServer receives level 20.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        backgroundColor = .clear
        isOpaque = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        alphaValue = 0
        // Magnification tracking lives on the content view's NSTrackingArea
        // (.mouseMoved + .activeAlways). Enabling mouseMoved on the window
        // itself ensures AppKit routes those events through the responder
        // chain even though this panel never becomes key.
        acceptsMouseMovedEvents = true
        applyCollectionBehavior()
        observeFrameInputs()
        observeScreenAndSpaceInputs()
        observeWindowPlacementInputs()
        observeVisibilityInputs()
        updatePointerScreenMonitoring()
        updateRevealMonitoring()
        let initialOverlap = computeContentOverlapStateOnTargetScreen()
        isFullscreenActiveOnTargetScreen = initialOverlap.isFullscreen
        if isContentOverlapActive {
            visibilityState = shouldRemainVisible ? .visible : .hidden
        }
    }

    isolated deinit {
        fullscreenRecheckWorkItem?.cancel()
        fullscreenRevealWorkItem?.cancel()
        if let globalPointerMonitor {
            NSEvent.removeMonitor(globalPointerMonitor)
        }
        if let localPointerMonitor {
            NSEvent.removeMonitor(localPointerMonitor)
        }
        if let globalDragRevealMonitor {
            NSEvent.removeMonitor(globalDragRevealMonitor)
        }
        if let localDragRevealMonitor {
            NSEvent.removeMonitor(localDragRevealMonitor)
        }
    }

    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        super.order(place, relativeTo: otherWin)
        applyBackgroundBlur()
    }

    func applyBackgroundBlur() {
        guard windowNumber > 0 else { return }
        _ = CGSSetWindowBackgroundBlurRadius(
            CGSMainConnectionID(),
            windowNumber,
            backgroundBlurRadius
        )
    }

}

extension MainWindow: DockWindowInteractionHolding, DockSearchFocusWindow {
    func setSearchFocus(_ focused: Bool) {
        Self.allowsKeyWindow = focused
        if focused { makeKey() } else { resignKey() }
    }
}
