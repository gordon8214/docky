//
//  WindowSwitcherOverlayWindowController.swift
//  Docky
//

import AppKit
import Combine
import Observation

final class WindowSwitcherOverlayWindowController: NSWindowController {
    private weak var mainWindow: MainWindow?
    private var cancellables: Set<AnyCancellable> = []
    private let preferences = DockyPreferences.shared

    private var showsOverlayUI: Bool {
        // Empty state — there's nothing to focus-preview, so we need the
        // overlay to render the "No windows available" message.
        if WindowSwitcherService.shared.windows.isEmpty {
            return true
        }

        // Instant Focus waits for release before focusing a window on another
        // Space, so the switcher shows which window is selected meanwhile.
        if WindowSwitcherService.shared.defersSelectionFocus {
            return true
        }

        // Instant Focus brings each selected window forward instead, which
        // needs captures; without Screen Recording the switcher stays visible.
        guard preferences.showsWindowSwitcherFocusPreview,
            preferences.windowSwitcherPreviewMode == .instantFocus,
            PermissionsService.shared.screenCapture == .granted
        else {
            return true
        }

        return false
    }

    init(mainWindow: MainWindow) {
        self.mainWindow = mainWindow

        let overlayWindow = WindowSwitcherOverlayWindow()
        let contentController = WindowSwitcherController()
        overlayWindow.contentViewController = contentController

        super.init(window: overlayWindow)

        prepareOverlayWindow()
        observeOverlayPresentation()
        observeMainWindow()
        observeSpaceBehavior()
        observePreviewMode()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func observeOverlayPresentation() {
        WindowSwitcherService.shared.$isRevealed
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRevealed in
                guard let self else { return }
                if isRevealed {
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

        guard showsOverlayUI else {
            configureHiddenWindowState()
            return
        }

        updateFrame()
        // Appear at once. The service's reveal delay already keeps a quick
        // tap from flashing the switcher, so a fade-in would only add lag.
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismissOverlay() {
        guard showsOverlayUI else {
            configureHiddenWindowState()
            return
        }

        animateWindowAlpha(to: 0) { [weak self] in
            // A new session may have revealed the switcher during the fade.
            guard let self, let window = self.window, !WindowSwitcherService.shared.isRevealed else { return }

            window.ignoresMouseEvents = true
            window.orderOut(nil)
        }
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

    private func observePreviewMode() {
        observeChanges { [weak self] in
            _ = DockyPreferences.shared.showsWindowSwitcherFocusPreview
            _ = DockyPreferences.shared.windowSwitcherPreviewMode
            self?.refreshOverlayPresentation()
        }
        .store(in: &cancellables)

        PermissionsService.shared.$screenCapture
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshOverlayPresentation()
            }
            .store(in: &cancellables)

        WindowSwitcherService.shared.$defersSelectionFocus
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshOverlayPresentation()
            }
            .store(in: &cancellables)
    }

    private func configureHiddenWindowState() {
        guard let window else { return }

        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.orderOut(nil)
    }

    private func refreshOverlayPresentation() {
        guard WindowSwitcherService.shared.isRevealed else {
            configureHiddenWindowState()
            return
        }

        if showsOverlayUI {
            presentOverlay()
        } else {
            configureHiddenWindowState()
        }
    }

    private func updateFrame() {
        guard let window else { return }
        let screenFrame = mainWindow?.screen?.frame ?? NSScreen.main?.frame ?? .zero
        guard !screenFrame.isEmpty else { return }
        window.setFrame(screenFrame, display: window.isVisible)
    }

    private func animateWindowAlpha(to alphaValue: CGFloat, completion: (@MainActor () -> Void)? = nil) {
        guard let window else {
            completion?()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = WindowsTaskbarStyle.reducesMotion ? 0 : WindowsTaskbarStyle.popupDuration
            context.timingFunction = WindowsTaskbarStyle.timingFunction
            window.animator().alphaValue = alphaValue
        } completionHandler: {
            Task { @MainActor in
                completion?()
            }
        }
    }
}

private final class WindowSwitcherOverlayWindow: NSWindow {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
