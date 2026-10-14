//
//  StartMenuOverlayWindowController.swift
//  Docky
//
//  Prototype controller. Hosts a borderless `.nonactivatingPanel`
//  attached to the dock via `addChildWindow(_:ordered:)`. The two
//  things this prototype is meant to verify:
//
//   1. Movement grouping — when the dock re-anchors (edge change,
//      screen change, manual setFrame), does the child follow without
//      us wiring our own move/resize observers?
//   2. Focus — can a `.nonactivatingPanel` child become key for its
//      native search field without pulling Docky to the foreground?
//      (Spotlight's pattern.)
//

import AppKit
import Carbon
import Combine
import Observation

final class StartMenuOverlayWindowController: NSWindowController {
    private weak var mainWindow: MainWindow?
    private var cancellables: Set<AnyCancellable> = []
    private var isInterruptingMainWindow = false
    private var isAttachedToParent = false
    private var localDismissMonitor: Any?
    private var globalDismissMonitor: Any?
    private var escapeKeyMonitor: Any?
    /// systemUptime captured when the dismiss monitors are installed.
    /// Used to swallow the very click that opened the menu, which can
    /// reach the local monitor with a timestamp predating install
    /// because Combine defers present() to the next runloop tick but
    /// the originating mouseDown stays queued.
    private var dismissMonitorsInstalledAt: TimeInterval = 0
    private let animationDuration: TimeInterval = 0.16
    /// The host panel is always sized for both sub-panels so the layout
    /// never reflows. The right slot stays transparent (and non-
    /// interactive) until the user toggles the all-apps panel on.
    private let mainPanelWidth: CGFloat = 440
    private let sidePanelWidth: CGFloat = 280
    private let sidePanelGap: CGFloat = 8
    private var panelSize: NSSize {
        NSSize(width: mainPanelWidth + sidePanelGap + sidePanelWidth, height: 680)
    }
    private let gap: CGFloat = 8
    private let contentController = NativeStartMenuController()

    init(mainWindow: MainWindow) {
        self.mainWindow = mainWindow

        let panel = StartMenuPanel()
        panel.setContentSize(NSSize(width: 440 + 8 + 280, height: 680))
        panel.contentViewController = contentController

        super.init(window: panel)

        prepareWindow()
        observePresentation()
        observeChromeAndParent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func prepareWindow() {
        guard let window else { return }
        window.alphaValue = 0
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }

    private func observePresentation() {
        StartMenuService.shared.$isPresented
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPresented in
                guard let self else { return }
                isPresented ? self.present() : self.dismiss()
            }
            .store(in: &cancellables)
    }

    /// Re-anchor whenever the chrome rect inside the window shifts
    /// (tile add/remove, magnification, axis-sizing toggle) or when the
    /// parent's frame itself changes (edge change, screen change).
    /// addChildWindow already translates the child for parent moves,
    /// but it can't see chrome shifts that happen inside the parent.
    private func observeChromeAndParent() {
        DockLayoutService.shared.$chromeSize
            .removeDuplicates(by: { abs($0.width - $1.width) < 0.5 && abs($0.height - $1.height) < 0.5 })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateFrameIfPresented() }
            .store(in: &cancellables)

