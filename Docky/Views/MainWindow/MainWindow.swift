//
//  MainWindow.swift
//  Docky
//
//  Created by Jose Quintero on 17/04/26.
//

import AppKit
import Combine

final class MainWindowContainerView: NSView {
    private let contentView = DockRootView(frame: .zero)
    private var trackingArea: NSTrackingArea?

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
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        (window as? MainWindow)?.pointerDidEnterWindow()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        (window as? MainWindow)?.pointerDidExitWindow()
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
    let editMode = DockEditModeService.shared
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
    /// True while the Windows taskbar's top edge is being dragged.
    var isResizingTaskbar = false
    var lastTaskbarHeight: CGFloat?

    var isFullscreenActive: Bool { isFullscreenActiveOnTargetScreen }
    var permitsPassivePresentation: Bool { !isFullscreenActiveOnTargetScreen || fullscreenRevealAuthorized }

    var showsPassiveCompanions: Bool { visibilityState == .visible && permitsPassivePresentation }

    var effectivelyAutohides: Bool {
        preferences.autohidesWindow || isFullscreenActiveOnTargetScreen
    }

    var isContentOverlapActive: Bool { isFullscreenActiveOnTargetScreen }

    /// Screen-coordinate rect of the taskbar chrome. Built from `chromeSize`
    /// rather than crossing the view/window coordinate boundary. Overlays
    /// that need to align to chrome edges read this.
    func chromeScreenFrame() -> CGRect? {
        let chromeSize = DockLayoutService.shared.chromeSize
        guard chromeSize.width > 0, chromeSize.height > 0 else { return nil }
        let position = DockyPreferences.shared.effectiveWindowPosition
            .resolved(systemOrientation: DockSettingsService.shared.orientation)
        return DockSystemGeometry.restingChrome(window: frame, size: chromeSize, edge: position)
    }

    override init(
        contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        visibilityState = DockyPreferences.shared.autohidesWindow ? .hidden : .visible
        // Force `.nonactivatingPanel` regardless of what the XIB hands us so
        // tile clicks never bring Docky to the foreground. The XIB supplies a
        // borderless mask, and `styleMask` keeps `.resizable` off.
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
        // The taskbar's resize handle tracks `.mouseMoved` to set its cursor.
        // Enabling mouseMoved on the window itself ensures AppKit routes those
        // events through the responder chain even though this panel never
        // becomes key.
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

    /// Only Docky sizes the dock. ScreenCaptureKit's ReplayKit window-rotation
    /// lock restores app windows' style masks with `.resizable` added, which
    /// would let AppKit resize this panel from its edges and swallow drags on
    /// the Windows taskbar's resize handle.
    override var styleMask: NSWindow.StyleMask {
        get { super.styleMask }
        set { super.styleMask = newValue.subtracting(.resizable) }
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
