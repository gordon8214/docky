import AppKit
import Combine

final class WindowsTaskbarStatusView: NSView {
    var extraTiles: [Tile] = [] { didSet { overflow.isHidden = extraTiles.isEmpty } }
    var calendarTile: Tile?
    var metrics = WindowsTaskbarMetrics.standard {
        didSet {
            guard metrics != oldValue else { return }
            for button in [overflow, clock] { button.metrics = metrics }
            menuExtras.metrics = metrics
            needsLayout = true
        }
    }
    private let overflow = WindowsStatusButton(glyph: "overflow", label: "Show additional Dock items")
    private let clock = WindowsStatusButton(glyph: "clock", label: "Date and time")
    private let menuExtras = WindowsMenuExtrasView()
    private let ownerID = UUID()
    private var subscriptions = Set<AnyCancellable>()
    private var popup: WindowsTaskbarPopup?
    override var isFlipped: Bool { true }
    var preferredWidth: CGFloat {
        (extraTiles.isEmpty ? 0 : metrics.overflowWidth) + menuExtras.preferredWidth + metrics.clockWidth
            + metrics.margin
    }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for button in [overflow, clock] { addSubview(button) }
        overflow.isHidden = extraTiles.isEmpty
        addSubview(menuExtras)
        overflow.onActivate = { [weak self] in self?.showExtras() }
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
        refresh()
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
        let extrasWidth = min(menuExtras.preferredWidth,
                              max(0, bounds.width - preferredWidth + menuExtras.preferredWidth))
        menuExtras.frame = CGRect(x: offset, y: inset, width: extrasWidth, height: height)
        offset += extrasWidth
        clock.frame = CGRect(x: offset, y: inset, width: metrics.clockWidth, height: height)
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
    private var hovered = false
    private var pressed = false
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
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
        pressed = true
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        pressed = false
        needsDisplay = true
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onActivate?() }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { onActivate?() } else { super.keyDown(with: event) }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        if hovered || pressed {
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
        let size = metrics.overflowGlyphSize
        WindowsStatusGlyph.drawOverflow(
            in: CGRect(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2, width: size, height: size),
            color: color)
    }
}
