import AppKit
import OSLog

extension DockCanvasController {
    struct MagnificationPass {
        /// Magnified icon side per tile id. Tiles that are missing render
        /// at their resting size.
        var iconSizes: [String: CGFloat] = [:]
        /// Shift to apply to the entire tile stack so the icon under the
        /// cursor stays put as neighbors magnify.
        var anchorOffset: CGFloat = 0

        static let inactive = MagnificationPass()
    }

    /// Resolves magnification for every tile in one walk. The tile list,
    /// the layout components and the cursor position are each built once
    /// here; resolving them per tile made a pointer move cost the square of
    /// the tile count.
    ///
    /// Magnification is suppressed in conditions where it would conflict
    /// with another interaction (edit mode, active drag) or when there's
    /// no headroom to grow into. Overflow rescaling does NOT disable it —
    /// when the dock is squished, magnification still pops icons up to
    /// the full `largeSize`, which is how Apple's Dock behaves. Scroll
    /// overflow IS disabled though: the section's scroll offset and
    /// clipped viewport make cursor-to-tile mapping unreliable.
    ///
    /// Also publishes the per-frame total along-axis growth to
    /// `DockChromeMetricsService` so the chrome can wrap tightly around
    /// whatever actually grew (handling edges and non-1×1 widgets
    /// precisely, not via the 5-icon constant approximation).
    func magnificationPass() -> MagnificationPass {
        guard dockSettings.magnification,
            !editMode.isActive,
            draggedTileID == nil,
            dockSettings.largeSize > dockSettings.tileSize
        else {
            publishChromeGrowth(0)
            return .inactive
        }

        let tiles = displayTiles
        let canvasAxisLength = projected(size: layout.tileCanvasFrame.size)
        let contentAxisLength = totalAxisLength(for: Self.layoutComponents(for: tiles))
        if preferences.overflowBehavior == .scroll,
            canvasAxisLength > 0,
            contentAxisLength > canvasAxisLength {
            publishChromeGrowth(0)
            return .inactive
        }

        // Read the pointer only once magnification is known to be live, so
        // pointer moves don't invalidate this view while it is suppressed.
        guard let pointer = magnification.pointerLocation else {
            publishChromeGrowth(0)
            return .inactive
        }

        // Pointer position projected onto the dock's primary axis, in
        // *HStack-leading-relative* coords so it can be compared directly
        // against the tiles' rest centers. The HStack/VStack centers itself
        // within the canvas when content fits, so we subtract that same
        // leading gap from the cursor before doing any distance math.
        // Without this, hovering over the first icon magnifies icons
        // further inward by the centering offset.
        let canvasOrigin = layout.tileCanvasFrame.origin
        let local = CGPoint(x: pointer.x - canvasOrigin.x, y: pointer.y - canvasOrigin.y)
        let cursorInCanvas = self.position.isVertical ? local.y : local.x
        let contentFits = contentAxisLength <= canvasAxisLength + 0.5
        let cursor =
            contentFits
            ? cursorInCanvas - max(0, (canvasAxisLength - contentAxisLength) / 2)
            : cursorInCanvas

        return resolvedMagnification(for: tiles, cursor: cursor, contentFits: contentFits)
    }
    func magnificationExtent(for tile: Tile, iconSize: CGFloat) -> CGFloat {
        projected(
            size: DockTileGeometry.size(
                for: tile, tileSize: iconSize,
                tileHeight: iconSize + (tileHeight - effectiveTileSize), tileSpacing: effectiveTileSpacing,
                position: position, compactWidgets: layout.compactsWidgetsForOverflow))
    }
    func resolvedMagnification(for tiles: [Tile], cursor: CGFloat, contentFits: Bool) -> MagnificationPass {
        let iconSize = effectiveTileSize
        let model = DockMagnificationModel(
            baseSize: iconSize, maxSize: dockSettings.largeSize,
            influenceRadius: iconSize * 2.5, strength: magnification.strength, cursorAxisLocation: cursor)
        let items = tiles.map { tile in
            DockMagnificationLayout.Item(
                id: tile.id, restExtent: magnificationExtent(for: tile, iconSize: iconSize),
                magnifies: shouldMagnify(tile))
        }
        let resolved = DockMagnificationLayout(
            items: items, spacing: effectiveTileSpacing, edgePadding: effectiveEdgePadding,
            restIconSize: iconSize, model: model, cursor: cursor,
            magnifiedExtent: { index, size in magnificationExtent(for: tiles[index], iconSize: size) })
        publishChromeGrowth(resolved.totalGrowth)
        return MagnificationPass(
            iconSizes: resolved.iconSizes,
            anchorOffset: contentFits ? 0 : cursor - resolved.anchoredMag)
    }

