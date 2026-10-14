import AppKit
import OSLog

extension DockCanvasController {
    func clearExternalInsertion() {
        if dockDrag.destinationIndex != nil { dockDrag.destinationIndex = nil }
        if dockDrag.destinationSection != nil { dockDrag.destinationSection = nil }
    }
    func updateExternalDragDestinationIndex(at location: CGPoint?) {
        guard let location, let kind = dockDrag.kind else {
            clearExternalInsertion()
            if dockDrag.documentTargetTileID != nil { dockDrag.documentTargetTileID = nil }
            return
        }
        dockDrag.updateSpringLoadCandidate(springLoadCandidateTileID(at: location))
        switch kind {
        case .document: updateExternalDocumentDrop(at: location)
        case .app: updateExternalAppDrop(at: location)
        case .folder: updateExternalFolderDrop(at: location)
        }
    }
    func updateExternalDocumentDrop(at location: CGPoint) {
        let target = documentDropTargetTileID(at: location) ?? trashDropTargetTileID(at: location, sourceTileID: "")
        if dockDrag.documentTargetTileID != target { dockDrag.documentTargetTileID = target }
        clearExternalInsertion()
    }
    func updateExternalAppDrop(at location: CGPoint) {
        let target = displayTiles.reversed().first { tile in
            if case .appFolder = tile.content { return visibleTileFrames[tile.id]?.contains(location) == true }
            return false
        }?.id
        if dockDrag.documentTargetTileID != target { dockDrag.documentTargetTileID = target }
        if target != nil {
            clearExternalInsertion()
            return
        }
        let positionValue = projected(point: location)
        guard isPointInPinnedDropRegion(positionValue) else {
            clearExternalInsertion()
            return
        }
        let index = DockAxisGeometry.insertionIndex(
            at: positionValue, frames: pinnedTiles.map { tileFrames[$0.id] }, vertical: position.isVertical)
        if dockDrag.destinationIndex != index { dockDrag.destinationIndex = index }
        if dockDrag.destinationSection != .pinned { dockDrag.destinationSection = .pinned }
    }
    func updateExternalFolderDrop(at location: CGPoint) {
        let target = documentDropTargetTileID(at: location)
        if dockDrag.documentTargetTileID != target { dockDrag.documentTargetTileID = target }
        guard target == nil else {
            clearExternalInsertion()
            return
        }
        let positionValue = projected(point: location)
        guard isPointInTrailingDropRegion(positionValue) else {
            clearExternalInsertion()
            return
        }
        let trashIndex =
            trailingTiles.firstIndex {
                if case .trash = $0.content { return true }
                return false
            } ?? trailingTiles.count
        let insertion = DockAxisGeometry.insertionIndex(
            at: positionValue, frames: trailingTiles.map { tileFrames[$0.id] }, vertical: position.isVertical)
        let index = min(insertion, trashIndex)
        if dockDrag.destinationIndex != index { dockDrag.destinationIndex = index }
        if dockDrag.destinationSection != .trailing { dockDrag.destinationSection = .trailing }
    }

    func updatePaletteDropDestinationFromCursor(at location: CGPoint?) {
        guard let location, let paletteDrag = editMode.paletteDrag else {
            return
        }
        guard let palettePreviewTile else {
            if editMode.paletteDropDestination != nil { editMode.paletteDropDestination = nil }
            return
        }
        updatePreviewDestination(
            at: projected(point: location),
            sourceTileID: palettePreviewTile.id,
            isTileDrag: false,

            canDropIntoPinned: DockTileGeometry.makePinnedItem(from: paletteDrag) != nil,
            canDropIntoTrailing: DockTileGeometry.makeTrailingItem(from: paletteDrag) != nil
        )
    }

    func documentDropTargetTileID(at location: CGPoint) -> String? {
        guard !editMode.isActive else { return nil }
        let candidates = displayTiles.compactMap { tile -> DockDropGeometry.Candidate? in
            guard let frame = visibleTileFrames[tile.id] else { return nil }
            let accepts: Bool
            if case .app(let app) = tile.content {
                accepts = app.displayedWidget == nil && !app.bundleIdentifier.isEmpty
            } else {
                accepts = false
            }
            return .init(identifier: tile.id, frame: frame, acceptsDrop: accepts)
        }
        return DockDropGeometry.target(at: location, candidates: candidates)
    }

