import AppKit

final class NativeSmartStackView: NSView {
    let tile: SmartStackTile
    let cornerRadius: CGFloat
    let span: TileSpan
    private var selection = 0
    private var child: NSView?
    private var lastScroll: TimeInterval = 0
    init(tile: SmartStackTile, cornerRadius: CGFloat, span: TileSpan) {
        self.tile = tile
        self.cornerRadius = cornerRadius
        self.span = span
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: String(localized: "Next Widget")) { [weak self] in
                self?.cycle(1)
                return true
            },
            NSAccessibilityCustomAction(name: String(localized: "Previous Widget")) { [weak self] in
                self?.cycle(-1)
                return true
            }
        ])
        showSelection()
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        child?.frame = bounds
    }
    override func scrollWheel(with event: NSEvent) {
        guard tile.widgets.count > 1, event.timestamp - lastScroll > 0.2 else { return }
        let delta =
            abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
            ? event.scrollingDeltaY : event.scrollingDeltaX
        guard abs(delta) > 1 else { return }
        lastScroll = event.timestamp
        cycle(delta < 0 ? 1 : -1)
    }
    func cycle(_ delta: Int) {
        guard !tile.widgets.isEmpty else { return }
        selection = (selection + delta + tile.widgets.count) % tile.widgets.count
        showSelection()
    }
    func activateSelected() {
        guard tile.widgets.indices.contains(selection) else { return }
        let widget = tile.widgets[selection]
        DockTileInteraction(
            tile: Tile(id: "stack-selection", content: .widget(widget)), isDragging: false,
            isDocumentDropTarget: false, isAppFolderDropTarget: false, isTrashDropTarget: false,
            renderedTileSize: nil
        ).handleWidgetTap(widget)
    }
    private func showSelection() {
        child?.removeFromSuperview()
        if tile.widgets.isEmpty {
            child = nativeLabel(String(localized: "No widgets selected"), size: 11, color: .secondaryLabelColor)
        } else {
            selection = min(selection, tile.widgets.count - 1)
            child = NativeWidgetView(tile: tile.widgets[selection], cornerRadius: cornerRadius, span: span)
        }
        if let child { addSubview(child) }
        setAccessibilityLabel(tile.title)
        setAccessibilityValue(
            tile.widgets.isEmpty ? String(localized: "No widgets selected") : tile.widgets[selection].title)
        needsLayout = true
    }
}
