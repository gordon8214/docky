import Foundation

/// Shared sizing and palette conversion rules for Dock presentation and window sizing.
@MainActor
enum DockTileGeometry {
    static let edgePadding: CGFloat = 8
    static func makePinnedItem(from paletteDrag: DockEditPaletteDrag) -> PinnedTileItem? {
        makePinnedItem(from: paletteDrag.item, widgetSpan: paletteDrag.widgetSpan)
    }

    static func makePinnedItem(from paletteItem: DockEditPaletteItem, widgetSpan: TileSpan?) -> PinnedTileItem? {
        return switch paletteItem {
        case .launchpad:
            PinnedTileItem.launchpad()
        case .startMenu:
            PinnedTileItem.startMenu()
        case .spacer:
            PinnedTileItem.spacer()
        case .flexibleSpacer:
            PinnedTileItem.flexibleSpacer()
        case .divider:
            PinnedTileItem.divider()
        case .widget(let ownerBundleIdentifier, let kind):
            PinnedTileItem.widget(
                kind: kind,
                ownerBundleIdentifier: ownerBundleIdentifier,
                span: resolvedPaletteWidgetSpan(
                    ownerBundleIdentifier: ownerBundleIdentifier,
                    kind: kind,
                    requestedSpan: widgetSpan
                )
            )
        case .smartStack:
            PinnedTileItem.smartStack()
        }
    }

    static func makeTrailingItem(from paletteDrag: DockEditPaletteDrag) -> TrailingTileItem? {
        return switch paletteDrag.item {
        case .launchpad:
            nil
        case .startMenu:
            nil
        case .spacer:
            TrailingTileItem.spacer()
        case .flexibleSpacer:
            TrailingTileItem.flexibleSpacer()
        case .divider:
            TrailingTileItem.divider()
        case .widget(let ownerBundleIdentifier, let kind):
            TrailingTileItem.widget(
                kind: kind,
                ownerBundleIdentifier: ownerBundleIdentifier,
                span: resolvedPaletteWidgetSpan(
                    ownerBundleIdentifier: ownerBundleIdentifier,
                    kind: kind,
                    requestedSpan: paletteDrag.widgetSpan
                )
            )
        case .smartStack:
            TrailingTileItem.smartStack()
        }
    }

    static func size(
        for tile: Tile,
        tileSize: CGFloat,
        tileHeight: CGFloat,
        tileSpacing: CGFloat = 0,
        position: ResolvedDockWindowPosition,
        compactWidgets: Bool = false
    ) -> CGSize {
        let extent: CGFloat
        if tile.content == .divider {
            extent = tileSize * 0.5
        } else if let span = widgetSpan(for: tile) {
            extent = spanExtent(
                for: effectiveWidgetSpan(
                    span, tileSize: tileSize,
                    isVertical: position.isVertical, compactWidgets: compactWidgets), baseTileSize: tileSize,
                tileSpacing: tileSpacing)
        } else {
            extent = tileSize
        }
        return position.isVertical
            ? CGSize(width: tileHeight, height: extent) : CGSize(width: extent, height: tileHeight)
    }
    static func widgetSpan(for tile: Tile) -> TileSpan? {
        switch tile.content {
        case .app(let app): return app.displayedWidget?.span
        case .widget(let widget): return widget.span
        case .smartStack(let stack): return stack.span
        default: return nil
        }
    }

    static func effectiveWidgetSpan(_ span: TileSpan, tileSize: CGFloat, isVertical: Bool, compactWidgets: Bool)
        -> TileSpan {
        if compactWidgets || isVertical {
            return .one
        }

        return span
    }

    private static func spanExtent(for span: TileSpan, baseTileSize: CGFloat, tileSpacing: CGFloat) -> CGFloat {
        let spanCount = CGFloat(span.rawValue)
        return baseTileSize * spanCount + tileSpacing * max(0, spanCount - 1)
    }

    /// Total content size for the given tile list, including inter-tile spacing
    /// and outer stack padding. Used by MainWindow to size itself to fit.
    static func contentSize(
        tiles: [Tile],
        tileSize: CGFloat,
        tileHeight: CGFloat,
        tileSpacing: CGFloat,
        position: ResolvedDockWindowPosition,
        compactWidgets: Bool = false,
        edgePadding: CGFloat = Self.edgePadding
    ) -> CGSize {
        let sizes = tiles.map {
            size(
                for: $0, tileSize: tileSize, tileHeight: tileHeight, tileSpacing: tileSpacing, position: position,
                compactWidgets: compactWidgets)
        }
        let spacings = max(0, CGFloat(tiles.count) - 1) * tileSpacing

        if position.isVertical {
            let height = sizes.reduce(CGFloat(0)) { $0 + $1.height } + spacings + edgePadding * 2
            let width = sizes.map(\.width).max() ?? tileSize
            return CGSize(width: width, height: height)
        }

        let width = sizes.reduce(CGFloat(0)) { $0 + $1.width } + spacings + edgePadding * 2
        let height = sizes.map(\.height).max() ?? tileHeight
        return CGSize(width: width, height: height)
    }

