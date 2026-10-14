import AppKit
import Combine

final class WindowsWindowPreviewController: NSViewController {
    var onHover: ((Bool) -> Void)?
    private var subscriptions = Set<AnyCancellable>()
    private var selectedIndex = 0
    override func loadView() {
        let root = WindowsPreviewContent()
        root.onHover = { [weak self] in self?.onHover?($0) }
        root.onKey = { [weak self] in self?.handleKey($0) }
        view = root
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        for publisher in [
            WindowPreviewService.shared.objectWillChange, WindowRegistry.shared.objectWillChange
        ] {
            publisher.sink { [weak self] in DispatchQueue.main.async { self?.refresh() } }.store(
                in: &subscriptions)
        }
        refresh()
    }
    private func refresh() {
        let windows = WindowPreviewService.shared.windows
        if windows.isEmpty {
            WindowPreviewWindowController.shared.dismissCurrent()
            return
        }
        view.subviews.forEach { $0.removeFromSuperview() }
        let scroll = NSScrollView(frame: view.bounds.insetBy(dx: 8, dy: 8))
        scroll.autoresizingMask = [.width, .height]
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = windows.count > 4
        let document = WindowsPreviewContent(
            frame: CGRect(x: 0, y: 0, width: CGFloat(windows.count) * 228, height: 180))
        for (index, window) in windows.enumerated() {
            let card = WindowsPreviewCard(window: window)
            card.frame = CGRect(x: CGFloat(index) * 228, y: 0, width: 220, height: 180)
            card.onConfirm = { WindowPreviewWindowController.shared.confirm(window) }
            card.onClose = {
                if WorkspaceService.shared.close(window: window) {
                    WindowPreviewService.shared.removeWindow(withIdentifier: window.windowIdentifier)
                }
            }
            document.addSubview(card)
        }
        scroll.documentView = document
        view.addSubview(scroll)
        selectedIndex = min(selectedIndex, max(0, windows.count - 1))
        updateSelection()
    }
    private func handleKey(_ event: NSEvent) {
        let windows = WindowPreviewService.shared.windows
        guard !windows.isEmpty else { return }
        switch event.keyCode {
        case 123: selectedIndex = (selectedIndex + windows.count - 1) % windows.count
        case 124: selectedIndex = (selectedIndex + 1) % windows.count
        case 36: WindowPreviewWindowController.shared.confirm(windows[selectedIndex])
        case 51:
            let window = windows[selectedIndex]
            if WorkspaceService.shared.close(window: window) {
                WindowPreviewService.shared.removeWindow(withIdentifier: window.windowIdentifier)
            }
        case 53: WindowPreviewWindowController.shared.dismissCurrent()
        default: break
        }
        updateSelection()
    }
    private func updateSelection() {
        guard let scroll = view.subviews.first as? NSScrollView else { return }
        for (index, card) in (scroll.documentView?.subviews ?? []).enumerated() {
            card.wantsLayer = true
            card.layer?.borderWidth = index == selectedIndex ? 1 : 0
            card.layer?.borderColor = WindowsTaskbarStyle.accent(view.effectiveAppearance).cgColor
            if index == selectedIndex { card.scrollToVisible(card.bounds) }
        }
    }
}

final class WindowsPreviewContent: NSView {
    var onHover: ((Bool) -> Void)?
    var onKey: ((NSEvent) -> Void)?
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { onKey?(event) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(
            rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self)
        if let tracking { addTrackingArea(tracking) }
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func draw(_ dirtyRect: NSRect) {
        WindowsTaskbarStyle.background(effectiveAppearance).withAlphaComponent(
            NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 0.97
        ).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }
}

final class WindowsPreviewCard: NSView {
    var onConfirm: (() -> Void)?
    var onClose: (() -> Void)?
    private let appWindow: AppWindow
    private let title = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let image = NSImageView()
    private let closeButton = NSButton(title: "×", target: nil, action: nil)
    override var isFlipped: Bool { true }
    init(window: AppWindow) {
        appWindow = window
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        title.stringValue = window.windowTitle
        title.font = WindowsTaskbarStyle.font()
        title.lineBreakMode = .byTruncatingTail
        title.textColor = WindowsTaskbarStyle.foreground(effectiveAppearance)
        icon.image = IconCacheService.shared.icon(forBundleIdentifier: window.bundleIdentifier)
        image.image =
            WindowPreviewService.shared.windowPreview(for: window)
            ?? IconCacheService.shared.icon(forBundleIdentifier: window.bundleIdentifier)
        image.imageScaling = .scaleProportionallyUpOrDown
        closeButton.isBordered = false
        closeButton.font = WindowsTaskbarStyle.font(size: 20)
        closeButton.target = self
        closeButton.action = #selector(closeWindow)
        closeButton.setAccessibilityLabel("Close \(window.windowTitle)")
        for child in [title, icon, image, closeButton] { addSubview(child) }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(window.windowTitle)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        icon.frame = CGRect(x: 8, y: 8, width: 16, height: 16)
        title.frame = CGRect(x: 30, y: 8, width: max(0, bounds.width - 66), height: 18)
        closeButton.frame = CGRect(x: bounds.width - 32, y: 2, width: 28, height: 28)
        image.frame = CGRect(
            x: 8, y: 34, width: max(0, bounds.width - 16), height: max(0, bounds.height - 42))
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        title.textColor = WindowsTaskbarStyle.foreground(effectiveAppearance)
        closeButton.contentTintColor = title.textColor
    }
    @objc private func closeWindow() { onClose?() }
    override func accessibilityPerformPress() -> Bool {
        onConfirm?()
        return true
    }
    override func mouseUp(with event: NSEvent) { onConfirm?() }
    override func rightMouseDown(with event: NSEvent) {
        let window = appWindow
        let sourceID = WindowPreviewWindowController.shared.presentedSourceTileID
        let actions =
            [
                ContextAction.action("Focus Window") { WindowPreviewWindowController.shared.confirm(window) },
                .action("Close Window", isDestructive: true) {
                    if WorkspaceService.shared.close(window: window) {
                        WindowPreviewService.shared.removeWindow(withIdentifier: window.windowIdentifier)
                    }
                }
            ]
            + windowMenuContextActions(for: appWindow) {
                WindowPreviewWindowController.shared.dismissCurrent()
            }
        ContextActionMenuPresenter.popUpMenu(actions: actions, from: self, onPresentationChanged: { presented in
            guard let sourceID else { return }
            WindowPreviewWindowController.shared.contextMenuPresentationChanged(presented, sourceTileID: sourceID)
        })
    }
}
