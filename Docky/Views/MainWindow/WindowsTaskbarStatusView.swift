import AppKit
import Combine

final class WindowsTaskbarStatusView: NSView {
    var extraTiles: [Tile] = [] {
        didSet {
            overflow.isHidden = extraTiles.isEmpty
            needsLayout = true
        }
    }
    /// Highlights the overflow button while a drag will drop into the tray.
    var isDropTarget: Bool {
        get { overflow.isDropTarget }
        set { overflow.isDropTarget = newValue }
    }
    var calendarTile: Tile?
    /// The Trash tile the tray's Trash button stands for. Nil hides the button,
    /// as when Shelve mode hides Trash.
    var trashTile: Tile? {
        didSet {
            guard trashTile?.id != oldValue?.id else { return }
            trash.isHidden = trashTile == nil
            needsLayout = true
        }
    }
    /// Highlights the Trash button while a drag will drop onto it.
    var isTrashDropTarget: Bool {
        get { trash.isDropTarget }
        set { trash.isDropTarget = newValue }
    }
    var metrics = WindowsTaskbarMetrics.standard {
        didSet {
            guard metrics != oldValue else { return }
            for button in [overflow, trash, clock] { button.metrics = metrics }
            menuExtras.metrics = metrics
            needsLayout = true
        }
    }
    private let overflow = WindowsStatusButton(glyph: "overflow", label: "Show additional Dock items")
    private let trash = WindowsStatusButton(glyph: "trash", label: String(localized: "Trash"))
    private let clock = WindowsStatusButton(glyph: "clock", label: "Date and time")
    private let menuExtras = WindowsMenuExtrasView()
    private let ownerID = UUID()
    private var subscriptions = Set<AnyCancellable>()
    private var popup: WindowsTaskbarPopup?
    override var isFlipped: Bool { true }
    var preferredWidth: CGFloat {
        (extraTiles.isEmpty ? 0 : metrics.overflowWidth) + (trashTile == nil ? 0 : metrics.overflowWidth)
            + menuExtras.preferredWidth + metrics.clockWidth + metrics.margin
    }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for button in [overflow, trash, clock] { addSubview(button) }
        overflow.isHidden = extraTiles.isEmpty
        trash.isHidden = true
        trash.isDestructive = true
        updateTrash(isEmpty: TrashService.shared.isEmpty)
        addSubview(menuExtras)
        overflow.onActivate = { [weak self] in self?.showExtras() }
        trash.onActivate = { Task { await FileBrowserService.shared.openTrash() } }
        trash.contextActions = { [weak self] in
            guard let tile = self?.trashTile else { return [] }
            return DockTileInteraction(
                tile: tile, isDragging: false, isDocumentDropTarget: false, isAppFolderDropTarget: false,
                isTrashDropTarget: false, renderedTileSize: nil
            ).contextActions(modifierFlags: [])
        }
        clock.onActivate = { [weak self] in self?.showCalendar() }
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        subscriptions.removeAll()
        if window == nil {
            WindowsTaskbarStatusService.shared.detach(ownerID)
            dismissPopup()
            return
        }
        WindowsTaskbarStatusService.shared.attach(ownerID)
        observeChanges { [weak self] in
            _ = WindowsTaskbarStatusService.shared.now
            _ = MenuExtrasService.shared.items
            _ = MenuExtrasNativeBridge.shared.enabled
            _ = MenuExtrasNativeBridge.shared.hostedIDs
            self?.refresh()
        }.store(in: &subscriptions)
        // Tracks the user's Trash icons; the sink below tracks whether Trash is empty.
        observeChanges { [weak self] in
            self?.updateTrash(isEmpty: TrashService.shared.isEmpty)
        }.store(in: &subscriptions)
        TrashService.shared.$isEmpty.sink { [weak self] isEmpty in
            self?.updateTrash(isEmpty: isEmpty)
        }.store(in: &subscriptions)
        refresh()
    }
    private func updateTrash(isEmpty: Bool) {
        let state: TrashIconState = isEmpty ? .empty : .full
        trash.image =
            DockyPreferences.shared.effectiveTrashIconOverrideURL(forState: state)
            .flatMap { IconCacheService.shared.image(forImageFileURL: $0) }
            ?? NSImage(named: state.systemImageName)
        trash.setAccessibilityValue(state.title)
    }
    func refresh() {
        let status = WindowsTaskbarStatusService.shared
        let time = DateFormatter()
        time.timeStyle = .short
        let date = DateFormatter()
        date.dateStyle = .short
        clock.clockText = time.string(from: status.now) + "\n" + date.string(from: status.now)
        clock.setAccessibilityLabel(clock.clockText.replacingOccurrences(of: "\n", with: ", "))
        needsLayout = true
        superview?.needsLayout = true
    }
    override func layout() {
        super.layout()
        let inset = metrics.inset
        let height = metrics.buttonSize
        var offset: CGFloat = overflow.isHidden ? 0 : metrics.overflowWidth
        overflow.frame = CGRect(x: 0, y: inset, width: metrics.overflowWidth, height: height)
        trash.frame = CGRect(x: offset, y: inset, width: metrics.overflowWidth, height: height)
        if !trash.isHidden { offset += metrics.overflowWidth }
        let extrasWidth = min(menuExtras.preferredWidth,
                              max(0, bounds.width - preferredWidth + menuExtras.preferredWidth))
        menuExtras.frame = CGRect(x: offset, y: inset, width: extrasWidth, height: height)
        offset += extrasWidth
        clock.frame = CGRect(x: offset, y: inset, width: metrics.clockWidth, height: height)
    }
    /// The Trash button's frame in `view`'s coordinates, or nil while it's hidden.
    func trashFrame(in view: NSView) -> CGRect? {
        guard !trash.isHidden else { return nil }
        layoutSubtreeIfNeeded()
        return view.convert(trash.bounds, from: trash)
    }
    func dismissPopup() {
        popup?.dismiss()
        popup = nil
    }
    private func showExtras() {
        if popup != nil {
            dismissPopup()
            return
        }
        let root = WindowsTaskbarExtraContent(tiles: extraTiles)
        let popup = WindowsTaskbarPopup(content: root, size: root.desiredSize)
        self.popup = popup
        popup.onDismiss = { [weak self] in self?.popup = nil }
        popup.present(from: overflow)
    }
    private func showCalendar() {
        if popup != nil {
            dismissPopup()
            return
        }
        let tile: WidgetTile
        if let calendarTile, case .widget(let widget) = calendarTile.content {
            tile = widget
        } else {
            tile = WidgetCatalog.calendar.makeTile()
        }
        let content = NativeWidgetView(tile: tile, cornerRadius: 4, span: .three, expanded: true)
        let popup = WindowsTaskbarPopup(content: content, size: CGSize(width: 380, height: 340))
        self.popup = popup
        popup.onDismiss = { [weak self] in self?.popup = nil }
        popup.present(from: clock)
    }
}

