import AppKit
import OSLog

extension DockCanvasController {
    func clearDragState() {
        if draggedTileID != nil {
            Self.logger.debug(
                "Clearing drag state tileID=\(self.draggedTileID ?? "nil", privacy: .public)"
            )
        }
        draggedTileID = nil
        draggedTileOffset = 0
        draggedTileInitialFrame = nil
        draggedPinnedTileDestinationIndex = nil
        draggedTrailingTileDestinationIndex = nil
        draggedAppFolderTargetTileID = nil
        draggedTrashTargetTileID = nil
        draggedAdditionalTileIDs = []
        draggedPickupCandidateTileID = nil
    }

    func bundleIdentifier(for tile: Tile) -> String? {
        guard case .app(let app) = tile.content else {
            return nil
        }
        return app.bundleIdentifier.isEmpty ? nil : app.bundleIdentifier
    }

    func optionalIndexDescription(_ index: Int?) -> String {
        guard let index else {
            return "nil"
        }
        return String(index)
    }

    func dropSectionDescription(_ section: DockEditDropSection) -> String {
        switch section {
        case .pinned:
            return "pinned"
        case .trailing:
            return "trailing"
        }
    }

    func tileLogDescription(_ tile: Tile) -> String {
        "\(tile.id):\(tileKindDescription(tile))"
    }

    func tileKindDescription(_ tile: Tile) -> String {
        switch tile.content {
        case .app(let app): return "app(\(app.bundleIdentifier))"
        case .appFolder(let folder): return "appFolder(\(folder.identifier))"
        case .folder(let folder): return "folder(\(folder.url.lastPathComponent))"
        case .widget(let widget): return "widget(\(widget.kind.rawValue))"
        case .minimizedWindow(let window): return "minimizedWindow(\(window.windowIdentifier))"
        default: return String(describing: tile.content).components(separatedBy: "(").first ?? "tile"
        }
    }

    func bundleIdentifier(forTileID tileID: String) -> String? {
        guard let tile = store.tiles.first(where: { $0.id == tileID }) else {
            return nil
        }

        return bundleIdentifier(for: tile)
    }

    func appFolderDropTargetTileID(
        at location: CGPoint,
        selectedTileIDs: Set<String>,
        selectedBundleIdentifiers: [String]
    ) -> String? {
        let selectedBundleIdentifierSet = Set(selectedBundleIdentifiers)

        for tile in previewPinnedBaseTiles where !selectedTileIDs.contains(tile.id) {
            switch tile.content {
            case .app(let app):
                guard !selectedBundleIdentifierSet.contains(app.bundleIdentifier) else {
                    continue
                }
            case .minimizedWindow:
                continue
            case .appFolder(let folder):
                guard folder.bundleIdentifiers.allSatisfy({ !selectedBundleIdentifierSet.contains($0) }) else {
                    continue
                }
            case .launchpad, .startMenu, .widget, .smartStack, .folder, .spacer, .flexibleSpacer, .divider, .trash:
                continue
            }

            guard let frame = visibleTileFrames[tile.id] else {
                continue
            }

            let targetFrame = frame.insetBy(dx: frame.width * 0.18, dy: frame.height * 0.18)
            if targetFrame.contains(location) {
                return tile.id
            }
        }

        return nil
    }

    func trashDropTargetTileID(at location: CGPoint, sourceTileID: String) -> String? {
        for tile in trailingTiles where tile.id != sourceTileID {
            guard case .trash = tile.content,
                let frame = visibleTileFrames[tile.id],
                frame.contains(location)
            else {
                continue
            }
            return tile.id
        }
        return nil
    }

    func dragPickupCandidateTileID(at location: CGPoint) -> String? {
        guard isCollectingAdditionalAppsDuringDrag else {
            return nil
        }

        let selectedBundleIdentifiers = Set(draggedSelectionBundleIdentifiers)

        for tile in displayTiles.reversed() {
            guard !draggedSelectionTileIDs.contains(tile.id),
                let bundleIdentifier = bundleIdentifier(for: tile),
                !selectedBundleIdentifiers.contains(bundleIdentifier),
                let frame = visibleTileFrames[tile.id]
            else {
                continue
            }

            let targetFrame = frame.insetBy(dx: frame.width * 0.18, dy: frame.height * 0.18)
            if targetFrame.contains(location) {
                return tile.id
            }
        }

        return nil
    }

    func groupedOpenedAppFolderID(for tileID: String) -> String? {
        guard tileID.hasPrefix("folder-running:") else {
            return nil
        }

        let suffix = tileID.dropFirst("folder-running:".count)
        guard let separatorIndex = suffix.lastIndex(of: ":") else {
            return nil
        }

        return String(suffix[..<separatorIndex])
    }

    func projected(size: CGSize) -> CGFloat {
        position.isVertical ? size.height : size.width
    }

    func projected(point: CGPoint) -> CGFloat {
        position.isVertical ? point.y : point.x
    }

    func axisSize(value: CGFloat) -> CGSize {
        position.isVertical ? CGSize(width: 0, height: value) : CGSize(width: value, height: 0)
    }
}
