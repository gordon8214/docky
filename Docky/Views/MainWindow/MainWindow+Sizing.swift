import AppKit
import Combine
import QuartzCore

extension MainWindow {
    func sizingPreviewTiles() -> [Tile] {
        let externalAppDropPreview: AppTile? = {
            if case .app(_, let tile) = DockDragService.shared.kind { return tile }
            return nil
        }()
        let externalFolderDropPreview: FolderTile? = {
            // Only grow the chrome when there's an actual placement: cursor in the
            // trailing drop region with a resolved insertion index. Open-with mode
            // (over an app tile) and idle hovering both leave chrome unchanged.
            guard DockDragService.shared.documentTargetTileID == nil,
                DockDragService.shared.destinationSection == .trailing,
                DockDragService.shared.destinationIndex != nil,
                case .folder(_, let tile) = DockDragService.shared.kind
            else {
                return nil
            }
            return tile
        }()
        return DockTileGeometry.previewedTiles(
            from: tileStore.tiles,
            paletteDrag: editMode.paletteDrag,
            paletteDropDestination: editMode.paletteDropDestination,
            externalAppDropPreview: externalAppDropPreview,
            externalFolderDropPreview: externalFolderDropPreview
        )
    }

    struct ContentLayout {
        let size: CGSize
        let scale: CGFloat
        let availableAxisLength: CGFloat
    }

    func resolveContentLayout(bounds layoutBounds: CGRect, position: ResolvedDockWindowPosition,
                              horizontalPadding: CGFloat, verticalPadding: CGFloat) -> ContentLayout {
        let horizontalContentPadding = horizontalPadding
        let verticalContentPadding = verticalPadding
        let baseTileSize = dockSettings.displayTileSize
        let baseTileHeight = baseTileSize + preferences.effectiveTileVerticalPadding * 2
        let sizingTiles = sizingPreviewTiles()
        let naturalContentSize = DockTileGeometry.contentSize(
            tiles: sizingTiles,
            tileSize: baseTileSize,
            tileHeight: baseTileHeight,
            tileSpacing: preferences.effectiveTileSpacing,
            position: position
        )
        let alongAxisContentPadding = position.isVertical ? verticalContentPadding : horizontalContentPadding
        let availableAxisLength = availableContentAxisLength(
            bounds: layoutBounds, padding: alongAxisContentPadding, content: naturalContentSize, position: position)
        let compactsWidgetsForOverflow = shouldCompactWidgetsForOverflow(
            contentSize: naturalContentSize,
            availableAxisLength: availableAxisLength,
            position: position
        )
        let baseContentSize = DockTileGeometry.contentSize(
            tiles: sizingTiles,
            tileSize: baseTileSize,
            tileHeight: baseTileHeight,
            tileSpacing: preferences.effectiveTileSpacing,
            position: position,
            compactWidgets: compactsWidgetsForOverflow
        )
        let contentScale = overflowContentScale(
            for: baseContentSize,
            availableAxisLength: availableAxisLength,
            position: position
        )
        layout.setContentScale(contentScale)
        layout.setCompactsWidgetsForOverflow(compactsWidgetsForOverflow)

        let displayedContentSize = scaledContentSize(
            tiles: sizingTiles, scale: contentScale, position: position, compact: compactsWidgetsForOverflow)
        let displayedChromeAxisLength =
            preferences.effectiveWindowAxisSizing == .fullAxis
            ? availableAxisLength
            : min(axisLength(of: displayedContentSize, position: position), availableAxisLength)
        layout.setChromeSize(
            displayedChromeSize(
                for: displayedContentSize,
                displayedAxisLength: displayedChromeAxisLength,
                position: position
            ))
        return ContentLayout(size: displayedContentSize, scale: contentScale, availableAxisLength: availableAxisLength)
    }

    func availableContentAxisLength(
        bounds layoutBounds: CGRect, padding alongAxisContentPadding: CGFloat,
        content naturalContentSize: CGSize, position: ResolvedDockWindowPosition
    ) -> CGFloat {
        let unreservedAvailableAxisLength = max(
            0,
            axisLength(of: layoutBounds.size, position: position) - alongAxisContentPadding
        )
        let contentAvailableAxisLength = max(
            0,
            unreservedAvailableAxisLength
                - (shouldReserveStatusBarLength(
                    for: naturalContentSize,
                    availableAxisLength: unreservedAvailableAxisLength,
                    position: position
                ) ? reservedStatusBarLength : 0)
        )
        return
            preferences.effectiveWindowAxisSizing == .fullAxis
            ? unreservedAvailableAxisLength
            : contentAvailableAxisLength
    }

    func scaledContentSize(tiles sizingTiles: [Tile], scale contentScale: CGFloat,
                           position: ResolvedDockWindowPosition, compact compactsWidgetsForOverflow: Bool) -> CGSize {
        let baseTileSize = dockSettings.displayTileSize
        let scaledTileSize = baseTileSize * contentScale
        let scaledTileHeight = scaledTileSize + (preferences.effectiveTileVerticalPadding * contentScale * 2)
        let scaledTileSpacing = preferences.effectiveTileSpacing * contentScale
        return DockTileGeometry.contentSize(
            tiles: sizingTiles,
            tileSize: scaledTileSize,
            tileHeight: scaledTileHeight,
            tileSpacing: scaledTileSpacing,
            position: position,
            compactWidgets: compactsWidgetsForOverflow,
            edgePadding: DockTileGeometry.edgePadding * contentScale
        )
    }

}