final class WindowsTaskbarExtraContent: NSView {
    let desiredSize: CGSize
    private let columns: Int
    private var selectedIndex = 0
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(tiles: [Tile]) {
        columns = min(4, max(1, tiles.count))
        let rows = (tiles.count + columns - 1) / columns
        desiredSize = CGSize(width: CGFloat(columns) * 88 + 16, height: CGFloat(rows) * 64 + 16)
        super.init(frame: CGRect(origin: .zero, size: desiredSize))
        for (index, tile) in tiles.enumerated() {
            let view = NativeDockTileView(tile: tile)
            view.frame = CGRect(
                x: CGFloat(index % columns) * 88, y: CGFloat(index / columns) * 64, width: 84, height: 60)
            view.interaction.renderedTileSize = 40
            addSubview(view)
        }
    }
    required init?(coder: NSCoder) { nil }
    override func keyDown(with event: NSEvent) {
        let tiles = subviews.compactMap { $0 as? NativeDockTileView }
        guard !tiles.isEmpty else { return }
        switch event.keyCode {
        case 123: selectedIndex = max(0, selectedIndex - 1)
        case 124: selectedIndex = min(tiles.count - 1, selectedIndex + 1)
        case 125: selectedIndex = min(tiles.count - 1, selectedIndex + columns)
        case 126: selectedIndex = max(0, selectedIndex - columns)
        case 115: selectedIndex = 0
        case 119: selectedIndex = tiles.count - 1
        case 36, 49: tiles[selectedIndex].activate()
        default: super.keyDown(with: event); return
        }
        for (index, tile) in tiles.enumerated() {
            tile.layer?.borderWidth = index == selectedIndex ? 1 : 0
            tile.layer?.borderColor = WindowsTaskbarStyle.accent(effectiveAppearance).cgColor
        }
        tiles[selectedIndex].scrollToVisible(tiles[selectedIndex].bounds)
    }
    override func layout() {
        super.layout()
        guard let popupWindow = window,
              let main = NSApp.windows.compactMap({ $0 as? MainWindow }).first else { return }
        for case let tile as NativeDockTileView in subviews {
            let screenFrame = popupWindow.convertToScreen(tile.convert(tile.bounds, to: nil))
            let frame = main.convertFromScreen(screenFrame)
            tile.interaction.globalTileFrame = DockAxisGeometry.topLeftFrame(
                frame, containerHeight: main.contentView?.bounds.height ?? main.frame.height)
        }
    }
}

