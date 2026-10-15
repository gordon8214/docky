import AppKit
import OSLog

extension DockCanvasController {
    var effectiveTileSize: CGFloat {
        baseTileSize
    }

    var tileHeight: CGFloat {
        effectiveTileSize + WindowsTaskbarStyle.Tray.verticalPadding * 2
    }

    var baseTileSize: CGFloat {
        dockSettings.displayTileSize
    }

    var position: ResolvedDockWindowPosition {
        preferences.effectiveWindowPosition.resolved(systemOrientation: dockSettings.orientation)
    }

    /// Frame size of a dragged tile's preview.
    func tileFrameSize(for tile: Tile) -> CGSize {
        DockTileGeometry.size(for: tile, tileSize: effectiveTileSize, tileHeight: tileHeight, position: position)
    }

    func isPinnedReorderable(tileID: String) -> Bool {
        store.isPinnedReorderable(tileID: tileID)
    }

    func isTrailingReorderable(tileID: String) -> Bool {
        store.isTrailingReorderable(tileID: tileID)
    }

    func isTileDraggable(_ tile: Tile) -> Bool {
        // Inline children of an app folder (rendered next to the folder
        // tile in inline / grouped-opened modes) are derived from the
        // folder's contents — reordering them as standalone tiles would
        // detach the relationship. Force users through the explicit
        // "Remove from Folder" action instead.
        if tile.id.hasPrefix("folder-running:") {
            return false
        }
        switch tile.content {
        case .app(let app):
            return !app.bundleIdentifier.isEmpty && app.bundleIdentifier != "com.apple.finder"
        case .minimizedWindow:
            return false
        case .appFolder:
            return isPinnedReorderable(tileID: tile.id)
        case .widget, .smartStack:
            return isPinnedReorderable(tileID: tile.id) || isTrailingReorderable(tileID: tile.id)
        case .launchpad, .startMenu, .spacer, .flexibleSpacer, .divider:
            return editMode.isActive && (isPinnedReorderable(tileID: tile.id) || isTrailingReorderable(tileID: tile.id))
        case .folder, .trash:
            return editMode.isActive && isTrailingReorderable(tileID: tile.id)
        }
    }
}
