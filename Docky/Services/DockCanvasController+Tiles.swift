import AppKit
import OSLog

extension DockCanvasController {
    var displayTiles: [Tile] {
        guard let firstTile = store.tiles.first else {
            return store.tiles
        }

        // Shelve mode drops the leading Finder tile, so the first store
        // tile may be a regular pinned app — which is also surfaced via
        // `previewPinnedTiles`. Only pin the first tile to the front when
        // it actually is Finder; otherwise let the normal pinned-section
        // path render it once.
        let leadsWithFinder = firstTile.id == "pinned:com.apple.finder"
        var result: [Tile] = []
        if leadsWithFinder {
            result.append(firstTile)
        }
        result.append(contentsOf: previewPinnedTiles)
        var appendedTrailingSection = false

        let remainingTiles: ArraySlice<Tile> =
            leadsWithFinder
            ? store.tiles.dropFirst()
            : store.tiles[...]
        for tile in remainingTiles {
            if appendedTrailingSection {
                continue
            }

            if groupedOpenedAppFolderID(for: tile.id) != nil {
                continue
            }

            if tile.id == "divider:trailing" {
                result.append(tile)
                result.append(contentsOf: previewTrailingSectionTiles)
                appendedTrailingSection = true
                continue
            }

            if isPinnedReorderable(tileID: tile.id)
                || isTrailingReorderable(tileID: tile.id) {
                continue
            }
            result.append(tile)
        }

        // Theme-level layout insertions apply after the editor-preview
        // merge: applying them in `TileStore.rebuildTiles` would lose
        // anything anchored past `divider:trailing` because this
        // method re-builds that section from `previewTrailingSectionTiles`.
        return TileStore.applyingThemeLayoutInsertions(to: result)
    }

    var pinnedTiles: [Tile] {
        store.tiles.filter { isPinnedReorderable(tileID: $0.id) }
    }

    var pinnedTileIDs: [String] {
        pinnedTiles.map(\.id)
    }

    var groupedOpenedAppTilesByFolderID: [String: [Tile]] {
        let groupedEntries: [(folderID: String, tile: Tile)] = store.tiles.compactMap { tile in
            guard case .app = tile.content,
                let folderID = groupedOpenedAppFolderID(for: tile.id)
            else {
                return nil
            }
            return (folderID: folderID, tile: tile)
        }

        return Dictionary(grouping: groupedEntries, by: { $0.folderID }).mapValues { entries in
            entries.map { $0.tile }
        }
    }

    var trailingTiles: [Tile] {
        store.tiles.filter { isTrailingReorderable(tileID: $0.id) }
    }

    var trailingTileIDs: [String] {
        trailingTiles.map(\.id)
    }

    var previewPinnedTiles: [Tile] {
        expandedPinnedTiles(from: previewPinnedBaseTiles)
    }

    var draggedAppFolderIdentifier: String? {
        guard let draggedTile,
            case .appFolder(let folder) = draggedTile.content
        else {
            return nil
        }

        return folder.identifier
    }

    var previewPinnedBaseTiles: [Tile] {
        var remainingPinnedTiles = pinnedTiles
        if !draggedAdditionalTileIDs.isEmpty {
            let hiddenTileIDs = Set(draggedAdditionalTileIDs)
            remainingPinnedTiles.removeAll { hiddenTileIDs.contains($0.id) }
        }

        guard let destinationIndex = activePinnedDropDestinationIndex else {
            return remainingPinnedTiles
        }

        if let draggedTileID {
            remainingPinnedTiles.removeAll { $0.id == draggedTileID }
        }
        let clampedDestinationIndex = min(max(destinationIndex, 0), remainingPinnedTiles.count)
        if let draggedTile, isDraggingPinnedTile || store.makePinnedItem(from: draggedTile) != nil {
            remainingPinnedTiles.insert(draggedTile, at: clampedDestinationIndex)
        } else if let palettePreviewTile {
            remainingPinnedTiles.insert(palettePreviewTile, at: clampedDestinationIndex)
        } else if case .app(_, let appTile) = dockDrag.kind {
            remainingPinnedTiles.insert(
                Tile(id: "drop-preview", content: .app(appTile)),
                at: clampedDestinationIndex
            )
        }
        return remainingPinnedTiles
    }

    func expandedPinnedTiles(from baseTiles: [Tile]) -> [Tile] {
        var result: [Tile] = []

        for tile in baseTiles {
            result.append(tile)

            guard case .appFolder(let folder) = tile.content else {
                continue
            }

            guard folder.identifier != draggedAppFolderIdentifier else {
                continue
            }

            result.append(
                contentsOf: (groupedOpenedAppTilesByFolderID[folder.identifier] ?? []).filter {
                    !isHiddenForActiveDrag(tileID: $0.id)
                })
        }

        return result
    }

