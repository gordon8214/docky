import AppKit
import Combine
import QuartzCore

/// A flipped canvas keeps hit testing, magnification, and drop geometry in one space.
final class DockCanvasView: NSView {
    let controller = DockCanvasController()
    var tiles: [String: NativeDockTileView] = [:]
    var sectionViews: [String: NSView] = [:]
    var scrollViews: [String: NSScrollView] = [:]
    var subscriptions = Set<AnyCancellable>()
    var keyMonitor: Any?
    var isLayingOut = false
    var isUpdatingHierarchy: Bool { isLayingOut }
    var scrollObservers: [String: NSObjectProtocol] = [:]
    var sectionTileIDs: [String: [String]] = [:]
    var dragPreviews: [NativeDockTileView] = []
    var dragPreviewIDs: [String] = []
    var dragTranslation: CGSize = .zero
    var windowsStatus: WindowsTaskbarStatusView?
    var windowsTileIDs: [String] = []
    var windowsAnimationTimer: Timer?
    var groupBackdrops: [String: NSView] = [:]
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        controller.onChange = { [weak self] in self?.needsLayout = true }
        for publisher in [
            controller.store.objectWillChange.eraseToAnyPublisher(),
            controller.layout.objectWillChange.eraseToAnyPublisher(),
            controller.editMode.objectWillChange.eraseToAnyPublisher(),
            controller.dockDrag.objectWillChange.eraseToAnyPublisher()
        ] {
            publisher.sink { [weak self] in
                DispatchQueue.main.async { self?.needsLayout = true }
            }.store(in: &subscriptions)
        }
        observeChanges { [weak self] in
            guard let self else { return }
            _ = self.controller.preferences.effectiveTileSpacing
            _ = ThemeManager.shared.removedLayoutInsertionIDsByTheme
            _ = self.controller.preferences.effectiveTileVerticalPadding
            _ = self.controller.preferences.windowPosition
            _ = self.controller.preferences.showsGroupedOpenedAppsBackdrop
            _ = self.controller.preferences.overflowBehavior
            if !WindowsTaskbarStyle.isActive {
                _ = self.controller.magnification.pointerLocation
                _ = self.controller.magnification.strength
            }
            _ = self.controller.dockSettings.displayTileSize
            self.needsLayout = true
        }.store(in: &subscriptions)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if window == nil {
            clearWindowsTaskbar()
            cancelDrag()
            for token in scrollObservers.values { NotificationCenter.default.removeObserver(token) }
            scrollObservers.removeAll()
        }
        if window != nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.controller.draggedTileID != nil else { return event }
                if event.keyCode == 53 {
                    self.cancelDrag()
                    return nil
                }
                return self.controller.handleDragKeyDown(event) ? nil : event
            }
        }
    }

    override func layout() {
        super.layout()
        layoutCanvas()
    }

    func cancelDrag() {
        for tile in tiles.values { tile.cancelDrag() }
        dragTranslation = .zero
        controller.clearDragState()
        needsLayout = true
    }

    func refreshFrames(force: Bool = false) {
        guard force || !isLayingOut else { return }
        controller.tileFrames.removeAll(keepingCapacity: true)
        controller.visibleTileFrames.removeAll(keepingCapacity: true)
        for (id, tile) in tiles {
            let visual = WindowsTaskbarStyle.isActive
                ? convert(tile.layer?.presentation()?.frame ?? tile.frame, from: tile.superview)
                : convert(tile.bounds, from: tile)
            controller.tileFrames[id] = visual
            if !tile.isHidden, tile.alphaValue > 0 {
                let visible = WindowsTaskbarStyle.isActive
                    ? visual.intersection(convert(tile.superview?.visibleRect ?? tile.bounds, from: tile.superview))
                    : convert(tile.visibleRect, from: tile)
                if !visible.isEmpty { controller.visibleTileFrames[id] = visible }
            }
            if let window, let content = window.contentView {
                let frame = WindowsTaskbarStyle.isActive ? convert(visual, to: nil) : tile.convert(tile.bounds, to: nil)
                tile.interaction.globalTileFrame = CGRect(
                    x: frame.minX, y: content.bounds.height - frame.maxY, width: frame.width, height: frame.height)
                if WindowsTaskbarStyle.isActive {
                    WindowPreviewWindowController.shared.updateSourceFrame(
                        tile.interaction.globalTileFrame, sourceTileID: id)
                }
            }
        }
        controller.updateExternalDragDestinationIndex(at: controller.dockDrag.cursorLocation)
        controller.updatePaletteDropDestinationFromCursor(at: controller.dockDrag.cursorLocation)
    }

    func updateDragPreviews() {
        guard let source = controller.draggedTile else {
            for preview in dragPreviews { preview.removeFromSuperview() }
            dragPreviews.removeAll()
            dragPreviewIDs.removeAll()
            return
        }
        let selected = controller.orderedDraggedSelectionTileIDs.compactMap { id in
            controller.store.tiles.first(where: { $0.id == id })
        }
        let additional = selected.filter { $0.id != source.id }
        let previewTiles = Array(additional.prefix(3).reversed()) + [source]
        if dragPreviewIDs != previewTiles.map(\.id) {
            for preview in dragPreviews { preview.removeFromSuperview() }
            dragPreviews = previewTiles.map { tile in
                let preview = NativeDockTileView(tile: tile)
                preview.isDragPreview = true
                addSubview(preview)
                return preview
            }
            dragPreviewIDs = previewTiles.map(\.id)
        }
        let center = controller.draggedTilePosition
        let translation = dragTranslation
        for (depth, preview) in dragPreviews.enumerated() {
            preview.interaction.renderedTileSize = controller.effectiveTileSize
            let tile = preview.interaction.tile
            let size = controller.magnifiedTileFrame(for: tile, iconSize: controller.effectiveTileSize)
            let stackOffset = tile.id == source.id ? CGFloat(0) : CGFloat(depth + 1) * 3
            preview.frame = CGRect(
                x: center.x + translation.width - size.width / 2 + stackOffset,
                y: center.y + translation.height - size.height / 2 + stackOffset, width: size.width, height: size.height
            )
        }
    }

    func positioned(size: CGSize, offset: CGFloat, vertical: Bool) -> CGRect {
        DockAxisGeometry.frame(size: size, offset: offset, canvas: bounds.size, edge: controller.position)
    }

    func view(for tile: Tile) -> NativeDockTileView {
        if let existing = tiles[tile.id] {
            existing.update(tile: tile)
            return existing
        }
        let view = NativeDockTileView(tile: tile)
        view.canvas = self
        tiles[tile.id] = view
        return view
    }

    func updateDropLocation(_ location: CGPoint) {
        layoutSubtreeIfNeeded()
        refreshFrames()
        controller.updateExternalDragDestinationIndex(at: location)
        controller.updatePaletteDropDestinationFromCursor(at: location)
    }
    func configure(
        _ view: NativeDockTileView, tile: Tile, magnification: DockCanvasController.MagnificationPass
    ) {
        view.interaction.renderedTileSize = magnification.iconSizes[tile.id] ?? controller.effectiveTileSize
        view.interaction.isDragging = controller.draggedTileID == tile.id
        view.interaction.isDocumentDropTarget = controller.dockDrag.documentTargetTileID == tile.id
        view.interaction.isAppFolderDropTarget = controller.draggedAppFolderTargetTileID == tile.id
        view.interaction.isTrashDropTarget = controller.draggedTrashTargetTileID == tile.id
        view.interaction.globalTileFrame = convert(view.bounds, from: view)
        view.refresh()
        if controller.shouldHideDraggedOriginalTile(tileID: tile.id) { view.alphaValue = 0 }
        if !view.hasAnimatedAppearance, view.window != nil {
            view.hasAnimatedAppearance = true
            if !WindowsTaskbarStyle.isActive, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = 0
                animation.toValue = view.alphaValue
                animation.duration = 0.18
                view.layer?.add(animation, forKey: "appearance")
            }
        }
    }
}

final class FlippedDockSectionView: NSView {
    override var isFlipped: Bool { true }
}
