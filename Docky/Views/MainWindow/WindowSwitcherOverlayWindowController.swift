//
//  WindowSwitcherOverlayWindowController.swift
//  Docky
//

import AppKit
import Combine
import Observation

/// Shows and hides the switcher without animation. The overlay orders in or
/// out in the same call that reveals or dismisses the switcher, and its cards
/// are built during the reveal delay, so the reveal has little left to lay out
/// or draw.
final class WindowSwitcherOverlayWindowController: NSWindowController {
    private weak var mainWindow: MainWindow?
    private let contentController: WindowSwitcherController
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
        self.contentController = contentController
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
        let service = WindowSwitcherService.shared
        // The hop to the main queue lets the press pick its first selection
        // before the cards are drawn.
        service.$isPresented
            .removeDuplicates()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.prepareOverlay()
            }
            .store(in: &cancellables)

        // No hop here: the service publishes on the main actor, so the overlay
        // appears and disappears within the call that changes `isRevealed`.
        // Dismissing therefore hides it before `confirmSelection` focuses the
        // chosen window. `@Published` sends before it stores, so these calls must
        // not read `isRevealed`.
        service.$isRevealed
            .removeDuplicates()
            .sink { [weak self] isRevealed in
                guard let self else { return }
                if isRevealed {
                    self.presentOverlay()
                } else {
                    self.hideOverlay()
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

    /// Builds this session's cards while the overlay is hidden. `viewWillAppear`
    /// still refreshes them, for selection moves and thumbnails that arrive
    /// during the delay and for reveals that come without this step.
    private func prepareOverlay() {
        let service = WindowSwitcherService.shared
        guard service.isPresented, !service.isRevealed, showsOverlayUI else { return }

        updateFrame()
        contentController.prepareForReveal()
    }

    private func presentOverlay() {
        guard let window else { return }

        guard showsOverlayUI else {
            hideOverlay()
            return
        }

        // Appear at once. The service's reveal delay already keeps a quick
        // tap from flashing the switcher, so a fade-in would only add lag.
        updateFrame()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Disappears at once: a fade-out would only delay the switch.
    private func hideOverlay() {
        window?.orderOut(nil)
    }

    private func prepareOverlayWindow() {
        guard let window else { return }

        updateFrame()
        window.collectionBehavior = preferences.windowSpaceBehavior.collectionBehavior(
            includesFullScreenAuxiliary: true)
        hideOverlay()
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

    private func refreshOverlayPresentation() {
        guard WindowSwitcherService.shared.isRevealed else {
            hideOverlay()
            return
        }

        presentOverlay()
    }

    private func updateFrame() {
        guard let window else { return }
        let screenFrame = mainWindow?.screen?.frame ?? NSScreen.main?.frame ?? .zero
        guard !screenFrame.isEmpty, window.frame != screenFrame else { return }
        window.setFrame(screenFrame, display: window.isVisible)
    }
}

private final class WindowSwitcherOverlayWindow: NSWindow {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        // No system animation when the window orders in or out.
        animationBehavior = .none
        // Set explicitly so the clear area outside the panel takes clicks,
        // which cancel the switcher. A hidden window gets no events anyway.
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
