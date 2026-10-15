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
    var hasAnimatedAppearance = false
    let hoverBackdrop = NSImageView()
    let activeBackdrop = NSImageView()
    let pressOverlay = CALayer()
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
        minimizedAppIcon.layer?.shadowColor = NSColor.black.cgColor
        minimizedAppIcon.layer?.shadowOpacity = 0.18
        minimizedAppIcon.layer?.shadowRadius = 4
        addSubview(minimizedAppIcon)
        pressOverlay.backgroundColor = NSColor.black.cgColor
        pressOverlay.cornerRadius = 10
        pressOverlay.zPosition = 10
        layer?.addSublayer(pressOverlay)
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
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawTile(dirtyRect)
    }
    func update(tile: Tile) {
        if interaction.tile != tile {
            interaction.tile = tile
            refresh()
        }
    }

    func refresh() {
        let tile = interaction.tile
        let prefs = interaction.preferences
        toolTip = WindowsTaskbarStyle.isActive ? nil : interaction.tooltipTitle
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(interaction.tooltipTitle)
        setAccessibilityIdentifier(tile.id)
        setAccessibilityValue(interaction.badgeText)
        updateTileAppearance()
        minimizedAppIcon.isHidden = true
        updateTileContent()
        imageView.isHidden = content != nil
        badge.stringValue = Self.badgeDisplayText(interaction.badgeText ?? "")
        badge.isHidden = interaction.badgeText == nil
        indicator.isHidden = !interaction.showsRunningIndicator || prefs.effectiveActiveIndicatorShape == .none
        indicator.image = interaction.runningIndicatorImage
        indicator.wantsLayer = true
        let windowsLayout = WindowsTaskbarStyle.isActive && canvas != nil
        windowsIndicator.isHidden = !windowsLayout
        if !windowsLayout { windowsIndicator.removeAllAnimations() }
        indicator.layer?.backgroundColor = indicator.image == nil ? prefs.effectiveActiveIndicatorColor.cgColor : nil
        indicator.layer?.cornerRadius =
            prefs.effectiveActiveIndicatorShape == .underline ? 0 : max(1, interaction.runningIndicatorThickness / 2)
        if windowsLayout { updateWindowsIndicator() }
        needsLayout = true
        needsDisplay = true
    }
    static func badgeDisplayText(_ text: String) -> String {
        if let value = Int(text), value > 999 { return "999+" }
        return String(text.prefix(4))
    }

    func updateTileAppearance() {
        if WindowsTaskbarStyle.isActive { updateWindowsAppearance(); return }
        let prefs = interaction.preferences
        badge.font = .systemFont(ofSize: 10, weight: .semibold)
        badge.layer?.cornerRadius = 8
        for view in [hoverBackdrop, activeBackdrop, imageView] { view.layer?.removeAllAnimations() }
        let selected =
            interaction.isAppFolderDropTarget || interaction.isTrashDropTarget || interaction.isDocumentDropTarget
        layer?.backgroundColor = selected ? NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor : nil
        layer?.cornerRadius = interaction.nonAppTileCornerRadius
        hoverBackdrop.isHidden = !interaction.isHovering || !interaction.supportsHoverBackground
        activeBackdrop.isHidden = !interaction.isFrontmostTile
        hoverBackdrop.image = prefs.effectiveTileHoverBackgroundImageURL.flatMap {
            IconCacheService.shared.image(forImageFileURL: $0)
        }
        activeBackdrop.image = prefs.effectiveTileActiveBackgroundImageURL.flatMap {
            IconCacheService.shared.image(forImageFileURL: $0)
        }
        hoverBackdrop.layer?.backgroundColor = prefs.effectiveTileHoverBackgroundColor?.cgColor
        activeBackdrop.layer?.backgroundColor = prefs.effectiveTileActiveBackgroundColor?.cgColor
        hoverBackdrop.layer?.cornerRadius = prefs.effectiveTileHoverBackgroundCornerRadius
        activeBackdrop.layer?.cornerRadius = prefs.effectiveTileActiveBackgroundCornerRadius
        hoverBackdrop.alphaValue = prefs.effectiveTileHoverBackgroundOpacity
        activeBackdrop.alphaValue = prefs.effectiveTileActiveBackgroundOpacity
        pressOverlay.opacity = Float(max(0, -interaction.pressDarkenAmount))
        let scale = interaction.isHovering ? prefs.effectiveTileHoverScale : 1
        imageView.layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        content?.layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        imageView.layer?.cornerRadius =
            prefs.effectiveTileClipShape == .circle ? min(imageView.bounds.width, imageView.bounds.height) / 2 : 0
        imageView.layer?.masksToBounds = prefs.effectiveTileClipShape == .circle
        alphaValue = CGFloat(
            interaction.tileBodyOpacity * (interaction.isHovering ? prefs.effectiveTileHoverOpacity : 1))
        layer?.shadowColor = prefs.effectiveIconShadowColor?.cgColor
        layer?.shadowRadius = CGFloat(prefs.effectiveIconShadowRadius)
        layer?.shadowOpacity = prefs.effectiveIconShadowColor == nil ? 0 : Float(prefs.effectiveIconShadowOpacity)
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
