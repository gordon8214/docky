//
//  LaunchpadOverlayWindowController.swift
//  Docky
//

import AppKit
import Combine
import Observation

final class LaunchpadOverlayWindowController: NSWindowController {
    private weak var mainWindow: MainWindow?
    private var cancellables: Set<AnyCancellable> = []
    private var isInterruptingMainWindow = false
    private let animationDuration: TimeInterval = 0.18
    private let preferences = DockyPreferences.shared
    /// The screen the launchpad is currently anchored to. Resolved at present
    /// time from the cursor location so the overlay always opens on the
    /// display the user is looking at.
    private weak var anchoredScreen: NSScreen?

    init(mainWindow: MainWindow) {
        self.mainWindow = mainWindow

        let overlayWindow = LaunchpadOverlayWindow()
        let contentController = NativeLaunchpadController()
        overlayWindow.contentViewController = contentController

        super.init(window: overlayWindow)

        prepareOverlayWindow()
        observeOverlayPresentation()
        observeMainWindow()
        observeSpaceBehavior()
        observeAppActivation()
    }

    /// Cmd+Tab (and any other path that puts another app frontmost) takes
    /// focus away from Docky, so the launchpad — which presented itself by
    /// activating Docky — should dismiss to match the user's intent.
    private func observeAppActivation() {
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                guard LaunchpadOverlayService.shared.isPresented else { return }
                LaunchpadOverlayService.shared.dismiss()
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func observeOverlayPresentation() {
        LaunchpadOverlayService.shared.$isPresented
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPresented in
                guard let self else { return }
                if isPresented {
                    self.presentOverlay()
                } else {
                    self.dismissOverlay()
                }
            }
            .store(in: &cancellables)
    }

    private func observeMainWindow() {
        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: mainWindow)
            .merge(with: NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: mainWindow))
            .merge(
                with: NotificationCenter.default.publisher(
                    for: NSWindow.didChangeScreenNotification, object: mainWindow)
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFrame()
            }
            .store(in: &cancellables)
    }

    private func presentOverlay() {
        guard let window else { return }

        anchoredScreen = screenForCursor()
        updateWallpaper(for: anchoredScreen)
        updateFrame()
        beginMainWindowInteraction()
        window.ignoresMouseEvents = false
        window.makeKeyAndOrderFront(nil)
        animateWindowAlpha(to: 1)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func screenForCursor() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? mainWindow?.screen
            ?? NSScreen.main
    }

    private func updateWallpaper(for screen: NSScreen?) {
        let url = screen.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        if LaunchpadOverlayService.shared.wallpaperURL != url {
            LaunchpadOverlayService.shared.wallpaperURL = url
        }
    }

    private func dismissOverlay() {
        animateWindowAlpha(to: 0) { [weak self] in
            guard let self, let window = self.window else { return }

            window.ignoresMouseEvents = true
            window.orderOut(nil)
            self.mainWindow?.makeKey()
        }
        endMainWindowInteraction()
    }

    private func prepareOverlayWindow() {
        guard let window else { return }

        updateFrame()
        window.collectionBehavior = preferences.windowSpaceBehavior.collectionBehavior(
            includesFullScreenAuxiliary: true)
        configureHiddenWindowState()
    }

    private func observeSpaceBehavior() {
        observeChanges { [weak self] in
            let behavior = DockyPreferences.shared.windowSpaceBehavior
            self?.window?.collectionBehavior = behavior.collectionBehavior(includesFullScreenAuxiliary: true)
        }
        .store(in: &cancellables)
    }

    private func configureHiddenWindowState() {
        guard let window else { return }

        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.orderOut(nil)
    }

    private func animateWindowAlpha(to alphaValue: CGFloat, completion: (@MainActor () -> Void)? = nil) {
        guard let window else {
            completion?()
            return
        }

        window.animator().alphaValue = window.alphaValue

        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = alphaValue
        } completionHandler: {
            Task { @MainActor in
                completion?()
            }
        }
    }

    private func updateFrame() {
        guard let window else { return }
        let screenFrame =
            anchoredScreen?.frame
            ?? mainWindow?.screen?.frame
            ?? NSScreen.main?.frame
            ?? .zero
        guard !screenFrame.isEmpty else { return }
        window.setFrame(screenFrame, display: window.isVisible)
    }

    private func beginMainWindowInteraction() {
        guard !isInterruptingMainWindow else { return }
        mainWindow?.beginInteraction()
        isInterruptingMainWindow = true
    }

    private func endMainWindowInteraction() {
        guard isInterruptingMainWindow else { return }
        mainWindow?.endInteraction()
        isInterruptingMainWindow = false
    }
}

private final class LaunchpadOverlayWindow: NSWindow {
    private let backgroundBlurRadius = 40

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        super.order(place, relativeTo: otherWin)
        applyBackgroundBlur()
    }

    /// Mirrors `MainWindow.applyBackgroundBlur` so the launchpad overlay rides
    /// the same private SkyLight backdrop blur as the dock chrome. Applied on
    /// every order — the window number is only valid once the window is on
    /// screen, and `orderOut` invalidates it.
    private func applyBackgroundBlur() {
        guard windowNumber > 0 else { return }
        _ = CGSSetWindowBackgroundBlurRadius(
            CGSMainConnectionID(),
            windowNumber,
            backgroundBlurRadius
        )
    }
}

/// Live state for an in-flight Launchpad drag. The display layer
/// reorders entries based on `targetIndex` so siblings shift to make
/// way as the cursor moves; the dragged tile renders both as a
/// translucent placeholder in its preview slot and as a floating
/// copy that follows the cursor.
