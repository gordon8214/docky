import AppKit
import Combine
import QuartzCore

/// A flipped canvas keeps hit testing and drop geometry in one space.
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
    var dragPreviews: [NativeDockTileView] = []
    var dragPreviewIDs: [String] = []
    var dragTranslation: CGSize = .zero
    var windowsStatus: WindowsTaskbarStatusView?
    var windowsTileIDs: [String] = []
    var windowsAnimationTimer: Timer?
    var windowsMetrics = WindowsTaskbarMetrics.standard
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        controller.onChange = { [weak self] in self?.needsLayout = true }
        for publisher in [
            controller.store.objectWillChange.eraseToAnyPublisher(),
            controller.editMode.objectWillChange.eraseToAnyPublisher(),
            controller.dockDrag.objectWillChange.eraseToAnyPublisher()
        ] {
            publisher.sink { [weak self] in
                DispatchQueue.main.async { self?.needsLayout = true }
            }.store(in: &subscriptions)
        }
        observeChanges { [weak self] in
            guard let self else { return }
            _ = self.controller.preferences.windowPosition
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
            // Taskbar tiles animate, so frames follow the presentation layer.
            let visual = convert(tile.layer?.presentation()?.frame ?? tile.frame, from: tile.superview)
            controller.tileFrames[id] = visual
            if !tile.isHidden, tile.alphaValue > 0 {
                let visible =
                    visual.intersection(convert(tile.superview?.visibleRect ?? tile.bounds, from: tile.superview))
                if !visible.isEmpty { controller.visibleTileFrames[id] = visible }
            }
            if let window, let content = window.contentView {
                let frame = convert(visual, to: nil)
                tile.interaction.globalTileFrame = CGRect(
                    x: frame.minX, y: content.bounds.height - frame.maxY, width: frame.width, height: frame.height)
                WindowPreviewWindowController.shared.updateSourceFrame(
                    tile.interaction.globalTileFrame, sourceTileID: id)
            }
        }
        // The tray's Trash button takes drops for the Trash tile it stands for.
        if let trashID = windowsStatus?.trashTile?.id, let frame = windowsStatus?.trashFrame(in: self) {
            controller.visibleTileFrames[trashID] = frame
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
            let size = controller.tileFrameSize(for: tile)
            let stackOffset = tile.id == source.id ? CGFloat(0) : CGFloat(depth + 1) * 3
            preview.frame = CGRect(
                x: center.x + translation.width - size.width / 2 + stackOffset,
                y: center.y + translation.height - size.height / 2 + stackOffset, width: size.width, height: size.height
            )
        }
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
    func configure(_ view: NativeDockTileView, tile: Tile) {
        view.interaction.renderedTileSize = controller.effectiveTileSize
        view.interaction.isDragging = controller.draggedTileID == tile.id
        view.interaction.isDocumentDropTarget = controller.dockDrag.documentTargetTileID == tile.id
        view.interaction.isAppFolderDropTarget = controller.draggedAppFolderTargetTileID == tile.id
        view.interaction.isTrashDropTarget = controller.draggedTrashTargetTileID == tile.id
        view.interaction.globalTileFrame = convert(view.bounds, from: view)
        view.refresh()
        if controller.shouldHideDraggedOriginalTile(tileID: tile.id) { view.alphaValue = 0 }
    }
}
