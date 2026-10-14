import AppKit
import OSLog

extension DockCanvasController {
    func makePinnedItem(from paletteDrag: DockEditPaletteDrag) -> PinnedTileItem? {
        DockTileGeometry.makePinnedItem(from: paletteDrag)
    }

    func makePinnedItem(from paletteDrag: DockEditPaletteDrag?) -> PinnedTileItem? {
        guard let paletteDrag else { return nil }
        return DockTileGeometry.makePinnedItem(from: paletteDrag)
    }

    func makeTrailingItem(from paletteDrag: DockEditPaletteDrag?) -> TrailingTileItem? {
        guard let paletteDrag else { return nil }
        return DockTileGeometry.makeTrailingItem(from: paletteDrag)
    }

    func resolvedPaletteWidgetSpan(
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

    var isDraggingPinnedTile: Bool {
        guard let draggedTileID else {
            return false
        }
        return isPinnedReorderable(tileID: draggedTileID)
    }

    var isDraggingTrailingTile: Bool {
        guard let draggedTileID else {
            return false
        }
        return isTrailingReorderable(tileID: draggedTileID)
    }

    func isHiddenForActiveDrag(tileID: String) -> Bool {
        if draggedAdditionalTileIDs.contains(tileID) {
            return true
        }

        guard tileID == draggedTileID else {
            return false
        }

        return (!isDraggingPinnedTile && draggedPinnedTileDestinationIndex != nil)
            || (!isDraggingTrailingTile && draggedTrailingTileDestinationIndex != nil)
            || draggedTileID == tileID
    }

    func shouldHideDraggedOriginalTile(tileID: String) -> Bool {
        isHiddenForActiveDrag(tileID: tileID)
    }

    func canDropInPinnedSection(_ tile: Tile) -> Bool {
        isPinnedReorderable(tileID: tile.id) || store.makePinnedItem(from: tile) != nil
            || bundleIdentifier(for: tile) != nil
    }

    func canDropInTrailingSection(_ tile: Tile) -> Bool {
        isTrailingReorderable(tileID: tile.id) || store.makeTrailingItem(from: tile) != nil
    }
}