final class WindowsStatusButton: NSView {
    var glyph: String { didSet { needsDisplay = true } }
    var clockText = "" { didSet { needsDisplay = true } }
    var metrics = WindowsTaskbarMetrics.standard { didSet { needsDisplay = true } }
    var onActivate: (() -> Void)?
    /// Drawn centered in place of a glyph, like a tray icon.
    var image: NSImage? { didSet { needsDisplay = true } }
    /// The button's right-click menu, when it has one.
    var contextActions: (() -> [ContextAction])?
    var isDropTarget = false { didSet { if isDropTarget != oldValue { needsDisplay = true } } }
    /// Drops here destroy things, so the drop-target fill is red rather than the accent.
    var isDestructive = false
    private var hovered = false
    private var pressed = false
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    init(glyph: String, label: String) {
        self.glyph = glyph
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
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
        hovered = true
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), contextActions != nil {
            rightMouseDown(with: event)
            return
        }
        pressed = true
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        let wasPressed = pressed
        pressed = false
        needsDisplay = true
        if wasPressed, bounds.contains(convert(event.locationInWindow, from: nil)) { onActivate?() }
    }
    override func rightMouseDown(with event: NSEvent) {
        guard let actions = contextActions?() else {
            super.rightMouseDown(with: event)
            return
        }
        ContextActionMenuPresenter.popUpMenu(actions: actions, from: self)
    }
    override func accessibilityPerformShowMenu() -> Bool {
        guard let actions = contextActions?(), !actions.isEmpty else { return false }
        ContextActionMenuPresenter.popUpMenu(actions: actions, from: self)
        return true
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { onActivate?() } else { super.keyDown(with: event) }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        if isDropTarget {
            // The accent fill matches taskbar buttons that are drop targets.
            (isDestructive ? NSColor.systemRed : WindowsTaskbarStyle.accent(effectiveAppearance))
                .withAlphaComponent(0.2).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: metrics.cornerRadius, yRadius: metrics.cornerRadius).fill()
        } else if hovered || pressed {
            WindowsTaskbarStyle.highlight(effectiveAppearance, pressed: pressed).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: metrics.cornerRadius, yRadius: metrics.cornerRadius).fill()
        }
        let color = WindowsTaskbarStyle.foreground(effectiveAppearance)
        if glyph == "clock" {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .right
            // Leave room below the text so two lines still fit when the bar is small.
            let inset = metrics.clockInset
            (clockText as NSString).draw(
                in: CGRect(
                    x: inset, y: metrics.inset, width: max(0, bounds.width - inset * 2),
                    height: max(0, bounds.height - metrics.inset)),
                withAttributes: [
                    .font: WindowsTaskbarStyle.font(size: metrics.clockFontSize), .foregroundColor: color,
                    .paragraphStyle: paragraph
                ])
            return
        }
        if let image {
            let size = metrics.trayIconSize
            image.draw(
                in: CGRect(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2, width: size, height: size),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return
        }
        let size = metrics.overflowGlyphSize
        WindowsStatusGlyph.drawOverflow(
            in: CGRect(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2, width: size, height: size),
            color: color)
    }
}