        let center = NotificationCenter.default
        center.publisher(for: NSWindow.didMoveNotification, object: mainWindow)
            .merge(with: center.publisher(for: NSWindow.didResizeNotification, object: mainWindow))
            .merge(with: center.publisher(for: NSWindow.didChangeScreenNotification, object: mainWindow))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateFrameIfPresented() }
            .store(in: &cancellables)
    }

    private func updateFrameIfPresented() {
        guard StartMenuService.shared.isPresented else { return }
        updateFrame()
    }

    private func present() {
        guard let panel = window as? StartMenuPanel, let main = mainWindow else { return }
        updateFrame()
        beginMainInteraction()
        if !isAttachedToParent {
            main.addChildWindow(panel, ordered: .above)
            isAttachedToParent = true
        }
        // Re-assert level after addChildWindow because AppKit will pin
        // the child's z-order relative to the parent and can clamp the
        // absolute level in the process.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        panel.makeKeyAndOrderFront(nil)
        installDismissMonitors()
        animateAlpha(to: 1)
    }

    private func dismiss() {
        removeDismissMonitors()
        animateAlpha(to: 0) { [weak self] in
            guard let self, let panel = self.window as? StartMenuPanel else { return }
            if self.isAttachedToParent, let main = self.mainWindow {
                main.removeChildWindow(panel)
                self.isAttachedToParent = false
            }
            panel.orderOut(nil)
            self.endMainInteraction()
        }
    }

    private func updateFrame() {
        guard let panel = window, let main = mainWindow,
            let screen = main.screen ?? NSScreen.main
        else { return }
        let visible = screen.visibleFrame
        let position = DockyPreferences.shared.windowPosition
            .resolved(systemOrientation: DockSettingsService.shared.orientation)

        // Anchor against the visible chrome rect when available; fall
        // back to the window frame for the brief startup window before
        // TileContainerView has reported its first geometry pass.
        let anchor = main.chromeScreenFrame() ?? main.frame

        // Leading along-axis is the user's natural reading-start edge:
        // left for horizontal docks, top for vertical docks. Trailing
        // across-axis is the chrome's inward edge (the side that faces
        // the rest of the screen). The panel hugs the corner where
        // those two edges meet, then extends inward and along the axis.
        let size = panelSize
        let origin: CGPoint
        switch position {
        case .bottom:
            origin = CGPoint(x: anchor.minX, y: anchor.maxY + gap)
        case .top:
            origin = CGPoint(x: anchor.minX, y: anchor.minY - size.height - gap)
        case .left:
            origin = CGPoint(x: anchor.maxX + gap, y: anchor.maxY - size.height)
        case .right:
            origin = CGPoint(x: anchor.minX - size.width - gap, y: anchor.maxY - size.height)
        }

        let clamped = CGPoint(
            x: min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8),
            y: min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        )

        panel.setFrame(CGRect(origin: clamped, size: size).integral, display: true)
    }

    private func animateAlpha(to value: CGFloat, completion: (@MainActor () -> Void)? = nil) {
        guard let window else {
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animationDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = value
        } completionHandler: {
            Task { @MainActor in
                completion?()
            }
        }
    }

    private func beginMainInteraction() {
        guard !isInterruptingMainWindow else { return }
        mainWindow?.beginInteraction()
        isInterruptingMainWindow = true
    }

    private func endMainInteraction() {
        guard isInterruptingMainWindow else { return }
        mainWindow?.endInteraction()
        isInterruptingMainWindow = false
    }

    /// Click-outside-to-dismiss. Local monitor fires when the click
    /// lands in any Docky window (including the dock itself); global
    /// fires for every other app. The hit test against the panel
    /// frame in screen coords keeps clicks inside the start menu
    /// from dismissing it.
    private func installDismissMonitors() {
        guard localDismissMonitor == nil, globalDismissMonitor == nil else { return }

        dismissMonitorsInstalledAt = ProcessInfo.processInfo.systemUptime

        let dismissIfOutside: () -> Void = { [weak self] in
            guard let self, let panel = self.window else { return }
            if !panel.frame.contains(NSEvent.mouseLocation) {
                DispatchQueue.main.async {
                    StartMenuService.shared.dismiss()
                }
            }
        }

        localDismissMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            // Suppress the originating tile click: its timestamp is
            // already older than the install time by the time we get
            // here, otherwise a single tap would open + close in one go.
            guard event.timestamp > self.dismissMonitorsInstalledAt else {
                return event
            }
            // Clicks on the dock itself are handled by the source
            // tile's own tap logic: the start-menu / Finder tile
            // calls `toggle()`, which closes the menu cleanly. If we
            // also dismissed here, the tap handler would see
            // `isPresented == false` and reopen on the same click.
            if let eventWindow = event.window, eventWindow === self.mainWindow {
                return event
            }
            dismissIfOutside()
            return event
        }

        globalDismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return }
            guard event.timestamp > self.dismissMonitorsInstalledAt else {
                return
            }
            dismissIfOutside()
        }

        // Escape dismisses while the menu has key focus. Returning nil
        // swallows the event so the focused TextField doesn't also see
        // it (and try to clear its contents on first press).
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard Int(event.keyCode) == kVK_Escape else { return event }
            DispatchQueue.main.async {
                StartMenuService.shared.dismiss()
            }
            return nil
        }
    }

    private func removeDismissMonitors() {
        if let monitor = localDismissMonitor {
            NSEvent.removeMonitor(monitor)
            localDismissMonitor = nil
        }
        if let monitor = globalDismissMonitor {
            NSEvent.removeMonitor(monitor)
            globalDismissMonitor = nil
        }
        if let monitor = escapeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            escapeKeyMonitor = nil
        }
    }
}

private final class StartMenuPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        // AppKit derives a window shadow from the content alpha mask, and
        // on a transparent panel hosting separate native glass surfaces
        // that mask has aliased sub-pixel edges along the panel
        // perimeter, which render as a faint hairline around the whole
        // window. The shadows on each sub-panel come from AppKit's
        // `.shadow(...)` modifier instead.
        hasShadow = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
    }

    /// `.nonactivatingPanel` + `canBecomeKey == true` is the Spotlight
    /// pattern: the panel can take keyboard focus (so the native
    /// TextField actually receives input) without bringing Docky to
    /// the foreground.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum SystemAction {
    case sleep
    case restart
    case shutDown
    case logOut

    var title: String {
        switch self {
        case .sleep: return "Sleep"
        case .restart: return "Restart..."
        case .shutDown: return "Shut Down..."
        case .logOut: return "Log Out..."
        }
    }

    private var eventID: AEEventID {
        switch self {
        case .sleep: return AEEventID(kAESleep)
        case .restart: return AEEventID(kAERestart)
        case .shutDown: return AEEventID(kAEShutDown)
        case .logOut: return AEEventID(kAEReallyLogOut)
        }
    }

    func perform() {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.loginwindow")
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: eventID,
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        _ = try? event.sendEvent(options: [.noReply], timeout: 2)
    }
}