    var palettePreviewTile: Tile? {
        guard let paletteDrag = editMode.paletteDrag else {
            return nil
        }

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
            let span = resolvedPaletteWidgetSpan(
                ownerBundleIdentifier: ownerBundleIdentifier,
                kind: kind,
                requestedSpan: paletteDrag.widgetSpan
            )
            return Tile(
                id: "editor-preview:widget",
                content: .widget(
                    WidgetTile(
                        identifier: "editor-preview:widget",
                        title: kind.title,
                        kind: kind,
                        ownerBundleIdentifier: ownerBundleIdentifier,
                        span: span
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

    var previewTrailingTiles: [Tile] {
        var remainingTrailingTiles = trailingTiles
        if !draggedAdditionalTileIDs.isEmpty {
            let hiddenTileIDs = Set(draggedAdditionalTileIDs)
            remainingTrailingTiles.removeAll { hiddenTileIDs.contains($0.id) }
        }

        guard let destinationIndex = activeTrailingDropDestinationIndex else {
            return remainingTrailingTiles
        }

        if let draggedTileID {
            remainingTrailingTiles.removeAll { $0.id == draggedTileID }
        }
        let clampedDestinationIndex = min(max(destinationIndex, 0), remainingTrailingTiles.count)
        if let draggedTile, store.makeTrailingItem(from: draggedTile) != nil {
            remainingTrailingTiles.insert(draggedTile, at: clampedDestinationIndex)
        } else if let palettePreviewTile, makeTrailingItem(from: editMode.paletteDrag) != nil {
            remainingTrailingTiles.insert(palettePreviewTile, at: clampedDestinationIndex)
        } else if case .folder(_, let folderTile) = dockDrag.kind {
            remainingTrailingTiles.insert(
                Tile(id: "drop-preview", content: .folder(folderTile)),
                at: clampedDestinationIndex
            )
        }
        return remainingTrailingTiles
    }

    var previewTrailingSectionTiles: [Tile] {
        let minimizedWindowTiles = store.tiles.compactMap { tile in
            if case .minimizedWindow = tile.content {
                return tile
            }
            return nil
        }

        guard !minimizedWindowTiles.isEmpty else {
            return previewTrailingTiles
        }

        var result: [Tile] = []
        var insertedMinimizedWindows = false

        for tile in previewTrailingTiles {
            if !insertedMinimizedWindows, case .trash = tile.content {
                result.append(contentsOf: minimizedWindowTiles)
                insertedMinimizedWindows = true
            }
            result.append(tile)
        }

        if !insertedMinimizedWindows {
            result.append(contentsOf: minimizedWindowTiles)
        }

        return result
    }

    var draggedTile: Tile? {
        guard let draggedTileID else {
            return nil
        }

        return store.tiles.first { $0.id == draggedTileID }
    }

    var orderedDraggedSelectionTileIDs: [String] {
        var result: [String] = []
        if let draggedTileID {
            result.append(draggedTileID)
        }

        for tileID in draggedAdditionalTileIDs where !result.contains(tileID) {
            result.append(tileID)
        }

        return result
    }

    var draggedSelectionTileIDs: Set<String> {
        Set(orderedDraggedSelectionTileIDs)
    }

    var draggedSelectionBundleIdentifiers: [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for tileID in orderedDraggedSelectionTileIDs {
            guard let bundleIdentifier = bundleIdentifier(forTileID: tileID),
                seen.insert(bundleIdentifier).inserted
            else {
                continue
            }
            result.append(bundleIdentifier)
        }

        return result
    }

    var dragPreviewBundleIdentifiers: [String] {
        Array(draggedSelectionBundleIdentifiers.dropFirst().suffix(3))
    }

    var isCollectingAdditionalAppsDuringDrag: Bool {
        draggedBundleIdentifier != nil
    }

    var hasCollectedAdditionalAppsDuringDrag: Bool {
        !draggedAdditionalTileIDs.isEmpty
    }

    var draggedTilePosition: CGPoint {
        guard let frame = draggedTileInitialFrame else {
            return .zero
        }

        return CGPoint(x: frame.midX, y: frame.midY)
    }

    var activePinnedDropDestinationIndex: Int? {
        if draggedTileID == nil {
            if dockDrag.destinationSection == .pinned, let externalIndex = dockDrag.destinationIndex {
                return externalIndex
            }
            guard editMode.paletteDropDestination?.section == .pinned else {
                return nil
            }
            return editMode.paletteDropDestination?.index
        }
        return draggedPinnedTileDestinationIndex
    }

    var activeTrailingDropDestinationIndex: Int? {
        if draggedTileID == nil {
            if dockDrag.destinationSection == .trailing, let externalIndex = dockDrag.destinationIndex {
                return externalIndex
            }
            guard editMode.paletteDropDestination?.section == .trailing else {
                return nil
            }
            return editMode.paletteDropDestination?.index
        }
        return draggedTrailingTileDestinationIndex
    }
}
