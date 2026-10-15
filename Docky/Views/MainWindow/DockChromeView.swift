import AppKit
import QuartzCore

/// The taskbar's background: a blurred material, a tint, and a hairline top edge.
final class DockChromeView: NSView {
    private let tint = CALayer()
    private let windowsEdge = CALayer()
    private let windowsMaterial = NSVisualEffectView()
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        windowsMaterial.material = .hudWindow
        windowsMaterial.blendingMode = .behindWindow
        windowsMaterial.state = .active
        addSubview(windowsMaterial)
        tint.zPosition = 1
        windowsEdge.zPosition = 2
        layer?.addSublayer(tint)
        layer?.addSublayer(windowsEdge)
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }
    func refresh() {
        windowsMaterial.isHidden = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        needsLayout = true
    }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        windowsMaterial.frame = bounds
        tint.frame = bounds
        let color = WindowsTaskbarStyle.background(effectiveAppearance)
        tint.backgroundColor = color.withAlphaComponent(
            NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : color.alphaComponent).cgColor
        windowsEdge.frame = CGRect(
            x: 0, y: 0, width: bounds.width, height: 1 / (window?.backingScaleFactor ?? 2))
        let edgeColor = WindowsTaskbarStyle.foreground(effectiveAppearance).withAlphaComponent(0.12)
        windowsEdge.backgroundColor = edgeColor.cgColor
        CATransaction.commit()
    }
    private var windowsBackgroundActions: [ContextAction] {
        let preferences = DockyPreferences.shared
        return [
            .action("Activity Monitor") {
                let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
                NSWorkspace.shared.openApplication(at: url,
                                                   configuration: NSWorkspace.OpenConfiguration())
            },
            .action("Show Menu Extras", isOn: MenuExtrasNativeBridge.shared.enabled) {
                MenuExtrasNativeBridge.shared.enabled.toggle()
            },
            .action(String(localized: "Settings...")) { (NSApp.delegate as? AppDelegate)?.showSettingsWindow(nil) },
            .divider,
            .action(
                preferences.autohidesWindow
                    ? String(localized: "Turn Hiding Off") : String(localized: "Turn Hiding On")
            ) {
                preferences.autohidesWindow.toggle()
            },
            .action(String(localized: "Edit Taskbar...")) { DockEditModeService.shared.enter() },
            .submenu(
                String(localized: "Troubleshoot"),
                children: [
                    .action(String(localized: "Sync Dock")) {
                        DockSettingsService.shared.refresh()
                        TileStore.shared.refresh()
                    }
                ]),
            .divider,
            .action(String(localized: "About Docky")) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel(nil)
            },
            .action(String(localized: "Quit Docky"), isDestructive: true) { NSApp.terminate(nil) }
        ]
    }
    override func rightMouseDown(with event: NSEvent) {
        // Anchor at the pointer so the menu opens where the bar was clicked, not mid-bar.
        let point = convert(event.locationInWindow, from: nil)
        ContextActionMenuPresenter.popUpMenu(
            actions: windowsBackgroundActions, from: self,
            anchorRect: CGRect(x: point.x, y: bounds.minY, width: 1, height: bounds.height))
    }
}
