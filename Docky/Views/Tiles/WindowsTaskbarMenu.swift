import AppKit

@MainActor
final class WindowsTaskbarMenu {
    private static var current: WindowsTaskbarMenu?
    static func install() {
        ContextActionMenuPresenter.customPresenter = { actions, anchor, changed in
            guard WindowsTaskbarStyle.isActive else { return false }
            show(actions: actions, from: anchor, onPresentationChanged: changed)
            return true
        }
    }
    private var popup: WindowsTaskbarPopup?
    private var child: WindowsTaskbarMenu?
    private var onPresentationChanged: (Bool) -> Void = { _ in }
    static func show(
        actions: [ContextAction], from anchor: NSView, onPresentationChanged: @escaping (Bool) -> Void
    ) {
        current?.dismiss()
        WindowsTaskbarTooltip.shared.dismiss()
        let menu = WindowsTaskbarMenu()
        current = menu
        menu.onPresentationChanged = onPresentationChanged
        menu.present(actions: actions, from: anchor)
    }
    private func present(actions: [ContextAction], from anchor: NSView, submenu: Bool = false) {
        let content = WindowsMenuContent(actions: actions)
        content.onAction = { [weak self] action, row in self?.activate(action, from: row) }
        content.onEscape = { [weak self] in self?.dismiss() }
        popup = WindowsTaskbarPopup(content: content, size: content.desiredSize)
        popup?.onDismiss = { [weak self] in
            self?.child?.dismiss()
            self?.child = nil
            self?.onPresentationChanged(false)
            self?.popup = nil
            if Self.current === self { Self.current = nil }
        }
        onPresentationChanged(true)
        popup?.present(from: anchor, submenu: submenu)
    }
    private func activate(_ action: ContextAction, from row: NSView) {
        switch action.kind {
        case .submenu, .lazySubmenu:
            child?.dismiss()
            let children = action.kind == .submenu ? action.children : action.childrenProvider?() ?? []
            guard !children.isEmpty else { return }
            let menu = WindowsTaskbarMenu()
            child = menu
            menu.present(actions: children, from: row, submenu: true)
        case .action:
            Self.current?.dismiss()
            action.handler()
        case .share(let url):
            let picker = NSSharingServicePicker(items: [url])
            picker.show(relativeTo: row.bounds, of: row, preferredEdge: .maxY)
        case .customView, .divider: break
        }
    }
    func dismiss() {
        child?.dismiss()
        child = nil
        popup?.dismiss()
        popup = nil
    }
}

