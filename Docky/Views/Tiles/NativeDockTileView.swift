import AppKit
import Combine
import QuartzCore

final class NativeDockTileView: NSView, NSPopoverDelegate {
    var isDragPreview = false
    var holdsFolderInteraction = false
    weak var canvas: DockCanvasView?
    var interaction: DockTileInteraction
    let imageView = NSImageView()
    let minimizedAppIcon = NSImageView()
    let hoverBackdrop = NSImageView()
    let activeBackdrop = NSImageView()
    var fan: NativeFolderFanController?
    var folderIconKey: String?
    var folderIconImage: NSImage?
    var folderPreviewTask: Task<Void, Never>?
    var folderPreviewURL: URL?
    var folderPreviewSort: FolderTileSortMode?
    var folderPreviewURLs: [URL] = []
    var folderPreviewNeedsRefresh = true
    var watchedFolder: URL?
    let badge = NSTextField(labelWithString: "")
    let indicator = NSImageView()
    let windowsIndicator = CALayer()
    var content: NSView?
    var contentKey: String?
    var tracking: NSTrackingArea?
    var mouseDownPoint: CGPoint?
    var wasDragging = false
    var canceledMouseSession = false
    var dragInteractionToken: UUID?
    var folderInteractionToken: UUID?
    weak var dragWindow: MainWindow?
    weak var heldFolderWindow: MainWindow?
    let folderWatcherID = "tile-view:" + UUID().uuidString
    var subscriptions = Set<AnyCancellable>()
    var folderPopover: NSPopover?
    var wasSpringLoaded = false
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    init(tile: Tile) {
        interaction = DockTileInteraction(
            tile: tile, isDragging: false, isDocumentDropTarget: false, isAppFolderDropTarget: false,
            isTrashDropTarget: false, renderedTileSize: nil)
        super.init(frame: .zero)
        wantsLayer = true
        for decoration in [imageView, minimizedAppIcon, hoverBackdrop, activeBackdrop, indicator, badge] {
            decoration.setAccessibilityElement(false)
        }
        imageView.imageScaling = .scaleProportionallyUpOrDown
        indicator.imageScaling = .scaleProportionallyUpOrDown
        badge.font = .systemFont(ofSize: 10, weight: .semibold)
        badge.textColor = .white
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.systemRed.cgColor
        badge.layer?.cornerRadius = 8
        for backdrop in [activeBackdrop, hoverBackdrop] {
            backdrop.wantsLayer = true
            backdrop.imageScaling = .scaleAxesIndependently
            backdrop.layer?.masksToBounds = true
            addSubview(backdrop)
        }
        imageView.wantsLayer = true
        addSubview(imageView)
        minimizedAppIcon.imageScaling = .scaleProportionallyUpOrDown
        minimizedAppIcon.wantsLayer = true
        // Through `NSView.shadow`: AppKit resets a backing layer's own shadow
        // opacity when the view moves into a window.
        let badgeShadow = NSShadow()
        badgeShadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        badgeShadow.shadowBlurRadius = 4
        badgeShadow.shadowOffset = CGSize(width: 0, height: -3)
        minimizedAppIcon.shadow = badgeShadow
        addSubview(minimizedAppIcon)
        addSubview(indicator)
        addSubview(badge)
        installObservers()
        refresh()
    }
    required init?(coder: NSCoder) { nil }
    isolated deinit { folderPreviewTask?.cancel() }
    override func hitTest(_ point: NSPoint) -> NSView? { isDragPreview ? nil : super.hitTest(point) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func accessibilityPerformShowMenu() -> Bool { showAccessibilityMenu() }
    override func accessibilityPerformPress() -> Bool { performTilePress() }
    override func updateTrackingAreas() { nativeUpdateTrackingAreas() }
    override func mouseEntered(with event: NSEvent) { nativeMouseEntered(with: event) }
    override func mouseExited(with event: NSEvent) { nativeMouseExited(with: event) }
    override func mouseDown(with event: NSEvent) { nativeMouseDown(with: event) }
    override func mouseDragged(with event: NSEvent) { nativeMouseDragged(with: event) }
    override func mouseUp(with event: NSEvent) { nativeMouseUp(with: event) }
    override func rightMouseDown(with event: NSEvent) { nativeRightMouseDown(with: event) }
    override func keyDown(with event: NSEvent) { nativeKeyDown(with: event) }
    override func viewDidMoveToWindow() { nativeViewDidMoveToWindow() }
    override func layout() {
        super.layout()
        layoutTile()
    }
    func update(tile: Tile) {
        if interaction.tile != tile {
            interaction.tile = tile
            refresh()
        }
    }

    func refresh() {
        let tile = interaction.tile
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(interaction.tooltipTitle)
        setAccessibilityIdentifier(tile.id)
        setAccessibilityValue(interaction.badgeText)
        updateWindowsAppearance()
        minimizedAppIcon.isHidden = true
        updateTileContent()
        imageView.isHidden = content != nil
        badge.stringValue = Self.badgeDisplayText(interaction.badgeText ?? "")
        badge.isHidden = interaction.badgeText == nil
        indicator.isHidden = !interaction.showsRunningIndicator
        indicator.wantsLayer = true
        indicator.layer?.cornerRadius = 0
        // Taskbar tiles draw the Windows indicator; tiles off the taskbar (the tray
        // popup, drag previews) keep an underline.
        let windowsLayout = canvas != nil
        windowsIndicator.isHidden = !windowsLayout
        if windowsLayout {
            updateWindowsIndicator()
        } else {
            windowsIndicator.removeAllAnimations()
            indicator.layer?.backgroundColor = WindowsTaskbarStyle.Tray.indicatorColor.cgColor
        }
        needsLayout = true
    }
    static func badgeDisplayText(_ text: String) -> String {
        if let value = Int(text), value > 999 { return "999+" }
        return String(text.prefix(4))
    }

    func updateTileContent() {
        let tile = interaction.tile
        let widget: WidgetTile?
        switch tile.content {
        case .widget(let value): widget = value
        case .app(let app): widget = app.displayedWidget
        default: widget = nil
        }
        if let widget {
            let key = "widget:\(widget.identifier):\(widget.settings):\(interaction.widgetRenderedSpan?.rawValue ?? 1)"
            if contentKey != key {
                setContent(
                    NativeWidgetView(
                        tile: widget, cornerRadius: interaction.nonAppTileCornerRadius,
                        span: interaction.widgetRenderedSpan ?? .one), key: key)
            }
            content?.layer?.cornerRadius = interaction.nonAppTileCornerRadius
        } else if case .smartStack(let stack) = tile.content {
            let renderedSpan = interaction.widgetRenderedSpan ?? .one
            let key =
                "stack:\(stack.identifier):\(stack.widgets):\(renderedSpan.rawValue)"
                + ":\(interaction.nonAppTileCornerRadius)"
            if contentKey != key {
                setContent(
                    NativeSmartStackView(
                        tile: stack, cornerRadius: interaction.nonAppTileCornerRadius,
                        span: interaction.widgetRenderedSpan ?? .one), key: key)
            }
        } else {
            setContent(nil, key: nil)
            updateImageContent()
        }
    }

    func setContent(_ view: NSView?, key: String?) {
        guard contentKey != key || (view == nil && content != nil) else { return }
        content?.removeFromSuperview()
        content = view
        contentKey = key
        if let view {
            view.wantsLayer = true
            addSubview(view, positioned: .below, relativeTo: badge)
        }
    }

}
