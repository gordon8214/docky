import AppKit
import Combine

final class WindowsTaskbarStatusView: NSView {
    var extraTiles: [Tile] = [] { didSet { overflow.isHidden = extraTiles.isEmpty } }
    var calendarTile: Tile?
    var batteryTile: Tile?
    private let overflow = WindowsStatusButton(glyph: "overflow", label: "Show additional Dock items")
    private let network = WindowsStatusButton(glyph: "network-offline", label: "Network")
    private let volume = WindowsStatusButton(glyph: "volume", label: "Volume")
    private let battery = WindowsStatusButton(glyph: "battery", label: "Battery")
    private let clock = WindowsStatusButton(glyph: "clock", label: "Date and time")
    private let ownerID = UUID()
    private var subscriptions = Set<AnyCancellable>()
    private var popup: WindowsTaskbarPopup?
    override var isFlipped: Bool { true }
    var preferredWidth: CGFloat { (extraTiles.isEmpty ? 0 : 32) + 64 + (battery.isHidden ? 0 : 28) + 98 + 12 }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for button in [overflow, network, volume, battery, clock] { addSubview(button) }
        overflow.onActivate = { [weak self] in self?.showExtras() }
        network.onActivate = {
            WindowsTaskbarStatusService.openSettings("com.apple.Network-Settings.extension")
        }
        volume.onActivate = { WindowsTaskbarStatusService.openSettings("com.apple.Sound-Settings.extension") }
        battery.onActivate = { BatteriesService.shared.openInBatterySettings() }
        battery.onContextMenu = { [weak self] in
            guard let self else { return }
            ContextActionMenuPresenter.popUpMenu(actions: [
                .action("Battery Details") { [weak self] in self?.showBatteryDetails() },
                .action("Battery Settings") { BatteriesService.shared.openInBatterySettings() }
            ], from: self.battery)
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
        BatteriesService.shared.ensureFreshBatteries()
        observeChanges { [weak self] in
            _ = WindowsTaskbarStatusService.shared.networkSymbol
            _ = WindowsTaskbarStatusService.shared.networkDescription
            _ = WindowsTaskbarStatusService.shared.audioVolume
            _ = WindowsTaskbarStatusService.shared.audioMuted
            _ = WindowsTaskbarStatusService.shared.now
            self?.refresh()
        }.store(in: &subscriptions)
        BatteriesService.shared.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }.store(in: &subscriptions)
        refresh()
    }
    func refresh() {
        let status = WindowsTaskbarStatusService.shared
        network.glyph = status.networkSymbol
        network.setAccessibilityLabel(status.networkDescription)
        volume.glyph = status.audioMuted || status.audioVolume == 0 ? "volume-muted" : "volume"
        volume.setAccessibilityLabel(status.audioDescription)
        let mac = BatteriesService.shared.snapshot?.devices.first { $0.kind == .mac }
        battery.isHidden = mac == nil
        battery.glyph = mac?.isCharging == true ? "battery-charging" : "battery"
        battery.level = CGFloat(mac?.levels.first?.percentage ?? 0) / 100
        let batteryLabel =
            mac.map {
                "Battery \($0.levels.first?.percentage ?? 0) percent" + ($0.isCharging ? ", charging" : "")
            } ?? "Battery unavailable"
        battery.setAccessibilityLabel(batteryLabel)
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
        var offset: CGFloat = 0
        for button in [overflow, network, volume, battery, clock] where !button.isHidden {
            let width: CGFloat = button === clock ? 98 : button === battery ? 28 : 32
            button.frame = CGRect(x: offset, y: 4, width: width, height: 40)
            offset += width
        }
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
    private func showBatteryDetails() {
        dismissPopup()
        let tile: WidgetTile
        if let batteryTile, case .widget(let widget) = batteryTile.content {
            tile = widget
        } else {
            tile = WidgetCatalog.batteries.makeTile()
        }
        let content = NativeWidgetView(tile: tile, cornerRadius: 4,
                                       span: .three, expanded: true)
        let popup = WindowsTaskbarPopup(content: content, size: CGSize(width: 380, height: 340))
        self.popup = popup
        popup.onDismiss = { [weak self] in self?.popup = nil }
        popup.present(from: battery)
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
    var level: CGFloat = 1 { didSet { needsDisplay = true } }
    var onActivate: (() -> Void)?
    var onContextMenu: (() -> Void)?
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
    override func rightMouseDown(with event: NSEvent) { onContextMenu?() }
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
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
        let color = WindowsTaskbarStyle.foreground(effectiveAppearance)
        if glyph == "clock" {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .right
            (clockText as NSString).draw(
                in: bounds.insetBy(dx: 7, dy: 4),
                withAttributes: [
                    .font: WindowsTaskbarStyle.font(size: 12), .foregroundColor: color,
                    .paragraphStyle: paragraph
                ])
            return
        }
        WindowsStatusGlyph.draw(
            glyph, in: CGRect(x: (bounds.width - 18) / 2, y: 11, width: 18, height: 18), color: color,
            level: level)
    }
}