    func shouldMagnify(_ tile: Tile) -> Bool {
        switch tile.content {
        case .app(let app):
            if let widget = app.displayedWidget {
                return effectiveWidgetSpan(widget.span) == .one
            }
            return true
        case .folder, .trash, .appFolder, .minimizedWindow, .launchpad, .startMenu, .spacer, .flexibleSpacer:
            return true
        case .widget(let widget):
            return effectiveWidgetSpan(widget.span) == .one
        case .smartStack(let stack):
            return effectiveWidgetSpan(stack.span) == .one
        case .divider:
            return false
        }
    }

    func effectiveWidgetSpan(_ span: TileSpan) -> TileSpan {
        DockTileGeometry.effectiveWidgetSpan(
            span,
            tileSize: effectiveTileSize,
            isVertical: position.isVertical,
            compactWidgets: layout.compactsWidgetsForOverflow
        )
    }

    /// Defers the publish to the next runloop tick so we don't mutate
    /// shared state mid-render. The service isn't observed by this view,
    /// so this never re-triggers `TileContainerView`.
    func publishChromeGrowth(_ value: CGFloat) {
        DockChromeMetricsService.shared.setAlongAxisGrowth(value)
    }

    /// Frame to assign to the tile, computed from its magnified icon side.
    /// Padding stays constant, matching Apple Dock's behavior where the
    /// icon scales but the tile chrome around it remains thin.
    func magnifiedTileFrame(for tile: Tile, iconSize: CGFloat) -> CGSize {
        guard iconSize > effectiveTileSize else {
            return DockTileGeometry.size(
                for: tile,
                tileSize: effectiveTileSize,
                tileHeight: tileHeight,
                tileSpacing: effectiveTileSpacing,
                position: position,
                compactWidgets: layout.compactsWidgetsForOverflow
            )
        }
        let magnifiedHeight = iconSize + (tileHeight - effectiveTileSize)
        return DockTileGeometry.size(
            for: tile,
            tileSize: iconSize,
            tileHeight: magnifiedHeight,
            tileSpacing: effectiveTileSpacing,
            position: position,
            compactWidgets: layout.compactsWidgetsForOverflow
        )
    }

    func isPinnedReorderable(tileID: String) -> Bool {
        store.isPinnedReorderable(tileID: tileID)
    }

    func isTrailingReorderable(tileID: String) -> Bool {
        store.isTrailingReorderable(tileID: tileID)
    }

    func isTileDraggable(_ tile: Tile) -> Bool {
        // Inline children of an app folder (rendered next to the folder
        // tile in inline / grouped-opened modes) are derived from the
        // folder's contents — reordering them as standalone tiles would
        // detach the relationship. Force users through the explicit
        // "Remove from Folder" action instead.
        if tile.id.hasPrefix("folder-running:") {
            return false
        }
        switch tile.content {
        case .app(let app):
            return !app.bundleIdentifier.isEmpty && app.bundleIdentifier != "com.apple.finder"
        case .minimizedWindow:
            return false
        case .appFolder:
            return isPinnedReorderable(tileID: tile.id)
        case .widget, .smartStack:
            return isPinnedReorderable(tileID: tile.id) || isTrailingReorderable(tileID: tile.id)
        case .launchpad, .startMenu, .spacer, .flexibleSpacer, .divider:
            return editMode.isActive && (isPinnedReorderable(tileID: tile.id) || isTrailingReorderable(tileID: tile.id))
        case .folder, .trash:
            return editMode.isActive && isTrailingReorderable(tileID: tile.id)
        }
    }
}
