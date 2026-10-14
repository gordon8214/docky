import AppKit
import OSLog

extension DockCanvasController {
    func updatePreviewDestination(
        at positionValue: CGFloat, sourceTileID: String,
        isTileDrag: Bool, canDropIntoPinned: Bool, canDropIntoTrailing: Bool
    ) {
        let section: DockEditDropSection?
        if canDropIntoPinned && isPointInPinnedDropRegion(positionValue) {
            section = .pinned
        } else if canDropIntoTrailing && isPointInTrailingDropRegion(positionValue) {
            section = .trailing
        } else {
            section = nil
        }
        guard let section else {
            if isTileDrag {
                draggedPinnedTileDestinationIndex = nil
                draggedTrailingTileDestinationIndex = nil
            } else if editMode.paletteDropDestination != nil {
                editMode.paletteDropDestination = nil
            }
            return
        }
        updateDropDestination(for: section, at: positionValue, sourceTileID: sourceTileID, isTileDrag: isTileDrag)
        if isTileDrag {
            switch section {
            case .pinned: draggedTrailingTileDestinationIndex = nil
            case .trailing: draggedPinnedTileDestinationIndex = nil
            }
        }
    }

    func updateDropDestination(
        for section: DockEditDropSection,
        at positionValue: CGFloat,
        sourceTileID: String,
        isTileDrag: Bool
    ) {
        let visibleTiles = previewTiles(for: section).filter { $0.id != sourceTileID }
        let destinationIndex = DockAxisGeometry.insertionIndex(
            at: positionValue,
            frames: visibleTiles.map { tileFrames[$0.id] },
            vertical: position.isVertical
        )

        let currentDestinationIndex = currentDropDestinationIndex(for: section, isTileDrag: isTileDrag)
        guard currentDestinationIndex != destinationIndex else {
            return
        }

        Self.logger.debug(
            "Drag destination updated sourceTileID=\(sourceTileID, privacy: .public)"
        )

        performTransition {
            setDropDestination(section: section, index: destinationIndex, isTileDrag: isTileDrag)
        }
    }
}
