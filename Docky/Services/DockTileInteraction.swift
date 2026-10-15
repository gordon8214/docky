import AppKit
import Combine
import OSLog
import QuickLookThumbnailing

@propertyWrapper
struct DockInteractionState<Value> {
    final class Storage {
        var value: Value
        init(_ value: Value) { self.value = value }
    }
    private let storage: Storage
    init(wrappedValue: Value) { storage = Storage(wrappedValue) }
    var wrappedValue: Value {
        get { storage.value }
        nonmutating set { storage.value = newValue }
    }
}

/// Tile commands and delayed interactions, shared by the native presentation.
@MainActor
struct DockTileInteraction {
    static let logger = Logger(subsystem: "gt.quintero.Docky", category: "TileTap")
    var tile: Tile
    var isDragging: Bool
    var isDocumentDropTarget: Bool
    var isAppFolderDropTarget: Bool
    var isTrashDropTarget: Bool
    /// Caller-supplied icon extent, so proportional metrics (corner radius,
    /// content padding) follow the rendered frame. `nil` falls back to the
    /// taskbar's button size.
    var renderedTileSize: CGFloat?
    let dockSettings = DockSettingsService.shared
    var preferences = DockyPreferences.shared
    var workspace = WorkspaceService.shared
    var mediaPlayback = MediaPlaybackService.shared
    var editMode = DockEditModeService.shared
    var widgetExpansion = WidgetExpansionWindowController.shared
    var dockDrag = DockDragService.shared
    @DockInteractionState var isHovering = false
    @DockInteractionState var isTooltipPresented = false
    @DockInteractionState var tooltipDelayTask: Task<Void, Never>?
    @DockInteractionState var globalTileFrame: CGRect = .zero
    @DockInteractionState var isFolderPopoverPresented = false
    @DockInteractionState var isFolderListMenuPresented = false
    @DockInteractionState var isAppFolderPopoverPresented = false
    @DockInteractionState var isAppFolderListMenuPresented = false
    @DockInteractionState var isContextMenuPresented = false
    @DockInteractionState var widgetExpansionTask: Task<Void, Never>?
    @DockInteractionState var folderSnapshot: FolderContentsSnapshot = .loaded([])
    @DockInteractionState var lastFolderPopoverDismissedAt: TimeInterval = 0
    @DockInteractionState var windowPreviewDelayTask: Task<Void, Never>?
    var windowPreview = WindowPreviewWindowController.shared
    var dockBadges = DockBadgeService.shared

    static let finderBundleIdentifier = "com.apple.finder"
    static let folderPopoverRetapGuardInterval: TimeInterval = 0.25

}
