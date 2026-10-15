import AppKit
import OSLog

extension DockCanvasController {
    func updateDrag(for tile: Tile, value: DockPointerDrag) {
        defer { onChange?() }
        guard isTileDraggable(tile) else {
            return
        }

        if draggedTileID == nil { beginDrag(tile) }

        guard draggedTileID == tile.id else {
            return
        }

        draggedTileOffset = projected(size: value.translation)
        draggedPickupCandidateTileID = dragPickupCandidateTileID(at: value.location)

        if updateDragHoverTargets(tile, location: value.location) { return }

        if hasCollectedAdditionalAppsDuringDrag {
            clearDragPreviewDestinations()
            return
        }

        draggedAppFolderTargetTileID = nil
        draggedTrashTargetTileID = nil
        updatePreviewDestination(
            at: projected(point: value.location),
            sourceTileID: tile.id,
            isTileDrag: true,

            canDropIntoPinned: canDropInPinnedSection(tile),
            canDropIntoTrailing: canDropInTrailingSection(tile)
        )
    }

    func updateDragHoverTargets(_ tile: Tile, location: CGPoint) -> Bool {
        if draggedBundleIdentifier != nil,
            let groupTargetTileID = appFolderDropTargetTileID(
                at: location,
                selectedTileIDs: draggedSelectionTileIDs,
                selectedBundleIdentifiers: draggedSelectionBundleIdentifiers
            ) {
            if draggedAppFolderTargetTileID != groupTargetTileID {
                Self.logger.debug(
                    "Drag folder target tile=\(self.tileLogDescription(tile), privacy: .public)"
                )
            }
            draggedAppFolderTargetTileID = groupTargetTileID
            draggedTrashTargetTileID = nil
            draggedPinnedTileDestinationIndex = nil
            draggedTrailingTileDestinationIndex = nil
            if editMode.paletteDropDestination != nil { editMode.paletteDropDestination = nil }
            return true
        }

        // Only tiles the Trash can remove (pinned or trailing items) target it.
        if isPinnedReorderable(tileID: tile.id) || isTrailingReorderable(tileID: tile.id),
            let trashTargetTileID = trashDropTargetTileID(at: location, sourceTileID: tile.id) {
            if draggedTrashTargetTileID != trashTargetTileID {
                Self.logger.debug(
                    "Drag trash target tile=\(self.tileLogDescription(tile), privacy: .public)"
                )
            }
            draggedTrashTargetTileID = trashTargetTileID
            draggedAppFolderTargetTileID = nil
            draggedPinnedTileDestinationIndex = nil
            draggedTrailingTileDestinationIndex = nil
            if editMode.paletteDropDestination != nil { editMode.paletteDropDestination = nil }
            return true
        }

        return false
    }

    func beginDrag(_ tile: Tile) {
        draggedTileID = tile.id
        draggedAdditionalTileIDs = []
        draggedTileInitialFrame = tileFrames[tile.id]
        draggedPinnedTileDestinationIndex =
            isPinnedReorderable(tileID: tile.id) ? pinnedTileIDs.firstIndex(of: tile.id) : nil
        draggedTrailingTileDestinationIndex =
            isTrailingReorderable(tileID: tile.id) ? trailingTileIDs.firstIndex(of: tile.id) : nil
        // Drag wins over hover/widget previews — they'd block the cursor
        // and confuse the reorder animation otherwise.
        WindowPreviewWindowController.shared.dismissCurrent()
        WidgetExpansionWindowController.shared.dismiss(sourceTileID: tile.id)
        Self.logger.info(
            "Drag started tile=\(self.tileLogDescription(tile), privacy: .public)"
        )
    }

    func endDrag(for tile: Tile, value: DockPointerDrag) {
        guard draggedTileID == tile.id else { return }
        defer { onChange?() }
        Self.logger.info(
            "endDrag tile=\(self.tileLogDescription(tile), privacy: .public)"
        )
        updateDrag(for: tile, value: value)

        guard draggedTileID == tile.id else {
            Self.logger.info(
                "Drag ended without active source tile=\(self.tileLogDescription(tile), privacy: .public)"
            )
            clearDragState()
            return
        }

        commitDragMutation(tile)

        performTransition {
            clearDragState()
        }
    }