    static func previewedTiles(
        from tiles: [Tile],
        paletteDrag: DockEditPaletteDrag?,
        paletteDropDestination: DockEditDropDestination?,
        externalAppDropPreview: AppTile? = nil,
        externalFolderDropPreview: FolderTile? = nil
    ) -> [Tile] {
        var previewTiles = tiles

        if let externalAppDropPreview {
            let insertionIndex = previewTiles.firstIndex(where: { $0.id == "divider:trailing" }) ?? previewTiles.count
            previewTiles.insert(
                Tile(id: "drop-preview", content: .app(externalAppDropPreview)),
                at: insertionIndex
            )
        }

        if let externalFolderDropPreview {
            let dividerIndex = previewTiles.firstIndex(where: { $0.id == "divider:trailing" }) ?? previewTiles.count
            previewTiles.insert(
                Tile(id: "drop-preview", content: .folder(externalFolderDropPreview)),
                at: min(dividerIndex + 1, previewTiles.count)
            )
        }

        guard let paletteDrag,
            let paletteDropDestination,
            let previewTile = palettePreviewTile(for: paletteDrag)
        else {
            return previewTiles
        }

        switch paletteDropDestination.section {
        case .pinned:
            let insertionIndex = previewTiles.firstIndex(where: { $0.id == "divider:trailing" }) ?? previewTiles.count
            previewTiles.insert(previewTile, at: insertionIndex)
        case .trailing:
            let insertionIndex = min(
                max(
                    0, (previewTiles.firstIndex(where: { $0.id == "divider:trailing" }) ?? (previewTiles.count - 1)) + 1
                ),
                previewTiles.count
            )
            previewTiles.insert(previewTile, at: insertionIndex)
        }

        return previewTiles
    }

    private static func palettePreviewTile(for paletteDrag: DockEditPaletteDrag) -> Tile? {
        switch paletteDrag.item {
        case .launchpad:
            return Tile(
                id: "editor-preview:launchpad",
                content: .launchpad(LaunchpadTile(identifier: "editor-preview:launchpad"))
            )
        case .startMenu:
            return Tile(
                id: "editor-preview:start-menu",
                content: .startMenu(StartMenuTile(identifier: "editor-preview:start-menu"))
            )
        case .spacer:
            return Tile(id: "editor-preview:spacer", content: .spacer)
        case .flexibleSpacer:
            // Render the in-dock drop preview as a fixed-size spacer so the
            // user has a tile-sized target to land on; the dropped tile is
            // still persisted as `.flexibleSpacer` via the palette item
            // factory and stretches once committed.
            return Tile(id: "editor-preview:flexible-spacer", content: .spacer)
        case .divider:
            return Tile(id: "editor-preview:divider", content: .divider)
        case .widget(let ownerBundleIdentifier, let kind):
            return Tile(
                id: "editor-preview:widget",
                content: .widget(
                    WidgetTile(
                        identifier: "editor-preview:widget",
                        title: kind.title,
                        kind: kind,
                        ownerBundleIdentifier: ownerBundleIdentifier,
                        span: resolvedPaletteWidgetSpan(
                            ownerBundleIdentifier: ownerBundleIdentifier,
                            kind: kind,
                            requestedSpan: paletteDrag.widgetSpan
                        )
                    ))
            )
        case .smartStack:
            return Tile(
                id: "editor-preview:smart-stack",
                content: .smartStack(
                    SmartStackTile(
                        identifier: "editor-preview:smart-stack",
                        title: "Smart Stack",
                        widgets: WidgetCatalog.smartStackRegistrations.map { $0.makeTile() },
                        span: .three
                    ))
            )
        }
    }

    static func resolvedPaletteWidgetSpan(
        ownerBundleIdentifier: String,
        kind: WidgetKind,
        requestedSpan: TileSpan?
    ) -> TileSpan {
        let supportedSpans = kind.supportedSpans
        if let requestedSpan, supportedSpans.contains(requestedSpan) {
            return requestedSpan
        }

        if let catalogSpan = WidgetCatalog.staticRegistrations.first(where: {
            $0.ownerBundleIdentifier == ownerBundleIdentifier && $0.kind == kind
        })?.defaultSpan,
            supportedSpans.contains(catalogSpan) {
            return catalogSpan
        }

        return supportedSpans.last ?? .one
    }
}
