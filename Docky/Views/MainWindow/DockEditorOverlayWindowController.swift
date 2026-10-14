import AppKit
import Combine

final class DockEditorOverlayWindowController: NSWindowController {
    private weak var mainWindow: MainWindow?
    private var cancellables: Set<AnyCancellable> = []
    private let overlayController = NativeDockEditorController()
    private let preferences = DockyPreferences.shared

    init(mainWindow: MainWindow) {
        self.mainWindow = mainWindow

        let overlayWindow = DockEditorOverlayWindow()
        let contentController = overlayController
        overlayWindow.contentViewController = contentController

        super.init(window: overlayWindow)

        observeEditMode()
        observeMainWindow()
        observeSpaceBehavior()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func observeEditMode() {
        DockEditModeService.shared.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                guard let self else { return }
                if isActive {
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

    private func observeSpaceBehavior() {
        observeChanges { [weak self] in
            let behavior = DockyPreferences.shared.windowSpaceBehavior
            self?.window?.collectionBehavior = behavior.collectionBehavior(includesFullScreenAuxiliary: false)
        }
        .store(in: &cancellables)
    }

    private func presentOverlay() {
        updateFrame()
        guard let window, let mainWindow else {
            return
        }

        window.level = NSWindow.Level.floating
        window.orderFront(nil)
        mainWindow.orderFrontRegardless()
    }

    private func dismissOverlay() {
        guard let window else {
            return
        }

        window.orderOut(nil)
    }

    private func updateFrame() {
        guard let window else {
            return
        }

        let screenFrame = mainWindow?.screen?.frame ?? NSScreen.main?.frame ?? .zero
        let position = preferences.windowPosition.resolved(systemOrientation: DockSettingsService.shared.orientation)
        let overlayFrame = insetOverlayFrame(screenFrame: screenFrame, position: position)

        if let mainWindow {
            let visibleDockFrame = mainWindow.frame.intersection(overlayFrame)
            if visibleDockFrame.isNull || visibleDockFrame.isEmpty {
                overlayController.dockFrame = .zero
            } else {
                overlayController.dockFrame =
                    CGRect(
                        x: visibleDockFrame.minX - overlayFrame.minX,
                        y: overlayFrame.maxY - visibleDockFrame.maxY,
                        width: visibleDockFrame.width,
                        height: visibleDockFrame.height
                    ).integral
            }
        } else {
            overlayController.dockFrame = .zero
        }

        window.setFrame(overlayFrame.integral, display: true)
    }

    private func insetOverlayFrame(screenFrame: CGRect, position: ResolvedDockWindowPosition) -> CGRect {
        guard let mainWindow else {
            return screenFrame
        }

        var frame = screenFrame
        let insetAmount = max(0, dockExtent(for: mainWindow.frame, position: position))

        switch position {
        case .bottom:
            frame.origin.y += insetAmount
            frame.size.height -= insetAmount
        case .top:
            frame.size.height -= insetAmount
        case .left:
            frame.origin.x += insetAmount
            frame.size.width -= insetAmount
        case .right:
            frame.size.width -= insetAmount
        }

        return frame
    }

    private func dockExtent(for frame: CGRect, position: ResolvedDockWindowPosition) -> CGFloat {
        switch position {
        case .bottom, .top:
            frame.height
        case .left, .right:
            frame.width
        }
    }
}

private final class DockEditorOverlayWindow: NSWindow {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