    func commitDragMutation(_ tile: Tile) {
        if draggedTrashTargetTileID != nil {
            Self.logger.info(
                "Drag dropping on trash tile=\(self.tileLogDescription(tile), privacy: .public)"
            )
            if isPinnedReorderable(tileID: tile.id) {
                store.removePinnedItem(tileID: tile.id)
            } else if isTrailingReorderable(tileID: tile.id) {
                store.removeTrailingItem(tileID: tile.id)
            }
        } else if let groupTargetTileID = draggedAppFolderTargetTileID,
            draggedBundleIdentifier != nil {
            Self.logger.info(
                "Drag committing group tile=\(self.tileLogDescription(tile), privacy: .public)"
            )
            _ = store.groupApps(bundleIdentifiers: draggedSelectionBundleIdentifiers, intoTileID: groupTargetTileID)
        } else if hasCollectedAdditionalAppsDuringDrag {
            // Multi-app pickup is only used for grouping into an app or folder target.
            Self.logger.info(
                "Drag ended with collected apps tile=\(self.tileLogDescription(tile), privacy: .public)"
            )
        } else if isPinnedReorderable(tileID: tile.id) {
            commitPinnedDrag(tile)
        } else if isTrailingReorderable(tileID: tile.id) {
            commitTrailingDrag(tile)
        } else if let destinationIndex = draggedPinnedTileDestinationIndex,
            let bundleIdentifier = draggedBundleIdentifier {
            _ = store.pinApp(bundleIdentifier: bundleIdentifier, at: destinationIndex)
        }
    }
    func commitPinnedDrag(_ tile: Tile) {
        if let destinationIndex = draggedTrailingTileDestinationIndex,
            let trailingItem = draggedTile.flatMap(store.makeTrailingItem(from:)) {
            Self.logger.info(
                "Drag moving pinned->trailing tile=\(self.tileLogDescription(tile), privacy: .public)"
            )
            store.removePinnedItem(tileID: tile.id)
            store.insertTrailingItem(trailingItem, at: destinationIndex)
        } else {
            let finalPinnedTileIDs = previewPinnedBaseTiles.map(\.id)
            Self.logger.info(
                "Drag reordering pinned tile=\(self.tileLogDescription(tile), privacy: .public)"
            )
            if finalPinnedTileIDs != pinnedTileIDs {
                store.setPinnedTileOrder(ids: finalPinnedTileIDs)
            }
        }
    }
    func commitTrailingDrag(_ tile: Tile) {
        if let destinationIndex = draggedPinnedTileDestinationIndex,
            let pinnedItem = draggedTile.flatMap(store.makePinnedItem(from:)) {
            Self.logger.info(
                "Drag moving trailing->pinned tile=\(self.tileLogDescription(tile), privacy: .public)"
            )
            store.removeTrailingItem(tileID: tile.id)
            store.insertPinnedItem(pinnedItem, at: destinationIndex)
        } else {
            let finalTrailingTileIDs = previewTrailingTiles.map(\.id)
            Self.logger.info(
                "Drag reordering trailing tile=\(self.tileLogDescription(tile), privacy: .public)"
            )
            if finalTrailingTileIDs != trailingTileIDs {
                store.setTrailingTileOrder(ids: finalTrailingTileIDs)
            }
        }
    }

    var draggedBundleIdentifier: String? {
        guard let draggedTile, case .app(let app) = draggedTile.content else {
            return nil
        }
        return app.bundleIdentifier
    }

    func handleDragKeyDown(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
            event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask),
            event.charactersIgnoringModifiers == " "
        else {
            return false
        }

        return grabPickupCandidateDuringActiveDrag()
    }

    func grabPickupCandidateDuringActiveDrag() -> Bool {
        guard isCollectingAdditionalAppsDuringDrag,
            let pickupCandidateTileID = draggedPickupCandidateTileID,
            let bundleIdentifier = bundleIdentifier(forTileID: pickupCandidateTileID),
            !draggedSelectionTileIDs.contains(pickupCandidateTileID),
            !draggedSelectionBundleIdentifiers.contains(bundleIdentifier)
        else {
            return false
        }

        performTransition {
            draggedAdditionalTileIDs.append(pickupCandidateTileID)
            draggedPickupCandidateTileID = nil
            clearDragPreviewDestinations()
        }
        return true
    }

    func clearDragPreviewDestinations() {
        draggedAppFolderTargetTileID = nil
        draggedTrashTargetTileID = nil
        draggedPinnedTileDestinationIndex = nil
        draggedTrailingTileDestinationIndex = nil
        editMode.paletteDropDestination = nil
    }
}
