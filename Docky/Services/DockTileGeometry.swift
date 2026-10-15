import Foundation

/// Shared sizing and palette conversion rules for taskbar tiles.
@MainActor
enum DockTileGeometry {
    static func makePinnedItem(from paletteDrag: DockEditPaletteDrag) -> PinnedTileItem? {
        makePinnedItem(from: paletteDrag.item, widgetSpan: paletteDrag.widgetSpan)
    }

    static func makePinnedItem(from paletteItem: DockEditPaletteItem, widgetSpan: TileSpan?) -> PinnedTileItem? {
        return switch paletteItem {
        case .launchpad:
            PinnedTileItem.launchpad()
        case .startMenu:
            PinnedTileItem.startMenu()
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

    /// Frame size of a single tile. Widgets span several tile widths, except
    /// on a vertical taskbar, which shows every widget at one tile.
    static func size(for tile: Tile, tileSize: CGFloat, tileHeight: CGFloat, position: ResolvedDockWindowPosition)
        -> CGSize {
        let span: TileSpan = position.isVertical ? .one : widgetSpan(for: tile) ?? .one
        let extent = tileSize * CGFloat(span.rawValue)
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
