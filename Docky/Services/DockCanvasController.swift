import AppKit
import Combine
import OSLog

struct DockPointerDrag {
    let location: CGPoint
    let translation: CGSize
}

/// Owns layout and drag state independently of the view hierarchy.
@MainActor
final class DockCanvasController {
    static let logger = Logger(subsystem: "gt.quintero.Docky", category: "TileDrag")
    var onChange: (() -> Void)?
    func performTransition(_ changes: () -> Void) {
        changes()
        onChange?()
    }
    var store = TileStore.shared
    let dockSettings = DockSettingsService.shared
    var preferences = DockyPreferences.shared
    var editMode = DockEditModeService.shared
    var dockDrag = DockDragService.shared

    var draggedTileID: String?
    var draggedTileOffset: CGFloat = 0
    var draggedTileInitialFrame: CGRect?
    var draggedPinnedTileDestinationIndex: Int?
    var draggedTrailingTileDestinationIndex: Int?
    var draggedAppFolderTargetTileID: String?
    var draggedTrashTargetTileID: String?
    var draggedAdditionalTileIDs: [String] = []
    var draggedPickupCandidateTileID: String?
    var tileFrames: [String: CGRect] = [:]
    var visibleTileFrames: [String: CGRect] = [:]
    /// The tray's frame in canvas coordinates. Trailing items (folders, stacks,
    /// widgets, and Trash's button) live there, so it is where they are dropped.
    var trayFrame: CGRect = .zero

}
