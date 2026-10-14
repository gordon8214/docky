import AppKit
import Combine
import QuartzCore

final class WindowsTaskbarPanel: NSPanel {
    var acceptsKeys = true
    override var canBecomeKey: Bool { acceptsKeys }
    override var canBecomeMain: Bool { false }
}

/// Shared popup chrome and lifetime. Every monitor and visibility hold ends on dismissal.
@MainActor
final class WindowsTaskbarPopup {
    let panel: WindowsTaskbarPanel
    var onDismiss: (() -> Void)?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var observation: AnyCancellable?
    private weak var mainWindow: MainWindow?
    private var interactionToken: UUID?
    private var isPresented = false
    init(content: NSView, size: CGSize, acceptsKeys: Bool = true) {
        panel = WindowsTaskbarPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.acceptsKeys = acceptsKeys
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        let root = WindowsTaskbarPopupChrome(frame: CGRect(origin: .zero, size: size))
        let scroll = NSScrollView(frame: root.bounds.insetBy(dx: 8, dy: 8))
        scroll.autoresizingMask = [.width, .height]
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        content.frame = CGRect(origin: .zero, size: scroll.contentSize)
        scroll.documentView = content
        scroll.wantsLayer = true
        scroll.layer?.zPosition = 2
        root.addSubview(scroll)
        panel.initialFirstResponder = content
        panel.contentView = root
    }
    func present(from anchor: NSView, submenu: Bool = false, monitors: Bool = true) {
        guard let sourceWindow = anchor.window else { return }
        let source = sourceWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visible = sourceWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? source
        let size = CGSize(width: min(panel.frame.width, visible.width),
                          height: min(panel.frame.height, visible.height))
        panel.setContentSize(size)
        var origin = CGPoint(x: source.midX - size.width / 2, y: source.maxY + 8)
        if submenu { origin = CGPoint(x: source.maxX + 2, y: source.maxY - size.height) }
        if submenu, origin.x + size.width > visible.maxX { origin.x = source.minX - size.width - 2 }
        origin.x = max(visible.minX, min(origin.x, visible.maxX - size.width))
        origin.y = max(visible.minY, min(origin.y, visible.maxY - size.height))
        panel.setFrameOrigin(origin)
        panel.alphaValue = 0
        panel.orderFront(nil)
        if panel.acceptsKeys {
            panel.makeKey()
            panel.makeFirstResponder(panel.initialFirstResponder)
        }
        isPresented = true
        if monitors {
            mainWindow = NSApp.windows.compactMap { $0 as? MainWindow }.first
            interactionToken = mainWindow?.beginInteraction()
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [
                .leftMouseDown, .rightMouseDown, .keyDown
            ]) { [weak self] event in
                guard let self else { return event }
                if event.type == .keyDown, event.keyCode == 53 {
                    self.dismiss()
                    return nil
                }
                if event.type != .keyDown, !(event.window is WindowsTaskbarPanel) { self.dismiss() }
                return event
            }
            let outsideEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: outsideEvents) { [weak self] _ in
                self?.dismiss()
            }
            observation = observeChanges { [weak self] in
                if !WindowsTaskbarStyle.isActive { self?.dismiss() }
            }
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = WindowsTaskbarStyle.reducesMotion ? 0 : WindowsTaskbarStyle.popupDuration
            context.timingFunction = WindowsTaskbarStyle.timingFunction
            panel.animator().alphaValue = 1
        }
    }
    func dismiss() {
        guard isPresented else { return }
        isPresented = false
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        observation?.cancel()
        observation = nil
        mainWindow?.endInteraction(interactionToken)
        mainWindow = nil
        interactionToken = nil
        panel.orderOut(nil)
        onDismiss?()
    }
    isolated deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        mainWindow?.endInteraction(interactionToken)
    }
}

final class WindowsTaskbarPopupChrome: NSView {
    private let material = NSVisualEffectView()
    private let tint = CALayer()
    private var transparencyObservation: AnyCancellable?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        addSubview(material)
        tint.zPosition = 1
        layer?.addSublayer(tint)
        updatePalette()
        transparencyObservation = NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
        ).sink { [weak self] _ in self?.updatePalette() }
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        material.frame = bounds
        tint.frame = bounds
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updatePalette()
    }
    private func updatePalette() {
        let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        material.isHidden = opaque
        let color = WindowsTaskbarStyle.background(effectiveAppearance)
        tint.backgroundColor = color.withAlphaComponent(opaque ? 1 : 0.94).cgColor
        layer?.borderColor =
            WindowsTaskbarStyle.foreground(effectiveAppearance).withAlphaComponent(0.12).cgColor
    }
}

@MainActor
final class WindowsTaskbarTooltip {
    static let shared = WindowsTaskbarTooltip()
    private var task: Task<Void, Never>?
    private var popup: WindowsTaskbarPopup?
    private var sourceID: String?
    func schedule(for tile: NativeDockTileView) {
        dismiss()
        sourceID = tile.interaction.tile.id
        task = Task { @MainActor [weak self, weak tile] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, let tile, tile.interaction.isHovering,
                tile.window != nil, WindowsTaskbarStyle.isActive,
                !tile.interaction.isContextMenuPresented,
                WindowPreviewWindowController.shared.presentedSourceTileID != tile.interaction.tile.id,
                let title = tile.interaction.tooltipTitle
            else { return }
            let label = NSTextField(labelWithString: title)
            label.font = WindowsTaskbarStyle.font()
            label.textColor = WindowsTaskbarStyle.foreground(tile.effectiveAppearance)
            let size = CGSize(width: min(400, label.intrinsicContentSize.width + 20), height: 32)
            let popup = WindowsTaskbarPopup(content: label, size: size, acceptsKeys: false)
            self.popup = popup
            popup.present(from: tile, monitors: false)
        }
    }
    func dismiss(sourceID: String? = nil) {
        if let sourceID, self.sourceID != sourceID { return }
        task?.cancel()
        task = nil
        popup?.dismiss()
        popup = nil
        self.sourceID = nil
    }
}
