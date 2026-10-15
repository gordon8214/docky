import AppKit
import OSLog

extension DockRootView {
    private static let logger = Logger(subsystem: "gt.quintero.Docky", category: "TrashDrop")

    func commitAppDrop(_ tile: AppTile) -> Bool {
        let service = DockDragService.shared
        if let targetID = service.documentTargetTileID, targetID != service.sourceFolderTileID {
            let grouped = TileStore.shared.groupApps(
                bundleIdentifiers: [tile.bundleIdentifier], intoTileID: targetID)
            if grouped, let sourceID = service.sourceFolderTileID {
                TileStore.shared.removeAppFromFolder(
                    tileID: sourceID, bundleIdentifier: tile.bundleIdentifier)
            }
            return grouped
        }
        guard let index = service.destinationIndex else { return false }
        if let sourceID = service.sourceFolderTileID, service.sourceFolderBundleIdentifier == tile.bundleIdentifier {
            TileStore.shared.removeAppFromFolder(
                tileID: sourceID, bundleIdentifier: tile.bundleIdentifier)
        }
        return TileStore.shared.pinApp(bundleIdentifier: tile.bundleIdentifier, at: index)
    }
    func commitFolderDrop(_ url: URL, tile: FolderTile) -> Bool {
        // A folder dropped on an app opens with it.
        if DockDragService.shared.documentTargetTileID != nil { return commitDocumentDrop([url]) }
        guard let index = DockDragService.shared.destinationIndex else { return false }
        TileStore.shared.insertTrailingItem(.folder(url: url, displayName: tile.displayName), at: index)
        return true
    }
    func commitDocumentDrop(_ urls: [URL]) -> Bool {
        guard let targetID = DockDragService.shared.documentTargetTileID,
            let target = TileStore.shared.tiles.first(where: { $0.id == targetID })
        else { return false }
        if target.content.isTrash { return commitTrashDrop(urls) }
        guard case .app(let app) = target.content, !app.bundleIdentifier.isEmpty else { return false }
        WorkspaceService.shared.open(fileURLs: urls, withApplicationBundleIdentifier: app.bundleIdentifier)
        return true
    }
    /// Moves dropped items to the Trash. Running apps, Docky itself, and apps dragged out
    /// of an app folder stay where they are.
    func commitTrashDrop(_ urls: [URL]) -> Bool {
        guard DockDragService.shared.sourceFolderTileID == nil else { return false }
        var trashed = false
        for url in urls where url.isFileURL && DockCanvasController.canTrash(url) {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                trashed = true
            } catch {
                Self.logger.error(
                    "Couldn't move \(url.path, privacy: .public) to the Trash: \(error, privacy: .public)")
            }
        }
        return trashed
    }
    func isTrash(_ tileID: String?) -> Bool {
        TileStore.shared.tiles.first { $0.id == tileID }?.content.isTrash == true
    }
    func commitPaletteDrop() -> Bool {
        guard let drag = DockEditModeService.shared.paletteDrag,
            let destination = DockEditModeService.shared.paletteDropDestination
        else { return false }
        defer {
            DockEditModeService.shared.endPaletteDrag()
            DockDragService.shared.cursorLocation = nil
        }
        switch destination.section {
        case .pinned:
            guard let item = DockTileGeometry.makePinnedItem(from: drag) else { return false }
            TileStore.shared.insertPinnedItem(item, at: destination.index)
        case .trailing:
            guard let item = DockTileGeometry.makeTrailingItem(from: drag) else { return false }
            TileStore.shared.insertTrailingItem(item, at: destination.index)
        }
        return true
    }
}
