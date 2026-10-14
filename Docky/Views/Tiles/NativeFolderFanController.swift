import AppKit
import QuartzCore

/// Bottom-anchored fan with the original icon spacing and staggered expansion.
final class NativeFolderFanController: NSWindowController {
    private weak var anchor: NSView?
    private let rows: [NSView]
    private let targets: [CGRect]
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var previewTasks: [Task<Void, Never>] = []
    private let openedAt = ProcessInfo.processInfo.systemUptime
    private var isClosing = false
    var onClose: (() -> Void)?
    init(anchor: NSView, items: [URL], iconSize: CGFloat) {
        self.anchor = anchor
        let content = NSView()
        let size = CGSize(width: 148 + iconSize, height: iconSize * CGFloat(items.count) + 8)
        content.frame = CGRect(origin: .zero, size: size)
        var targets: [CGRect] = []
        var rows: [NSView] = []
        for (index, url) in items.enumerated() {
            let button = NativeActionButton(FileManager.default.displayName(atPath: url.path)) {
                NSWorkspace.shared.open(url)
            }
            button.image = IconCacheService.shared.cachedPreviewThumbnail(
                forFileURL: url, maxPixelSize: IconCacheService.tileThumbnailPixelExtent)
                ?? IconCacheService.shared.icon(forFileURL: url)
            button.imagePosition = .imageTrailing
            button.imageScaling = .scaleProportionallyDown
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.85).cgColor
            button.layer?.cornerRadius = 10
            button.frame = CGRect(x: 0, y: 4, width: size.width, height: iconSize)
            button.alphaValue = 0
            content.addSubview(button, positioned: .below, relativeTo: content.subviews.first)
            targets.append(CGRect(x: 0, y: 4 + iconSize * CGFloat(index), width: size.width, height: iconSize))
            rows.append(button)
        }
        self.rows = rows
        self.targets = targets
        let panel = NativeFolderFanPanel(
            contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .mainMenu
        panel.isReleasedWhenClosed = false
        panel.contentView = content
        super.init(window: panel)
        for case let button as NativeActionButton in rows {
            let action = button.handler
            button.handler = { [weak self] in
                action?()
                self?.dismiss()
            }
        }
        loadPreviews(items)
    }
    private func loadPreviews(_ items: [URL]) {
        for (url, row) in zip(items, rows) {
            guard let button = row as? NSButton else { continue }
            previewTasks.append(Task { [weak button] in
                let image = await IconCacheService.shared.loadPreviewThumbnailAsync(
                    forFileURL: url, maxPixelSize: IconCacheService.tileThumbnailPixelExtent)
                guard !Task.isCancelled, let image else { return }
                button?.image = image
            })
        }
    }
    required init?(coder: NSCoder) { nil }
    isolated deinit {
        for task in previewTasks { task.cancel() }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    }
    func present() {
        guard let anchor, let parent = anchor.window, let window else { return }
        let source = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visible = parent.screen?.visibleFrame ?? source
        let width = window.frame.width
        let origin = CGPoint(
            x: min(max(source.midX - width + (targets.first?.height ?? 0) / 2, visible.minX), visible.maxX - width),
            y: source.maxY + 8)
        window.setFrameOrigin(origin)
        parent.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for (index, row) in rows.enumerated() {
            if reduced {
                row.frame = targets[index]
                row.alphaValue = 1
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25 + Double(index) * 0.02
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    row.animator().frame = targets[index]
                    row.animator().alphaValue = 1
                }
            }
        }
        let localEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .keyDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: localEvents) { [weak self] event in
            guard let self, event.timestamp >= self.openedAt else { return event }
            if event.type == .keyDown && event.keyCode == 53 {
                self.dismiss()
                return nil
            }
            if event.type != .keyDown && event.window !== self.window { self.dismiss() }
            return event
        }
        let globalEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: globalEvents) { [weak self] _ in self?.dismiss()
        }
    }
    func dismiss() {
        guard !isClosing else { return }
        isClosing = true
        for task in previewTasks { task.cancel() }
        previewTasks.removeAll()
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.2
            for row in self.rows {
                row.animator().alphaValue = 0
                row.animator().setFrameOrigin(CGPoint(x: 0, y: 4))
            }
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if let window = self.window {
                    window.parent?.removeChildWindow(window)
                    window.orderOut(nil)
                }
                self.onClose?()
            }
        }
    }
}
private final class NativeFolderFanPanel: NSPanel { override var canBecomeKey: Bool { true } }
