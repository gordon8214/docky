//
//  WidgetSettingsPanelController.swift
//  Docky
//

import AppKit
import Observation

/// Borderless panel that can still become key so its text fields work.
private final class KeyableSettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class WidgetSettingsPanelController: NSObject {
    static let shared = WidgetSettingsPanelController()

    private static let contentWidth: CGFloat = 320
    private static let maxContentHeight: CGFloat = 440
    private static let edgeGap: CGFloat = 8

    private var panel: KeyableSettingsPanel?
    private var currentTileID: String?
    private var globalClickMonitor: Any?
    private var localEventMonitor: Any?
    private weak var heldMainWindow: MainWindow?
    private var interactionToken: UUID?

    private override init() { super.init() }

    /// `sourceFrame` is the tile's frame in MainWindow coordinates (the flipped Dock canvas).
    func present(widget: WidgetTile, tileID: String, sourceFrame: CGRect) {
        if currentTileID == tileID {
            dismiss()
            return
        }
        dismiss()

        let controller = NativeWidgetSettingsController(tileID: tileID, widget: widget)
        controller.onDone = { [weak self] in self?.dismiss() }
        let windowSize = CGSize(width: 380, height: 440)
        controller.view.frame = CGRect(origin: .zero, size: windowSize)

        let panel = KeyableSettingsPanel(
            contentRect: CGRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .mainMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentViewController = controller
        panel.delegate = self

        let origin = frameOrigin(for: windowSize, sourceFrame: sourceFrame)
        panel.setFrame(CGRect(origin: origin, size: windowSize), display: true)

        self.panel = panel
        self.currentTileID = tileID
        beginDockVisibilityHoldIfNeeded()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        installEventMonitors()
    }

    func dismiss() {
        removeEventMonitors()
        endDockVisibilityHoldIfNeeded()
        currentTileID = nil
        if let panel {
            panel.delegate = nil
            panel.orderOut(nil)
            panel.contentViewController = nil
            panel.contentView = nil
            panel.close()
        }
        panel = nil
    }

    private func installEventMonitors() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }

            if event.type == .keyDown {
                if event.keyCode == 53 {
                    self.dismiss()
                    return nil
                }
                return event
            }

            if event.window !== self.panel {
                self.dismiss()
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        globalClickMonitor = nil
        localEventMonitor = nil
    }

    private func beginDockVisibilityHoldIfNeeded() {
        guard heldMainWindow == nil,
            let mainWindow = NSApp.windows.compactMap({ $0 as? MainWindow }).first
        else {
            return
        }
        interactionToken = mainWindow.beginInteraction()
        heldMainWindow = mainWindow
    }

    private func endDockVisibilityHoldIfNeeded() {
        heldMainWindow?.endInteraction(interactionToken)
        heldMainWindow = nil
    }

    private func frameOrigin(for size: CGSize, sourceFrame originalSourceFrame: CGRect) -> CGPoint {
        let sourceFrame = convertToScreen(originalSourceFrame)
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(sourceFrame) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            return CGPoint(x: sourceFrame.midX - size.width / 2, y: sourceFrame.maxY)
        }

        return DockPresentationGeometry.origin(for: .init(size: size, source: sourceFrame, visible: visibleFrame,
            edge: DockyPreferences.shared.effectiveWindowPosition.resolved(
                systemOrientation: DockSettingsService.shared.orientation), gap: Self.edgeGap))
    }

    private func convertToScreen(_ frame: CGRect) -> CGRect {
        guard let dockFrame = NSApp.windows.compactMap({ $0 as? MainWindow }).first?.frame else {
            return frame
        }
        return CGRect(
            x: dockFrame.minX + frame.minX,
            y: dockFrame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private var dockEdge: NSRectEdge {
        let prefs = DockyPreferences.shared
        let settings = DockSettingsService.shared
        switch prefs.effectiveWindowPosition.resolved(systemOrientation: settings.orientation) {
        case .top: return .minY
        case .bottom: return .maxY
        case .left: return .maxX
        case .right: return .minX
        }
    }
}

extension WidgetSettingsPanelController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        dismiss()
    }
}
