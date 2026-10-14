import AppKit
import Combine
import OSLog

struct CanvasGeometry { let size: CGSize }
struct DockPointerDrag {
    let location: CGPoint
    let translation: CGSize
}

/// Owns layout and drag state independently of the view hierarchy.
@MainActor
final class DockCanvasController {
    static let edgePadding: CGFloat = DockTileGeometry.edgePadding
    static let logger = Logger(subsystem: "gt.quintero.Docky", category: "TileDrag")
    var onChange: (() -> Void)?
    func performTransition(_ changes: () -> Void) {
        changes()
        onChange?()
    }
    var store = TileStore.shared
    let dockSettings = DockSettingsService.shared
    var layout = DockLayoutService.shared
    var preferences = DockyPreferences.shared
    var editMode = DockEditModeService.shared
    var dockDrag = DockDragService.shared
    let magnification = DockMagnificationService.shared

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

}