final class WindowsMenuContent: NSView {
    var onAction: ((ContextAction, NSView) -> Void)?
    var onEscape: (() -> Void)?
    private let actions: [ContextAction]
    private var buttons: [WindowsMenuRow] = []
    private var selectedIndex = 0
    private var hoverTask: Task<Void, Never>?
    let desiredSize: CGSize
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(actions: [ContextAction]) {
        self.actions = actions
        let titleWidth = max(
            220,
            min(
                420,
                (actions.map { action in
                    (action.title as NSString).size(withAttributes: [.font: WindowsTaskbarStyle.font()]).width
                        + 64
                }.max() ?? 220)))
        let width = max(titleWidth, (actions.compactMap { $0.customView?.frame.width }.max() ?? 0) + 16)
        let height = actions.reduce(CGFloat(16)) { total, action in
            total
                + (action.kind == .divider
                    ? 9 : action.kind == .customView ? max(32, action.customView?.frame.height ?? 32) : 32)
        }
        desiredSize = CGSize(width: width, height: height)
        super.init(frame: CGRect(origin: .zero, size: desiredSize))
        var offset: CGFloat = 0
        for action in actions {
            if action.kind == .divider {
                let line = NSBox(frame: CGRect(x: 4, y: offset + 4, width: width - 24, height: 1))
                line.boxType = .separator
                addSubview(line)
                offset += 9
            } else if action.kind == .customView, let custom = action.customView {
                custom.frame.origin = CGPoint(x: 0, y: offset)
                addSubview(custom)
                offset += max(32, custom.frame.height)
            } else {
                let button = WindowsMenuRow(action: action)
                button.frame = CGRect(x: 0, y: offset, width: width - 16, height: 32)
                button.onActivate = { [weak self, weak button] in
                    guard let button else { return }
                    self?.onAction?(action, button)
                }
                button.onHover = { [weak self, weak button] in
                    guard let self, let button else { return }
                    self.hover(action: action, button: button)
                }
                button.onHoverEnd = { [weak self] in self?.cancelPendingHover() }
                buttons.append(button)
                addSubview(button)
                offset += 32
            }
        }
    }
    required init?(coder: NSCoder) { nil }
    isolated deinit { hoverTask?.cancel() }
    private func cancelPendingHover() {
        hoverTask?.cancel()
        hoverTask = nil
    }
    private func hover(action: ContextAction, button: WindowsMenuRow) {
        guard let index = buttons.firstIndex(of: button) else { return }
        select(index)
        if action.kind == .submenu || action.kind == .lazySubmenu {
            hoverTask = Task { @MainActor [weak self, weak button] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, let self, let button,
                    button.isHovered, self.buttons.indices.contains(self.selectedIndex),
                    self.buttons[self.selectedIndex] === button else { return }
                self.onAction?(action, button)
            }
        }
    }
    func select(_ index: Int) {
        cancelPendingHover()
        guard !buttons.isEmpty else { return }
        selectedIndex = (index + buttons.count) % buttons.count
        for (offset, button) in buttons.enumerated() { button.isSelected = offset == selectedIndex }
        buttons[selectedIndex].scrollToVisible(buttons[selectedIndex].bounds)
    }
    override func keyDown(with event: NSEvent) {
        cancelPendingHover()
        switch event.keyCode {
        case 125: select(selectedIndex + 1)
        case 126: select(selectedIndex - 1)
        case 36, 49: if !buttons.isEmpty { buttons[selectedIndex].onActivate?() }
        case 124:
            guard !buttons.isEmpty else { return }
            let row = buttons[selectedIndex]
            if row.action.kind == .submenu || row.action.kind == .lazySubmenu { row.onActivate?() }
        case 53, 123: onEscape?()
        default: super.keyDown(with: event)
        }
    }
}

final class WindowsMenuRow: NSView {
    let action: ContextAction
    var onActivate: (() -> Void)?
    var onHover: (() -> Void)?
    var onHoverEnd: (() -> Void)?
    private(set) var isHovered = false
    var isSelected = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    init(action: ContextAction) {
        self.action = action
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(action.title)
        setAccessibilityValue(action.isOn ? "Checked" : "")
    }
    required init?(coder: NSCoder) { nil }
    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(
            rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self)
        if let tracking { addTrackingArea(tracking) }
    }
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        onHover?()
    }
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        onHoverEnd?()
    }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onActivate?() }
    }
    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            WindowsTaskbarStyle.highlight(effectiveAppearance).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
        let color =
            action.isDestructive ? NSColor.systemRed : WindowsTaskbarStyle.foreground(effectiveAppearance)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: WindowsTaskbarStyle.font(), .foregroundColor: color
        ]
        (action.title as NSString).draw(at: CGPoint(x: 32, y: 8), withAttributes: attrs)
        action.image?.draw(
            in: CGRect(x: 8, y: 8, width: 16, height: 16), from: .zero,
            operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        if action.isOn { ("✓" as NSString).draw(at: CGPoint(x: 8, y: 8), withAttributes: attrs) }
        if action.kind == .submenu || action.kind == .lazySubmenu {
            ("›" as NSString).draw(at: CGPoint(x: bounds.width - 18, y: 7), withAttributes: attrs)
        }
    }
}