    /// Tile id under the cursor that should spring-open during a drag.
    /// Grid-mode app folders and grid-mode regular folders qualify; list/
    /// inline presentations can't host drop targets per item.
    func springLoadCandidateTileID(at location: CGPoint) -> String? {
        guard !editMode.isActive else { return nil }
        for tile in displayTiles.reversed() {
            guard let frame = visibleTileFrames[tile.id], frame.contains(location) else { continue }
            switch tile.content {
            case .appFolder(let folder)
            where folder.contentViewMode == .grid && !folder.apps.isEmpty:
                return tile.id
            case .folder(let folder)
            where folder.displayMode == .folder && folder.contentViewMode == .grid:
                return tile.id
            default:
                return nil
            }
        }
        return nil
    }

    func isPointInPinnedDropRegion(_ positionValue: CGFloat) -> Bool {
        if WindowsTaskbarStyle.isActive {
            let frames = displayTiles.compactMap { tile -> CGRect? in
                guard case .app = tile.content else { return nil }
                return visibleTileFrames[tile.id]
            }
            guard let first = frames.map(\.minX).min(), let last = frames.map(\.maxX).max() else {
                guard let start = visibleTileFrames["windows:start"] ?? displayTiles.first(where: {
                    if case .startMenu = $0.content { return true }
                    return false
                }).flatMap({ visibleTileFrames[$0.id] }) else { return false }
                return positionValue >= start.minX && positionValue <= start.maxX + 8
            }
            return positionValue >= first - 8 && positionValue <= last + 8
        }
        guard let trailingBoundaryFrame = tileFrames[pinnedTrailingBoundaryTileID],
            let lowerBound = pinnedDropRegionLowerBound
        else {
            return false
        }

        let upperBound = projected(point: trailingBoundaryFrame.origin)
        return positionValue >= lowerBound && positionValue <= upperBound
    }

    /// Leading edge of the pinned drop region. Normally this is the trailing
    /// edge of the fixed Finder fixture, so drops never land before it. Shelve
    /// mode can hide the Finder tile, in which case there's nothing to anchor
    /// against, so fall back to the dock's leading content edge. Without this
    /// fallback the whole pinned section becomes undroppable (issue #13).
    var pinnedDropRegionLowerBound: CGFloat? {
        if let finderFrame = tileFrames["pinned:com.apple.finder"] {
            return projected(point: finderFrame.origin) + projected(size: finderFrame.size)
        }
        return tileFrames.values.map { projected(point: $0.origin) }.min()
    }

    var pinnedTrailingBoundaryTileID: String {
        tileFrames.keys.contains("divider:running") ? "divider:running" : "divider:trailing"
    }

    func isPointInTrailingDropRegion(_ positionValue: CGFloat) -> Bool {
        guard let dividerFrame = tileFrames["divider:trailing"] else {
            return false
        }

        // With trailing tiles present the region spans from the divider's
        // trailing edge to the last tile's trailing edge. Shelve mode can hide
        // Trash and leave the trailing section empty, so there's no tile past
        // the divider to anchor against, and the dock shrinks to content,
        // leaving no empty space either. Treat the divider tile itself as the
        // drop target so widgets can still be dropped there (issue #13).
        guard let lastTrailingTileID = previewTrailingTiles.last?.id,
            let trailingBoundaryFrame = tileFrames[lastTrailingTileID]
        else {
            let lowerBound = projected(point: dividerFrame.origin)
            let upperBound = projected(point: dividerFrame.origin) + projected(size: dividerFrame.size)
            return positionValue >= lowerBound && positionValue <= upperBound
        }

        let lowerBound = projected(point: dividerFrame.origin) + projected(size: dividerFrame.size)
        let upperBound = projected(point: trailingBoundaryFrame.origin) + projected(size: trailingBoundaryFrame.size)
        return positionValue >= lowerBound && positionValue <= upperBound
    }

    func previewTiles(for section: DockEditDropSection) -> [Tile] {
        switch section {
        case .pinned:
            previewPinnedBaseTiles
        case .trailing:
            previewTrailingTiles
        }
    }

    func currentDropDestinationIndex(for section: DockEditDropSection, isTileDrag: Bool) -> Int? {
        if isTileDrag {
            return switch section {
            case .pinned: draggedPinnedTileDestinationIndex
            case .trailing: draggedTrailingTileDestinationIndex
            }
        }

        guard editMode.paletteDropDestination?.section == section else {
            return nil
        }
        return editMode.paletteDropDestination?.index
    }

    func setDropDestination(section: DockEditDropSection, index: Int?, isTileDrag: Bool) {
        if isTileDrag {
            switch section {
            case .pinned:
                draggedPinnedTileDestinationIndex = index
            case .trailing:
                draggedTrailingTileDestinationIndex = index
            }
            return
        }

        if let index {
            editMode.paletteDropDestination = DockEditDropDestination(section: section, index: index)
        } else {
            if editMode.paletteDropDestination != nil { editMode.paletteDropDestination = nil }
        }
    }
}
