//
//  SmartOrganizeProgressChipWindowController.swift
//  Docky
//

import AppKit
import Combine
import Observation

final class SmartOrganizeProgressChipWindowController: NSWindowController {
    private weak var mainWindow: MainWindow?
    private var cancellables: Set<AnyCancellable> = []
    private var isInterruptingMainWindow = false
    private var interactionToken: UUID?
    private let chipGap: CGFloat = 10
    private let preferences = DockyPreferences.shared
    private let dockSettings = DockSettingsService.shared
    private let contentController = NativeProgressChipController()

    init(mainWindow: MainWindow) {
        self.mainWindow = mainWindow

        let chipWindow = SmartOrganizeProgressChipWindow()
        chipWindow.contentViewController = contentController

        super.init(window: chipWindow)

        prepareWindow()
        observeProgressPresentation()
        observeMainWindow()
        observeSpaceBehavior()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func prepareWindow() {
        guard let window else { return }
        window.collectionBehavior = preferences.windowSpaceBehavior.collectionBehavior(
            includesFullScreenAuxiliary: true)
        configureHiddenWindowState()
        updateFrame()
    }

    private func observeProgressPresentation() {
        SmartOrganizeProgressService.shared.$isPresented
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPresented in
                guard let self else { return }
                self.syncPresentation(isPresented: isPresented)
            }
            .store(in: &cancellables)

        SmartOrganizeProgressService.shared.$message
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFrame()
            }
            .store(in: &cancellables)
    }

    private func observeMainWindow() {
        NotificationCenter.default.publisher(for: .dockyVisibilityChanged, object: mainWindow)
            .merge(with: NotificationCenter.default.publisher(for: .dockyEnteredFullscreen, object: mainWindow))
            .sink { [weak self] _ in
                self?.syncPresentation(isPresented: SmartOrganizeProgressService.shared.isPresented)
            }
            .store(in: &cancellables)
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
            self?.window?.collectionBehavior = behavior.collectionBehavior(includesFullScreenAuxiliary: true)
        }
        .store(in: &cancellables)
    }

    private func syncPresentation(isPresented: Bool) {
        guard let window, let mainWindow else { return }
        guard isPresented, mainWindow.permitsPassivePresentation else {
            window.orderOut(nil)
            configureHiddenWindowState()
            endMainWindowInteraction()
            return
        }
        // Background progress must not hold a fullscreen edge reveal open.
        if !mainWindow.isFullscreenActive { beginMainWindowInteraction() }
        guard mainWindow.showsPassiveCompanions else { window.orderOut(nil); return }
        updateFrame()
        window.orderFront(nil)
        window.alphaValue = 1
    }

    private func updateFrame() {
        guard let window, let mainWindow else { return }
        contentController.view.layoutSubtreeIfNeeded()
        let contentSize = contentController.view.fittingSize
        let frameSize = NSSize(width: max(contentSize.width, 220), height: max(contentSize.height, 34))
        let screenVisibleFrame = mainWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        guard !screenVisibleFrame.isEmpty else { return }
        let position = preferences.effectiveWindowPosition.resolved(systemOrientation: dockSettings.orientation)

        let origin: CGPoint
        switch position {
        case .top:
            origin = CGPoint(
                x: mainWindow.frame.midX - frameSize.width / 2,
                y: mainWindow.frame.minY - frameSize.height - chipGap
            )
        case .left:
            origin = CGPoint(
                x: mainWindow.frame.maxX + chipGap,
                y: mainWindow.frame.midY - frameSize.height / 2
            )
        case .right:
            origin = CGPoint(
                x: mainWindow.frame.minX - frameSize.width - chipGap,
                y: mainWindow.frame.midY - frameSize.height / 2
            )
        case .bottom:
            origin = CGPoint(
                x: mainWindow.frame.midX - frameSize.width / 2,
                y: mainWindow.frame.maxY + chipGap
            )
        }

        let clampedOrigin = CGPoint(
            x: min(max(origin.x, screenVisibleFrame.minX + 8), screenVisibleFrame.maxX - frameSize.width - 8),
            y: min(max(origin.y, screenVisibleFrame.minY + 8), screenVisibleFrame.maxY - frameSize.height - 8)
        )

        window.setFrame(CGRect(origin: clampedOrigin, size: frameSize).integral, display: true)
    }

    private func configureHiddenWindowState() {
        guard let window else { return }
        window.alphaValue = 0
        window.ignoresMouseEvents = true
    }

    private func beginMainWindowInteraction() {
        guard !isInterruptingMainWindow else { return }
        isInterruptingMainWindow = true
        interactionToken = mainWindow?.beginInteraction()
    }

    private func endMainWindowInteraction() {
        guard isInterruptingMainWindow else { return }
        mainWindow?.endInteraction(interactionToken)
        isInterruptingMainWindow = false
    }
}

private final class SmartOrganizeProgressChipWindow: NSWindow {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
