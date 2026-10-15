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
        let target = documentDropTargetTileID(at: location) ?? externalTrashTargetTileID(at: location)
        if dockDrag.documentTargetTileID != target { dockDrag.documentTargetTileID = target }
        clearExternalInsertion()
    }
    /// The Trash under the cursor, when a drag from outside the taskbar may go there. Edit
    /// mode and drags out of an app folder never target it: an app folder's apps are
    /// entries in a group, and dropping one on Trash must not uninstall the app.
    func externalTrashTargetTileID(at location: CGPoint) -> String? {
        guard !editMode.isActive, dockDrag.sourceFolderTileID == nil else { return nil }
        if case .app(let url, _) = dockDrag.kind, !Self.canTrash(url) { return nil }
        return trashDropTargetTileID(at: location, sourceTileID: "")
    }
    /// Running apps, Docky included, stay out of the Trash.
    static func canTrash(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if path == Bundle.main.bundleURL.standardizedFileURL.path { return false }
        return !NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL.path == path }
    }
    func updateExternalAppDrop(at location: CGPoint) {
        let target =
            externalTrashTargetTileID(at: location)
            ?? displayTiles.reversed().first { tile in
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
        let target = documentDropTargetTileID(at: location) ?? externalTrashTargetTileID(at: location)
        if dockDrag.documentTargetTileID != target { dockDrag.documentTargetTileID = target }
        guard target == nil else {
            clearExternalInsertion()
            return
        }
        guard isPointInTrailingDropRegion(projected(point: location)) else {
            clearExternalInsertion()
            return
        }
        // The tray shows trailing items in a popup rather than in a row, so a
        // dropped folder joins them just before Trash.
        let index = trailingTiles.firstIndex { $0.content.isTrash } ?? trailingTiles.count
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

    /// The pinned region spans the taskbar's app buttons, or the Start button when there are none.
    func isPointInPinnedDropRegion(_ positionValue: CGFloat) -> Bool {
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

    /// The trailing region is the whole tray, where trailing items live.
    func isPointInTrailingDropRegion(_ positionValue: CGFloat) -> Bool {
        guard !trayFrame.isEmpty else { return false }
        let lowerBound = projected(point: trayFrame.origin)
        return positionValue >= lowerBound && positionValue <= lowerBound + projected(size: trayFrame.size)
    }

    /// Whether a drag will drop into the tray, so the tray can show it.
    var isTrayDropTarget: Bool { activeTrailingDropDestinationIndex != nil }

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
