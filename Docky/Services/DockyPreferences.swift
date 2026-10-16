//
//  DockyPreferences.swift
//  Docky
//
//  Docky's own user-adjustable settings. Persisted to UserDefaults.
//  Consume via `DockyPreferences.shared`; the class is `@Observable`
//  so SwiftUI views auto-track only the properties they read in body
//  and Combine consumers bridge through `observe(_:)` from
//  `ObservationBridge.swift`.
//

import AppKit
import Foundation
import Observation

enum PinnedTileItemKind: String, Codable, Equatable {
    case app
    case appFolder
    case launchpad
    case startMenu
    case widget
    case smartStack
    case spacer
    case flexibleSpacer
    case divider
}

enum TrailingTileItemKind: String, Codable, Equatable {
    case folder
    case trash
    case widget
    case smartStack
    case spacer
    case flexibleSpacer
    case divider
}

struct PinnedTileItem: Codable, Equatable, Identifiable {
    let id: String
    let kind: PinnedTileItemKind
    let bundleIdentifier: String?
    let folderDisplayName: String?
    let folderBundleIdentifiers: [String]
    let appFolderDisplayMode: AppFolderTileDisplayMode?
    let folderContentViewMode: FolderTileContentViewMode?
    let widgetKind: WidgetKind?
    let widgetOwnerBundleIdentifier: String?
    let widgetSpan: TileSpan?
    let hiddenWidgetOwnerBundleIdentifiers: [String]
    /// Optional so pre-existing persisted items decode as nil (default behavior).
    var widgetSettings: WidgetSettings? = nil

    nonisolated static func app(bundleIdentifier: String) -> Self {
        Self(
            id: "app:\(bundleIdentifier)",
            kind: .app,
            bundleIdentifier: bundleIdentifier,
            folderDisplayName: nil,
            folderBundleIdentifiers: [],
            appFolderDisplayMode: nil,
            folderContentViewMode: nil,
            widgetKind: nil,
            widgetOwnerBundleIdentifier: nil,
            widgetSpan: nil,
            hiddenWidgetOwnerBundleIdentifiers: []
        )
    }

    nonisolated static func appFolder(
        id: String = "custom:\(UUID().uuidString)",
        displayName: String = "Folder",
        bundleIdentifiers: [String],
        displayMode: AppFolderTileDisplayMode = .grid,
        contentViewMode: FolderTileContentViewMode = .grid
    ) -> Self {
        Self(
            id: id,
            kind: .appFolder,
            bundleIdentifier: nil,
            folderDisplayName: displayName,
            folderBundleIdentifiers: bundleIdentifiers,
            appFolderDisplayMode: displayMode,
            folderContentViewMode: contentViewMode,
            widgetKind: nil,
            widgetOwnerBundleIdentifier: nil,
            widgetSpan: nil,
            hiddenWidgetOwnerBundleIdentifiers: []
        )
    }

    nonisolated static func widget(kind: WidgetKind, ownerBundleIdentifier: String, span: TileSpan = .three) -> Self {
        Self(
            id: "custom:\(UUID().uuidString)",
            kind: .widget,
            bundleIdentifier: nil,
            folderDisplayName: nil,
            folderBundleIdentifiers: [],
            appFolderDisplayMode: nil,
            folderContentViewMode: nil,
            widgetKind: kind,
            widgetOwnerBundleIdentifier: ownerBundleIdentifier,
            widgetSpan: span,
            hiddenWidgetOwnerBundleIdentifiers: []
        )
    }

    nonisolated static func launchpad(id: String = "custom:\(UUID().uuidString)") -> Self {
        Self(
            id: id,
            kind: .launchpad,
            bundleIdentifier: nil,
            folderDisplayName: nil,
            folderBundleIdentifiers: [],
            appFolderDisplayMode: nil,
            folderContentViewMode: nil,
            widgetKind: nil,
            widgetOwnerBundleIdentifier: nil,
            widgetSpan: nil,
            hiddenWidgetOwnerBundleIdentifiers: []
        )
    }

    nonisolated static func startMenu(id: String = "custom:\(UUID().uuidString)") -> Self {
        Self(
            id: id,
            kind: .startMenu,
            bundleIdentifier: nil,
            folderDisplayName: nil,
            folderBundleIdentifiers: [],
            appFolderDisplayMode: nil,
            folderContentViewMode: nil,
            widgetKind: nil,
            widgetOwnerBundleIdentifier: nil,
            widgetSpan: nil,
            hiddenWidgetOwnerBundleIdentifiers: []
        )
    }

    @MainActor static func smartStack(
        hiddenWidgetOwnerBundleIdentifiers: [String] = WidgetCatalog.defaultHiddenSmartStackOwnerBundleIdentifiers
    ) -> Self {
        Self(
            id: "custom:\(UUID().uuidString)",
            kind: .smartStack,
            bundleIdentifier: nil,
            folderDisplayName: nil,
            folderBundleIdentifiers: [],
            appFolderDisplayMode: nil,
            folderContentViewMode: nil,
            widgetKind: nil,
            widgetOwnerBundleIdentifier: nil,
            widgetSpan: nil,
            hiddenWidgetOwnerBundleIdentifiers: hiddenWidgetOwnerBundleIdentifiers
        )
    }
}

struct TrailingTileItem: Codable, Equatable, Identifiable {
    let id: String
    let kind: TrailingTileItemKind
    let sourceTileID: String?
    let folderURL: URL?
    let folderDisplayName: String?
    let folderDisplayMode: FolderTileDisplayMode?
    let folderContentViewMode: FolderTileContentViewMode?
    let folderSortMode: FolderTileSortMode?
    let widgetKind: WidgetKind?
    let widgetOwnerBundleIdentifier: String?
    let widgetSpan: TileSpan?
    let hiddenWidgetOwnerBundleIdentifiers: [String]
    /// Optional so pre-existing persisted items decode as nil (default behavior).
    var widgetSettings: WidgetSettings? = nil

    var effectiveFolderDisplayMode: FolderTileDisplayMode {
        folderDisplayMode ?? .contents
    }

    var effectiveFolderContentViewMode: FolderTileContentViewMode {
        folderContentViewMode ?? .grid
    }

    var effectiveFolderSortMode: FolderTileSortMode {
        folderSortMode ?? .dateAdded
    }

    nonisolated init(
        id: String,
        kind: TrailingTileItemKind,
        sourceTileID: String? = nil,
        folderURL: URL? = nil,
        folderDisplayName: String? = nil,
        folderDisplayMode: FolderTileDisplayMode? = nil,
        folderContentViewMode: FolderTileContentViewMode? = nil,
        folderSortMode: FolderTileSortMode? = nil,
        widgetKind: WidgetKind? = nil,
        widgetOwnerBundleIdentifier: String? = nil,
        widgetSpan: TileSpan? = nil,
        hiddenWidgetOwnerBundleIdentifiers: [String] = [],
        widgetSettings: WidgetSettings? = nil
    ) {
        self.id = id
        self.kind = kind
        self.sourceTileID = sourceTileID
        self.folderURL = folderURL
        self.folderDisplayName = folderDisplayName
        self.folderDisplayMode = folderDisplayMode
        self.folderContentViewMode = folderContentViewMode
        self.folderSortMode = folderSortMode
        self.widgetKind = widgetKind
        self.widgetOwnerBundleIdentifier = widgetOwnerBundleIdentifier
        self.widgetSpan = widgetSpan
        self.hiddenWidgetOwnerBundleIdentifiers = hiddenWidgetOwnerBundleIdentifiers
        self.widgetSettings = widgetSettings
    }

    nonisolated static func folder(
        sourceTileID: String,
        displayMode: FolderTileDisplayMode = .contents,
        contentViewMode: FolderTileContentViewMode = .grid,
        sortMode: FolderTileSortMode = .dateAdded
    ) -> Self {
        Self(
            id: "folder:\(sourceTileID)",
            kind: .folder,
            sourceTileID: sourceTileID,
            folderURL: nil,
            folderDisplayName: nil,
            folderDisplayMode: displayMode,
            folderContentViewMode: contentViewMode,
            folderSortMode: sortMode,
            widgetKind: nil,
            widgetOwnerBundleIdentifier: nil,
            widgetSpan: nil,
            hiddenWidgetOwnerBundleIdentifiers: []
        )
    }

    nonisolated static func folder(
        id: String = "custom-folder:\(UUID().uuidString)",
        url: URL,
        displayName: String,
        displayMode: FolderTileDisplayMode = .contents,
        contentViewMode: FolderTileContentViewMode = .grid,
        sortMode: FolderTileSortMode = .dateAdded
    ) -> Self {
        Self(
            id: id,
            kind: .folder,
            sourceTileID: nil,
            folderURL: url,
            folderDisplayName: displayName,
            folderDisplayMode: displayMode,
            folderContentViewMode: contentViewMode,
            folderSortMode: sortMode,
            widgetKind: nil,
            widgetOwnerBundleIdentifier: nil,
            widgetSpan: nil,
            hiddenWidgetOwnerBundleIdentifiers: []
        )
    }

    nonisolated static func trash() -> Self {
        Self(
            id: "trash",
            kind: .trash,
            sourceTileID: nil,
            folderURL: nil,
            folderDisplayName: nil,
            folderDisplayMode: nil,
            folderContentViewMode: nil,
            widgetKind: nil,
            widgetOwnerBundleIdentifier: nil,
            widgetSpan: nil,
            hiddenWidgetOwnerBundleIdentifiers: []
        )
    }

    nonisolated static func widget(kind: WidgetKind, ownerBundleIdentifier: String, span: TileSpan = .three) -> Self {
        Self(
            id: "custom:\(UUID().uuidString)",
            kind: .widget,
            sourceTileID: nil,
            folderURL: nil,
            folderDisplayName: nil,
            folderDisplayMode: nil,
            folderContentViewMode: nil,
            widgetKind: kind,
            widgetOwnerBundleIdentifier: ownerBundleIdentifier,
            widgetSpan: span,
            hiddenWidgetOwnerBundleIdentifiers: []
        )
    }

    @MainActor static func smartStack(
        hiddenWidgetOwnerBundleIdentifiers: [String] = WidgetCatalog.defaultHiddenSmartStackOwnerBundleIdentifiers
    ) -> Self {
        Self(
            id: "custom:\(UUID().uuidString)",
            kind: .smartStack,
            sourceTileID: nil,
            folderURL: nil,
            folderDisplayName: nil,
            folderDisplayMode: nil,
            folderContentViewMode: nil,
            widgetKind: nil,
            widgetOwnerBundleIdentifier: nil,
            widgetSpan: nil,
            hiddenWidgetOwnerBundleIdentifiers: hiddenWidgetOwnerBundleIdentifiers
        )
    }
}

enum DockWindowPosition: String, CaseIterable, Identifiable {
    case system
    case top
    case left
    case right
    case bottom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .top: String(localized: "Top")
        case .left: String(localized: "Left")
        case .right: String(localized: "Right")
        case .bottom: String(localized: "Bottom")
        }
    }

    func resolved(systemOrientation: DockSettingsService.Orientation) -> ResolvedDockWindowPosition {
        switch self {
        case .system:
            switch systemOrientation {
            case .bottom: .bottom
            case .left: .left
            case .right: .right
            }
        case .top:
            .top
        case .left:
            .left
        case .right:
            .right
        case .bottom:
            .bottom
        }
    }
}

enum DockWindowDisplayTarget: String, CaseIterable, Identifiable {
    case primaryDisplay
    case displayContainingPointer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .primaryDisplay: String(localized: "Primary Display")
        case .displayContainingPointer: String(localized: "Display With Pointer")
        }
    }
}

enum DockWindowSpaceBehavior: String, CaseIterable, Identifiable {
    case activeSpace
    case allSpaces

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activeSpace: String(localized: "Active Space")
        case .allSpaces: String(localized: "All Spaces")
        }
    }

    func collectionBehavior(includesFullScreenAuxiliary: Bool) -> NSWindow.CollectionBehavior {
        var behavior: NSWindow.CollectionBehavior = [.stationary, .ignoresCycle]
        behavior.insert(self == .allSpaces ? .canJoinAllSpaces : .moveToActiveSpace)
        if includesFullScreenAuxiliary { behavior.insert(.fullScreenAuxiliary) }
        return behavior
    }

}

/// Behavior when an app tile is clicked while that app is already frontmost
/// with at least one visible (non-minimized) window. Default `.none` keeps the
/// click as a no-op so existing users don't change behavior on upgrade.
enum AppTileFrontmostClickBehavior: String, CaseIterable, Identifiable {
    case none
    case hide
    case cycleWindows
    case minimizeAll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: String(localized: "Do Nothing")
        case .hide: String(localized: "Hide App")
        case .cycleWindows: String(localized: "Cycle Windows")
        case .minimizeAll: String(localized: "Minimize All Windows")
        }
    }

}

struct AppIconOverride: Codable, Equatable, Identifiable {
    let bundleIdentifier: String
    let iconPath: String
    /// Optional inset, expressed as a fraction of the smaller cell
    /// dimension, applied around the override icon at render time. Lets
    /// users compensate for custom icons that lack the transparent
    /// padding system icons usually have. Missing in older serialized
    /// data, hence Optional.
    let paddingFraction: CGFloat?

    init(bundleIdentifier: String, iconPath: String, paddingFraction: CGFloat? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.iconPath = iconPath
        self.paddingFraction = paddingFraction
    }

    var id: String { bundleIdentifier }

    var effectiveIconURL: URL? {
        guard !iconPath.isEmpty, FileManager.default.fileExists(atPath: iconPath) else {
            return nil
        }

        return URL(fileURLWithPath: iconPath)
    }
}

enum TrashIconState: String, Codable, CaseIterable, Identifiable {
    case empty
    case full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .empty: String(localized: "Empty")
        case .full: String(localized: "Full")
        }
    }

    var systemImageName: String {
        switch self {
        case .empty: "NSTrashEmpty"
        case .full: "NSTrashFull"
        }
    }
}

struct TrashIconOverride: Codable, Equatable, Identifiable {
    let state: TrashIconState
    let iconPath: String
    /// See `AppIconOverride.paddingFraction`.
    let paddingFraction: CGFloat?

    init(state: TrashIconState, iconPath: String, paddingFraction: CGFloat? = nil) {
        self.state = state
        self.iconPath = iconPath
        self.paddingFraction = paddingFraction
    }

    var id: String { state.rawValue }

    var effectiveIconURL: URL? {
        guard !iconPath.isEmpty, FileManager.default.fileExists(atPath: iconPath) else {
            return nil
        }

        return URL(fileURLWithPath: iconPath)
    }
}

struct FolderIconOverride: Codable, Equatable, Identifiable {
    let folderPath: String
    let iconPath: String
    /// See `AppIconOverride.paddingFraction`.
    let paddingFraction: CGFloat?

    init(folderPath: String, iconPath: String, paddingFraction: CGFloat? = nil) {
        self.folderPath = folderPath
        self.iconPath = iconPath
        self.paddingFraction = paddingFraction
    }

    var id: String { folderPath }

    var effectiveIconURL: URL? {
        guard !iconPath.isEmpty, FileManager.default.fileExists(atPath: iconPath) else {
            return nil
        }

        return URL(fileURLWithPath: iconPath)
    }
}

enum FolderTileDisplayMode: String, CaseIterable, Codable, Identifiable {
    case folder
    case contents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .folder: String(localized: "Folder")
        case .contents: String(localized: "Contents")
        }
    }
}

enum AppFolderTileDisplayMode: String, CaseIterable, Codable, Identifiable {
    case grid
    case stack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: String(localized: "Grid")
        case .stack: String(localized: "Stack")
        }
    }
}

/// How an app folder surfaces its contained apps' notification badges on the
/// dock tile: a single rolled-up total, or a badge on each individual app
/// icon. See `DockyPreferences.folderBadgeMode`.
enum FolderBadgeMode: String, CaseIterable, Codable, Identifiable {
    case combined
    case perApp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .combined: String(localized: "Combined total")
        case .perApp: String(localized: "On each app")
        }
    }
}

/// When per-app folder badges are shown on the dock-tile preview, whether each
/// badged app icon gets a plain dot or the full numeric count. Only affects the
/// tile preview; the expanded popover always shows the numeric count.
enum FolderBadgePreviewStyle: String, CaseIterable, Codable, Identifiable {
    case dot
    case number

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dot: String(localized: "Dot")
        case .number: String(localized: "Number")
        }
    }
}

enum FolderTileContentViewMode: String, CaseIterable, Codable, Identifiable {
    case grid
    case list
    case inline
    case fan
    case finder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: String(localized: "Grid")
        case .list: String(localized: "List")
        case .inline: String(localized: "Inline")
        case .fan: String(localized: "Fan")
        case .finder: String(localized: "Finder Window")
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? Self.grid.rawValue

        switch rawValue {
        case Self.list.rawValue:
            self = .list
        case Self.inline.rawValue:
            self = .inline
        case Self.fan.rawValue:
            self = .fan
        case Self.finder.rawValue:
            self = .finder
        case Self.grid.rawValue:
            self = .grid
        default:
            self = .grid
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum FolderTileSortMode: String, CaseIterable, Codable, Identifiable {
    case name
    case dateModified
    case dateCreated
    case dateAdded
    case kind
    case size

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: String(localized: "Name")
        case .dateModified: String(localized: "Date Modified")
        case .dateCreated: String(localized: "Date Created")
        case .dateAdded: String(localized: "Date Added")
        case .kind: String(localized: "Kind")
        case .size: String(localized: "Size")
        }
    }
}

enum WindowSwitcherPreviewMode: String, CaseIterable, Codable, Identifiable {
    case inPlace
    case instantFocus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inPlace: String(localized: "In Place")
        case .instantFocus: String(localized: "Instant Focus")
        }
    }

    var summary: String {
        switch self {
        case .inPlace:
            String(localized: "Hold on one selection to preview that window behind the switcher without changing focus until you release the shortcut.")
        case .instantFocus:
            String(localized: "Focus each selected window immediately while keeping the original cycling order frozen until you release the shortcut.")
        }
    }
}

/// Which Spaces a taskbar or switcher list draws from.
enum SpaceScope: String, CaseIterable, Codable, Identifiable {
    case allSpaces
    case activeSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allSpaces: String(localized: "All Spaces")
        case .activeSpace: String(localized: "Active Space")
        }
    }

    /// Whether a window on an active Space (or not) belongs in the list.
    func includes(windowOnActiveSpace: Bool) -> Bool {
        self == .allSpaces || windowOnActiveSpace
    }
}

enum LaunchpadLayoutAxis: String, CaseIterable, Codable, Identifiable {
    /// Apple's classic paged Launchpad: a fixed grid per page, scrolls
    /// horizontally one screenful at a time.
    case horizontal
    /// macOS Tahoe-style "Apps" view: a single continuous vertical
    /// grid that scrolls freely without page boundaries.
    case vertical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .horizontal: String(localized: "Paged")
        case .vertical: String(localized: "Continuous")
        }
    }

    var summary: String {
        switch self {
        case .horizontal:
            String(localized: "Apple's classic Launchpad: pages of icons that swipe horizontally with a page indicator below.")
        case .vertical:
            String(localized: "macOS Tahoe-style Apps view: one tall scrollable grid with no page boundaries. Rows are unused.")
        }
    }

    /// Default for the current OS. macOS 26 (Tahoe) ships a vertical
    /// Apps view in place of paged Launchpad; older systems keep the
    /// paged layout so the upgrade isn't silently disruptive.
    static var defaultForCurrentOS: LaunchpadLayoutAxis {
        if #available(macOS 26.0, *) {
            return .vertical
        }
        return .horizontal
    }
}

/// How Launchpad orders its top-level entries. `.manual` preserves the
/// user's drag-arranged layout; the others sort the grid on the fly
/// without mutating the persisted layout, so switching back to
/// `.manual` restores the custom order untouched.
enum LaunchpadSortMode: String, CaseIterable, Codable, Identifiable {
    case manual
    case name
    case dateCreated
    case dateModified

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: String(localized: "Default")
        case .name: String(localized: "Alphabetical")
        case .dateCreated: String(localized: "Date Created")
        case .dateModified: String(localized: "Date Modified")
        }
    }
}

@MainActor
@Observable final class DockyPreferences {
    static let shared = DockyPreferences()

    /// Edge Docky anchors itself to. `system` mirrors the macOS Dock. Stored for
    /// screen-edge support; the taskbar follows `effectiveWindowPosition` meanwhile.
    var windowPosition: DockWindowPosition {
        didSet {
            guard windowPosition != oldValue else { return }
            defaults.set(windowPosition.rawValue, forKey: Keys.windowPosition)
            syncSystemDockPositionIfNeeded()
        }
    }

    /// Which display owns Docky's single main window.
    var windowDisplayTarget: DockWindowDisplayTarget {
        didSet {
            guard windowDisplayTarget != oldValue else { return }
            defaults.set(windowDisplayTarget.rawValue, forKey: Keys.windowDisplayTarget)
        }
    }

    /// Whether Docky's windows stay in the active Space or join all Spaces.
    var windowSpaceBehavior: DockWindowSpaceBehavior {
        didSet {
            guard windowSpaceBehavior != oldValue else { return }
            defaults.set(windowSpaceBehavior.rawValue, forKey: Keys.windowSpaceBehavior)
        }
    }

    /// Whether Docky's main window should slide off-screen until revealed.
    var autohidesWindow: Bool {
        didSet {
            guard autohidesWindow != oldValue else { return }
            defaults.set(autohidesWindow, forKey: Keys.autohidesWindow)
        }
    }

    /// Whether running apps show their notification badge (the red count,
    /// like Mail's unread total) on their dock tile. Read from the system
    /// Dock via accessibility, see `DockBadgeService`.
    var showsAppBadges: Bool {
        didSet {
            guard showsAppBadges != oldValue else { return }
            defaults.set(showsAppBadges, forKey: Keys.showsAppBadges)
        }
    }

    /// Whether `docky://install-widget` links may install a widget. Off by
    /// default so a web page can't drive a native-code install unprompted.
    var allowsWidgetLinkInstalls: Bool {
        didSet {
            guard allowsWidgetLinkInstalls != oldValue else { return }
            defaults.set(allowsWidgetLinkInstalls, forKey: Keys.allowsWidgetLinkInstalls)
        }
    }

    /// Whether app folders roll their contained apps' badges into a single
    /// total on the group tile, or paint a badge on each app icon. Only
    /// meaningful when `showsAppBadges` is on.
    var folderBadgeMode: FolderBadgeMode {
        didSet {
            guard folderBadgeMode != oldValue else { return }
            defaults.set(folderBadgeMode.rawValue, forKey: Keys.folderBadgeMode)
        }
    }

    /// With per-app folder badges, whether the dock-tile preview shows a plain
    /// dot or the numeric count on each badged app. Only meaningful when
    /// `folderBadgeMode` is `.perApp`.
    var folderBadgePreviewStyle: FolderBadgePreviewStyle {
        didSet {
            guard folderBadgePreviewStyle != oldValue else { return }
            defaults.set(folderBadgePreviewStyle.rawValue, forKey: Keys.folderBadgePreviewStyle)
        }
    }

    /// Whether Docky should register itself to launch when the user logs in.
    var opensAtLogin: Bool {
        didSet {
            guard opensAtLogin != oldValue else { return }
            defaults.set(opensAtLogin, forKey: Keys.opensAtLogin)

            guard !isSyncingOpenAtLoginPreference else {
                return
            }

            guard LaunchAtLoginService.shared.setEnabled(opensAtLogin) else {
                syncOpenAtLoginPreferenceFromSystem()
                return
            }
        }
    }

    /// Delay before Docky hides its own window after interaction ends.
    var autohideWindowDelay: TimeInterval {
        didSet {
            let clampedValue = max(0, autohideWindowDelay)
            guard clampedValue != oldValue else {
                if autohideWindowDelay != clampedValue {
                    autohideWindowDelay = clampedValue
                }
                return
            }

            if autohideWindowDelay != clampedValue {
                autohideWindowDelay = clampedValue
                return
            }

            defaults.set(clampedValue, forKey: Keys.autohideWindowDelay)
        }
    }

    /// Height of the Windows 11 taskbar, in whole points. Dragging the bar's
    /// top edge or the Settings field changes it; the bar's buttons, icons,
    /// and tray scale with it.
    var windowsTaskbarHeight: CGFloat {
        didSet {
            let clampedValue = WindowsTaskbarMetrics.clampedHeight(windowsTaskbarHeight)
            guard clampedValue != oldValue else {
                if windowsTaskbarHeight != clampedValue {
                    windowsTaskbarHeight = clampedValue
                }
                return
            }

            if windowsTaskbarHeight != clampedValue {
                windowsTaskbarHeight = clampedValue
                return
            }

            defaults.set(Double(clampedValue), forKey: Keys.windowsTaskbarHeight)
        }
    }

    /// Dwell time the pointer must spend at the screen edge before Docky
    /// reveals while a fullscreen app is on the target screen. Mirrors the
    /// macOS Dock's intent-gating behavior in fullscreen.
    var fullscreenRevealDelay: TimeInterval {
        didSet {
            let clampedValue = max(0, fullscreenRevealDelay)
            guard clampedValue != oldValue else {
                if fullscreenRevealDelay != clampedValue {
                    fullscreenRevealDelay = clampedValue
                }
                return
            }

            if fullscreenRevealDelay != clampedValue {
                fullscreenRevealDelay = clampedValue
                return
            }

            defaults.set(clampedValue, forKey: Keys.fullscreenRevealDelay)
        }
    }

    /// Hover dwell before the per-tile window preview slides up. Same
    /// clamp pattern as the other delay prefs so the slider can never go
    /// negative.
    var windowPreviewHoverDelay: TimeInterval {
        didSet {
            let clampedValue = max(0, windowPreviewHoverDelay)
            guard clampedValue != oldValue else {
                if windowPreviewHoverDelay != clampedValue {
                    windowPreviewHoverDelay = clampedValue
                }
                return
            }

            if windowPreviewHoverDelay != clampedValue {
                windowPreviewHoverDelay = clampedValue
                return
            }

            defaults.set(clampedValue, forKey: Keys.windowPreviewHoverDelay)
        }
    }

    /// The taskbar lays out horizontally only, so it stays at the bottom
    /// without rewriting the stored preference.
    var effectiveWindowPosition: DockWindowPosition {
        .bottom
    }

    /// Whether hovering an expandable widget tile presents the expanded preview window.
    var enablesWidgetHoverPreview: Bool {
        didSet {
            guard enablesWidgetHoverPreview != oldValue else { return }
            defaults.set(enablesWidgetHoverPreview, forKey: Keys.enablesWidgetHoverPreview)
        }
    }

    /// Tile spans for which the expanded hover preview is allowed to appear.
    var widgetHoverPreviewSpans: Set<TileSpan> {
        didSet {
            guard widgetHoverPreviewSpans != oldValue else { return }
            defaults.set(widgetHoverPreviewSpans.map(\.rawValue), forKey: Keys.widgetHoverPreviewSpans)
        }
    }

    /// How long the cursor must rest on a widget before its expanded preview appears. Zero = immediate.
    var widgetHoverPreviewDelay: TimeInterval {
        didSet {
            let clampedValue = max(0, widgetHoverPreviewDelay)
            guard clampedValue != oldValue else {
                if widgetHoverPreviewDelay != clampedValue {
                    widgetHoverPreviewDelay = clampedValue
                }
                return
            }

            if widgetHoverPreviewDelay != clampedValue {
                widgetHoverPreviewDelay = clampedValue
                return
            }

            defaults.set(clampedValue, forKey: Keys.widgetHoverPreviewDelay)
        }
    }

    /// Whether Docky surfaces unpinned running apps. Disable to use Docky as a static shelf alongside the system Dock.
    var showsRunningApps: Bool {
        didSet {
            guard showsRunningApps != oldValue else { return }
            defaults.set(showsRunningApps, forKey: Keys.showsRunningApps)
        }
    }

    /// Behavior when clicking an app tile whose app is already frontmost with at least one
    /// visible window. `.none` is the default; `.cycleWindows` and `.minimizeAll` are pro-only.
    var appTileFrontmostClickBehavior: AppTileFrontmostClickBehavior {
        didSet {
            guard appTileFrontmostClickBehavior != oldValue else { return }
            defaults.set(appTileFrontmostClickBehavior.rawValue, forKey: Keys.appTileFrontmostClickBehavior)
        }
    }

    /// The app that folder, reveal and Trash actions open. `FileBrowserService` falls back to
    /// Finder when the chosen app isn't installed.
    var fileBrowser: FileBrowser {
        didSet {
            guard fileBrowser != oldValue else { return }
            defaults.set(fileBrowser.rawValue, forKey: Keys.fileBrowser)
        }
    }

    /// Whether Docky surfaces minimized window tiles in the trailing section.
    var showsMinimizedWindows: Bool {
        didSet {
            guard showsMinimizedWindows != oldValue else { return }
            defaults.set(showsMinimizedWindows, forKey: Keys.showsMinimizedWindows)
        }
    }

    /// Shelve mode: hides the Finder and/or Trash tiles so the dock
    /// reads as a pure shelf of pinned apps + widgets. The granular
    /// `shelveHidesFinder` / `shelveHidesTrash` prefs decide *which*
    /// fixtures disappear when this is on; both default to `true` for
    /// backward compatibility with the original boolean behavior.
    var enablesShelveMode: Bool {
        didSet {
            guard enablesShelveMode != oldValue else { return }
            defaults.set(enablesShelveMode, forKey: Keys.enablesShelveMode)
        }
    }

    /// While shelve mode is on, whether the Finder tile is suppressed.
    /// Has no effect when `enablesShelveMode` is `false`.
    var shelveHidesFinder: Bool {
        didSet {
            guard shelveHidesFinder != oldValue else { return }
            defaults.set(shelveHidesFinder, forKey: Keys.shelveHidesFinder)
        }
    }

    /// While shelve mode is on, whether the Trash tile is suppressed.
    var shelveHidesTrash: Bool {
        didSet {
            guard shelveHidesTrash != oldValue else { return }
            defaults.set(shelveHidesTrash, forKey: Keys.shelveHidesTrash)
        }
    }

    /// When true, recent / unpinned running apps are hidden from the dock.
    /// Equivalent to `showsRunningApps == false`; either being set hides
    /// them, so the user can disable recents from the dedicated toggle
    /// without flipping the broader "Show Running Apps" preference.
    var hidesRecentApps: Bool {
        didSet {
            guard hidesRecentApps != oldValue else { return }
            defaults.set(hidesRecentApps, forKey: Keys.hidesRecentApps)
        }
    }

    /// Whether the taskbar's app buttons, running underlines, minimized-window
    /// tiles and hover window previews cover every Space or only the Spaces
    /// currently shown. Pinned apps stay either way.
    var taskbarSpaceScope: SpaceScope {
        didSet {
            guard taskbarSpaceScope != oldValue else { return }
            defaults.set(taskbarSpaceScope.rawValue, forKey: Keys.taskbarSpaceScope)
        }
    }

    /// Hides the profile switcher strip even when more than one profile
    /// exists. When `false` (default), the strip still hides itself
    /// automatically while only the "Default" profile is around;
    /// `ProfileSwitcherWindowController` observes both this flag and
    /// the live profile count to drive show/hide.
    var hidesProfileStrip: Bool {
        didSet {
            guard hidesProfileStrip != oldValue else { return }
            defaults.set(hidesProfileStrip, forKey: Keys.hidesProfileStrip)
        }
    }

    /// Optional per-app icon overrides used by app tiles.
    var appIconOverrides: [AppIconOverride] {
        didSet {
            guard appIconOverrides != oldValue else { return }
            persistAppIconOverrides(appIconOverrides)
        }
    }

    /// Optional icon overrides for the Trash tile, keyed by empty/full state.
    var trashIconOverrides: [TrashIconOverride] {
        didSet {
            guard trashIconOverrides != oldValue else { return }
            persistTrashIconOverrides(trashIconOverrides)
        }
    }

    /// Optional per-folder icon overrides used by folder tiles, keyed by path.
    var folderIconOverrides: [FolderIconOverride] {
        didSet {
            guard folderIconOverrides != oldValue else { return }
            persistFolderIconOverrides(folderIconOverrides)
        }
    }

    /// Optional image path used to replace the Launchpad tile's icon.
    var launchpadIconPath: String? {
        didSet {
            guard launchpadIconPath != oldValue else { return }

            if let launchpadIconPath, !launchpadIconPath.isEmpty {
                defaults.set(launchpadIconPath, forKey: Keys.launchpadIconPath)
            } else {
                defaults.removeObject(forKey: Keys.launchpadIconPath)
            }
        }
    }

    /// Optional padding fraction applied around the Launchpad override icon.
    /// Persists as a Double under `launchpadIconPaddingFraction`.
    var launchpadIconPaddingFraction: CGFloat? {
        didSet {
            guard launchpadIconPaddingFraction != oldValue else { return }

            if let launchpadIconPaddingFraction {
                defaults.set(Double(launchpadIconPaddingFraction), forKey: Keys.launchpadIconPaddingFraction)
            } else {
                defaults.removeObject(forKey: Keys.launchpadIconPaddingFraction)
            }
        }
    }

    /// Bundle identifiers hidden from Docky's app tile surfaces.
    var hiddenAppBundleIdentifiers: [String] {
        didSet {
            let normalizedIdentifiers = Self.normalizedBundleIdentifiers(hiddenAppBundleIdentifiers)
            guard normalizedIdentifiers != oldValue else {
                if hiddenAppBundleIdentifiers != normalizedIdentifiers {
                    hiddenAppBundleIdentifiers = normalizedIdentifiers
                }
                return
            }

            if hiddenAppBundleIdentifiers != normalizedIdentifiers {
                hiddenAppBundleIdentifiers = normalizedIdentifiers
                return
            }

            defaults.set(normalizedIdentifiers, forKey: Keys.hiddenAppBundleIdentifiers)
            mirrorToActiveProfile { $0.hiddenAppBundleIdentifiers = normalizedIdentifiers }
        }
    }

    /// Whether opened apps from an app folder should appear grouped beside that folder.
    var showsGroupedOpenedAppsInDock: Bool {
        didSet {
            guard showsGroupedOpenedAppsInDock != oldValue else { return }
            defaults.set(showsGroupedOpenedAppsInDock, forKey: Keys.showsGroupedOpenedAppsInDock)
        }
    }

    /// Whether Docky's Launchpad overlay is enabled.
    var enablesLaunchpadOverlay: Bool {
        didSet {
            guard enablesLaunchpadOverlay != oldValue else { return }
            defaults.set(enablesLaunchpadOverlay, forKey: Keys.enablesLaunchpadOverlay)
        }
    }

    /// Whether Docky's Start menu overlay is enabled. Gates the tile
    /// click handler, the ⌃⌥S hotkey, and visibility of the Start menu
    /// widget in the dock editor palette.
    var enablesStartMenuOverlay: Bool {
        didSet {
            guard enablesStartMenuOverlay != oldValue else { return }
            defaults.set(enablesStartMenuOverlay, forKey: Keys.enablesStartMenuOverlay)
        }
    }

    /// When true, clicking the Finder tile opens the Start menu instead
    /// of activating Finder. Off by default so the Finder tile behaves
    /// like every other app tile unless the user opts in.
    var opensStartMenuFromFinderTile: Bool {
        didSet {
            guard opensStartMenuFromFinderTile != oldValue else { return }
            defaults.set(opensStartMenuFromFinderTile, forKey: Keys.opensStartMenuFromFinderTile)
        }
    }

    /// How transparent the Launchpad overlay's background tint is. `0` is
    /// fully opaque (heavy tint over the SkyLight blur); `1` is fully clear
    /// (only the live blur remains, no tint on top).
    var launchpadOverlayTransparency: CGFloat {
        didSet {
            let clampedValue = min(max(launchpadOverlayTransparency, 0), 1)
            guard clampedValue != oldValue else {
                if launchpadOverlayTransparency != clampedValue {
                    launchpadOverlayTransparency = clampedValue
                }
                return
            }

            if launchpadOverlayTransparency != clampedValue {
                launchpadOverlayTransparency = clampedValue
                return
            }

            defaults.set(Double(clampedValue), forKey: Keys.launchpadOverlayTransparency)
        }
    }

    /// Preferred column count for the Launchpad overlay grid.
    var launchpadGridColumnCount: Int {
        didSet {
            let clampedValue = max(1, launchpadGridColumnCount)
            guard clampedValue != oldValue else {
                if launchpadGridColumnCount != clampedValue {
                    launchpadGridColumnCount = clampedValue
                }
                return
            }

            if launchpadGridColumnCount != clampedValue {
                launchpadGridColumnCount = clampedValue
                return
            }

            defaults.set(clampedValue, forKey: Keys.launchpadGridColumnCount)
        }
    }

    /// Preferred row count for the Launchpad overlay grid.
    var launchpadGridRowCount: Int {
        didSet {
            let clampedValue = max(1, launchpadGridRowCount)
            guard clampedValue != oldValue else {
                if launchpadGridRowCount != clampedValue {
                    launchpadGridRowCount = clampedValue
                }
                return
            }

            if launchpadGridRowCount != clampedValue {
                launchpadGridRowCount = clampedValue
                return
            }

            defaults.set(clampedValue, forKey: Keys.launchpadGridRowCount)
        }
    }

    /// Icon edge length used by the Launchpad overlay at the 1440p
    /// reference height. Doubles as the upper bound (smaller displays
    /// scale down linearly from here; larger displays are clamped to
    /// this value). Range comes from `DefaultValues.launchpadBaseIconSize`
    /// bookends; the setter clamps so a corrupt stored value can't push
    /// the icon outside that range.
    var launchpadBaseIconSize: CGFloat {
        didSet {
            let clampedValue = min(
                max(launchpadBaseIconSize, DefaultValues.launchpadBaseIconSizeMin),
                DefaultValues.launchpadBaseIconSizeMax
            )
            guard clampedValue != oldValue else {
                if launchpadBaseIconSize != clampedValue {
                    launchpadBaseIconSize = clampedValue
                }
                return
            }

            if launchpadBaseIconSize != clampedValue {
                launchpadBaseIconSize = clampedValue
                return
            }

            defaults.set(Double(clampedValue), forKey: Keys.launchpadBaseIconSize)
        }
    }

    /// Horizontal gap between Launchpad cells at the reference height.
    /// Scaled down on smaller displays with the same screen-height
    /// factor as the icon. Clamped to the bookends below.
    var launchpadColumnSpacing: CGFloat {
        didSet {
            let clampedValue = min(
                max(launchpadColumnSpacing, DefaultValues.launchpadSpacingMin),
                DefaultValues.launchpadSpacingMax
            )
            guard clampedValue != oldValue else {
                if launchpadColumnSpacing != clampedValue {
                    launchpadColumnSpacing = clampedValue
                }
                return
            }

            if launchpadColumnSpacing != clampedValue {
                launchpadColumnSpacing = clampedValue
                return
            }

            defaults.set(Double(clampedValue), forKey: Keys.launchpadColumnSpacing)
        }
    }

    /// Optional image path used as the Launchpad's full-screen
    /// backdrop. When `nil` the launchpad falls back to the current
    /// desktop wallpaper (the previous default).
    var launchpadBackgroundImagePath: String? {
        didSet {
            guard launchpadBackgroundImagePath != oldValue else { return }
            if let path = launchpadBackgroundImagePath, !path.isEmpty {
                defaults.set(path, forKey: Keys.launchpadBackgroundImagePath)
            } else {
                defaults.removeObject(forKey: Keys.launchpadBackgroundImagePath)
            }
        }
    }

    /// Whether the launchpad's backdrop image (custom or desktop
    /// wallpaper) is rendered through the heavy SwiftUI blur. Default
    /// `true` matches the previous behavior; disabling shows the image
    /// crisp, useful when the user picks a curated background.
    var launchpadBackgroundBlursImage: Bool {
        didSet {
            guard launchpadBackgroundBlursImage != oldValue else { return }
            defaults.set(launchpadBackgroundBlursImage, forKey: Keys.launchpadBackgroundBlursImage)
        }
    }

    /// Scroll axis for the Launchpad overlay. `.horizontal` keeps the
    /// classic Apple paged layout; `.vertical` renders a single
    /// continuous grid (matches macOS Tahoe's Apps view). Row count is
    /// only consulted in horizontal mode.
    var launchpadLayoutAxis: LaunchpadLayoutAxis {
        didSet {
            guard launchpadLayoutAxis != oldValue else { return }
            defaults.set(launchpadLayoutAxis.rawValue, forKey: Keys.launchpadLayoutAxis)
        }
    }

    /// Sort order applied to the Launchpad grid. Display-only — never
    /// mutates the persisted layout, so `.manual` always restores the
    /// user's drag-arranged order.
    var launchpadSortMode: LaunchpadSortMode {
        didSet {
            guard launchpadSortMode != oldValue else { return }
            defaults.set(launchpadSortMode.rawValue, forKey: Keys.launchpadSortMode)
        }
    }

    /// Global shortcut that toggles Docky's Launchpad overlay.
    var launchpadShortcut: KeyboardShortcut {
        didSet {
            guard launchpadShortcut != oldValue else { return }
            persistLaunchpadShortcut(launchpadShortcut)
        }
    }

    /// Whether Docky's window switcher is enabled.
    var enablesWindowSwitcher: Bool {
        didSet {
            guard enablesWindowSwitcher != oldValue else { return }
            defaults.set(enablesWindowSwitcher, forKey: Keys.enablesWindowSwitcher)
        }
    }

    /// Whether minimized windows appear alongside visible ones in the
    /// switcher. When on, the switcher view dims them and labels them
    /// "(minimized)" so the user can still tell them apart at a glance.
    var includesMinimizedWindows: Bool {
        didSet {
            guard includesMinimizedWindows != oldValue else { return }
            defaults.set(includesMinimizedWindows, forKey: Keys.includesMinimizedWindows)
        }
    }

    /// Global shortcut that opens Docky's window switcher.
    var windowSwitcherShortcut: KeyboardShortcut {
        didSet {
            guard windowSwitcherShortcut != oldValue else { return }
            persistWindowSwitcherShortcut(windowSwitcherShortcut)
        }
    }

    /// Whether ⌘Tab opens Docky's window switcher instead of the macOS app
    /// switcher. `SystemCommandTabService` turns the system's ⌘Tab and ⇧⌘Tab
    /// hotkeys off while this is on.
    var replacesSystemCommandTab: Bool {
        didSet {
            guard replacesSystemCommandTab != oldValue else { return }
            defaults.set(replacesSystemCommandTab, forKey: Keys.replacesSystemCommandTab)
        }
    }

    /// The shortcut the switcher actually listens for: ⌘Tab while it replaces
    /// the macOS app switcher, otherwise the recorded `windowSwitcherShortcut`.
    var effectiveWindowSwitcherShortcut: KeyboardShortcut {
        replacesSystemCommandTab ? KeyboardShortcut.commandTab : windowSwitcherShortcut
    }

    /// Whether the window switcher previews the selected window while the shortcut is held.
    /// Off by default, so like ⌘Tab nothing comes forward until the shortcut is released.
    var showsWindowSwitcherFocusPreview: Bool {
        didSet {
            guard showsWindowSwitcherFocusPreview != oldValue else { return }
            defaults.set(showsWindowSwitcherFocusPreview, forKey: Keys.showsWindowSwitcherFocusPreview)
        }
    }

    /// Which behavior Docky's window switcher should use when previewing the selected window.
    var windowSwitcherPreviewMode: WindowSwitcherPreviewMode {
        didSet {
            guard windowSwitcherPreviewMode != oldValue else { return }
            defaults.set(windowSwitcherPreviewMode.rawValue, forKey: Keys.windowSwitcherPreviewMode)
        }
    }

    /// Whether the window switcher lists windows from every Space or only
    /// from the Spaces currently shown.
    var windowSwitcherSpaceScope: SpaceScope {
        didSet {
            guard windowSwitcherSpaceScope != oldValue else { return }
            defaults.set(windowSwitcherSpaceScope.rawValue, forKey: Keys.windowSwitcherSpaceScope)
        }
    }

    /// Point size of the window title in each window switcher card's header.
    var windowSwitcherFontSize: CGFloat {
        didSet {
            let clampedValue = WindowSwitcherGeometry.clampedFontSize(windowSwitcherFontSize)
            guard clampedValue != oldValue else {
                if windowSwitcherFontSize != clampedValue {
                    windowSwitcherFontSize = clampedValue
                }
                return
            }

            if windowSwitcherFontSize != clampedValue {
                windowSwitcherFontSize = clampedValue
                return
            }

            defaults.set(Double(clampedValue), forKey: Keys.windowSwitcherFontSize)
        }
    }

    /// Point size of the app icon in each window switcher card's header.
    var windowSwitcherIconSize: CGFloat {
        didSet {
            let clampedValue = WindowSwitcherGeometry.clampedIconSize(windowSwitcherIconSize)
            guard clampedValue != oldValue else {
                if windowSwitcherIconSize != clampedValue {
                    windowSwitcherIconSize = clampedValue
                }
                return
            }

            if windowSwitcherIconSize != clampedValue {
                windowSwitcherIconSize = clampedValue
                return
            }

            defaults.set(Double(clampedValue), forKey: Keys.windowSwitcherIconSize)
        }
    }

    /// Single-key (no modifier — switcher's own modifier is already held)
    /// pressed inside the open switcher to minimize the selected window.
    var switcherMinimizeKeyCode: UInt16 {
        didSet {
            guard switcherMinimizeKeyCode != oldValue else { return }
            defaults.set(Int(switcherMinimizeKeyCode), forKey: Keys.switcherMinimizeKeyCode)
        }
    }

    /// Single-key pressed inside the open switcher to close the selected window.
    var switcherCloseKeyCode: UInt16 {
        didSet {
            guard switcherCloseKeyCode != oldValue else { return }
            defaults.set(Int(switcherCloseKeyCode), forKey: Keys.switcherCloseKeyCode)
        }
    }

    /// Single-key pressed inside the open switcher to zoom (green-button) the selected window.
    var switcherZoomKeyCode: UInt16 {
        didSet {
            guard switcherZoomKeyCode != oldValue else { return }
            defaults.set(Int(switcherZoomKeyCode), forKey: Keys.switcherZoomKeyCode)
        }
    }

    /// Docky-owned ordered pinned app bundle identifiers.
    var pinnedAppBundleIdentifiers: [String] {
        didSet {
            guard pinnedAppBundleIdentifiers != oldValue else { return }
            defaults.set(pinnedAppBundleIdentifiers, forKey: Keys.pinnedAppBundleIdentifiers)
        }
    }

    /// Docky-owned ordered pinned section items.
    var pinnedItems: [PinnedTileItem] {
        didSet {
            guard pinnedItems != oldValue else { return }
            persistPinnedItems(pinnedItems)
            let snapshot = pinnedItems
            mirrorToActiveProfile { $0.pinnedItems = snapshot }

            let appBundleIdentifiers = pinnedItems.compactMap { item in
                item.kind == .app ? item.bundleIdentifier : nil
            }
            if pinnedAppBundleIdentifiers != appBundleIdentifiers {
                pinnedAppBundleIdentifiers = appBundleIdentifiers
            }
        }
    }

    /// Enabled widgets grouped by the app tile they extend.
    var widgetPlacements: [WidgetPlacement] {
        didSet {
            guard widgetPlacements != oldValue else { return }
            persistWidgetPlacements(widgetPlacements)
            let snapshot = widgetPlacements
            mirrorToActiveProfile { $0.widgetPlacements = snapshot }
        }
    }

    /// Optional widget substitutions for app tiles.
    var appWidgetDisplays: [AppWidgetDisplay] {
        didSet {
            guard appWidgetDisplays != oldValue else { return }
            persistAppWidgetDisplays(appWidgetDisplays)
            let snapshot = appWidgetDisplays
            mirrorToActiveProfile { $0.appWidgetDisplays = snapshot }
        }
    }

    /// Docky-owned ordered folder/trash section items.
    var trailingItems: [TrailingTileItem] {
        didSet {
            guard trailingItems != oldValue else { return }
            persistTrailingItems(trailingItems)
            let snapshot = trailingItems
            mirrorToActiveProfile { $0.trailingItems = snapshot }
        }
    }

    /// Whether Docky has already shown the divider edit hint chip.
    var hasSeenDockEditorHint: Bool {
        didSet {
            guard hasSeenDockEditorHint != oldValue else { return }
            defaults.set(hasSeenDockEditorHint, forKey: Keys.hasSeenDockEditorHint)
        }
    }

    /// Ordered file bookmarks for the Photo Frame widget's slideshow.
    /// Global (not mirrored per-profile) — the user's chosen photos are
    /// content, like installed widgets, not part of a dock layout.
    /// `Data` is a property-list type, so it round-trips through
    /// UserDefaults directly without a JSON encode step.
    var photoFrameBookmarks: [Data] {
        didSet {
            guard photoFrameBookmarks != oldValue else { return }
            if photoFrameBookmarks.isEmpty {
                defaults.removeObject(forKey: Keys.photoFrameBookmarks)
            } else {
                defaults.set(photoFrameBookmarks, forKey: Keys.photoFrameBookmarks)
            }
        }
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var isSyncingOpenAtLoginPreference = false

    /// When `true`, tile-store didSet observers skip the push to
    /// `ProfileService`. Used by `applyProfile(_:)` so loading a profile
    /// doesn't immediately overwrite it with the values just loaded.
    private var isApplyingProfile = false

    /// Swap the active profile's tile-store fields into this preferences
    /// object. Each assignment fires its didSet — those still persist to
    /// the legacy top-level keys (which now act as a snapshot of the
    /// active profile) but skip mirroring back to `ProfileService` while
    /// `isApplyingProfile` is set.
    func applyProfile(_ profile: DockProfile) {
        isApplyingProfile = true
        defer { isApplyingProfile = false }
        pinnedItems = profile.pinnedItems
        trailingItems = profile.trailingItems
        widgetPlacements = profile.widgetPlacements
        appWidgetDisplays = profile.appWidgetDisplays
        hiddenAppBundleIdentifiers = profile.hiddenAppBundleIdentifiers
    }

    /// Mirror a tile-store edit to the active profile so it survives the
    /// next profile switch. No-op while a profile is being applied.
    fileprivate func mirrorToActiveProfile(_ mutate: @escaping (inout DockProfile) -> Void) {
        guard !isApplyingProfile else { return }
        ProfileService.shared.updateActiveProfile(mutate)
    }

    func appIconOverride(forBundleIdentifier bundleIdentifier: String) -> AppIconOverride? {
        return appIconOverrides.first { $0.bundleIdentifier == bundleIdentifier }
    }

    func effectiveAppIconOverrideURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        appIconOverride(forBundleIdentifier: bundleIdentifier)?.effectiveIconURL
    }

    func setAppIconOverride(bundleIdentifier: String, iconPath: String, paddingFraction: CGFloat? = nil) {
        guard !bundleIdentifier.isEmpty, !iconPath.isEmpty else {
            return
        }

        var overridesByBundleIdentifier = Dictionary(uniqueKeysWithValues: appIconOverrides.map {
            ($0.bundleIdentifier, $0)
        })
        overridesByBundleIdentifier[bundleIdentifier] = AppIconOverride(
            bundleIdentifier: bundleIdentifier,
            iconPath: iconPath,
            paddingFraction: paddingFraction
        )
        appIconOverrides = overridesByBundleIdentifier.values.sorted {
            $0.bundleIdentifier.localizedCaseInsensitiveCompare($1.bundleIdentifier) == .orderedAscending
        }
    }

    /// Updates only the padding for an existing override. No-op when the
    /// app has no override yet, callers should set an icon first.
    func setAppIconPaddingFraction(bundleIdentifier: String, paddingFraction: CGFloat?) {
        guard let existing = appIconOverrides.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return
        }
        setAppIconOverride(
            bundleIdentifier: bundleIdentifier,
            iconPath: existing.iconPath,
            paddingFraction: paddingFraction
        )
    }

    func removeAppIconOverride(bundleIdentifier: String) {
        appIconOverrides.removeAll { $0.bundleIdentifier == bundleIdentifier }
    }

    /// Padding fraction (0...0.5) applied around an app's override icon.
    /// Returns 0 when no override or no padding has been configured.
    func appIconOverridePadding(forBundleIdentifier bundleIdentifier: String) -> CGFloat {
        appIconOverride(forBundleIdentifier: bundleIdentifier)?.paddingFraction ?? 0
    }

    func trashIconOverride(forState state: TrashIconState) -> TrashIconOverride? {
        return trashIconOverrides.first { $0.state == state }
    }

    func effectiveTrashIconOverrideURL(forState state: TrashIconState) -> URL? {
        trashIconOverride(forState: state)?.effectiveIconURL
    }

    func setTrashIconOverride(state: TrashIconState, iconPath: String, paddingFraction: CGFloat? = nil) {
        guard !iconPath.isEmpty else {
            return
        }

        var overridesByState = Dictionary(uniqueKeysWithValues: trashIconOverrides.map {
            ($0.state, $0)
        })
        overridesByState[state] = TrashIconOverride(
            state: state,
            iconPath: iconPath,
            paddingFraction: paddingFraction
        )
        trashIconOverrides = TrashIconState.allCases.compactMap { overridesByState[$0] }
    }

    func setTrashIconPaddingFraction(state: TrashIconState, paddingFraction: CGFloat?) {
        guard let existing = trashIconOverrides.first(where: { $0.state == state }) else {
            return
        }
        setTrashIconOverride(
            state: state,
            iconPath: existing.iconPath,
            paddingFraction: paddingFraction
        )
    }

    func removeTrashIconOverride(state: TrashIconState) {
        trashIconOverrides.removeAll { $0.state == state }
    }

    func trashIconOverridePadding(forState state: TrashIconState) -> CGFloat {
        trashIconOverride(forState: state)?.paddingFraction ?? 0
    }

    func folderIconOverride(forPath path: String) -> FolderIconOverride? {
        return folderIconOverrides.first { $0.folderPath == path }
    }

    func effectiveFolderIconOverrideURL(forPath path: String) -> URL? {
        folderIconOverride(forPath: path)?.effectiveIconURL
    }

    func setFolderIconOverride(folderPath: String, iconPath: String, paddingFraction: CGFloat? = nil) {
        guard !folderPath.isEmpty, !iconPath.isEmpty else {
            return
        }

        var overridesByPath = DataIntegrityReporter.makeDictionary(
            folderIconOverrides.map { ($0.folderPath, $0) },
            site: "DockyPreferences.folderIconOverrides"
        )
        overridesByPath[folderPath] = FolderIconOverride(
            folderPath: folderPath,
            iconPath: iconPath,
            paddingFraction: paddingFraction
        )
        folderIconOverrides = overridesByPath.values.sorted {
            $0.folderPath.localizedCaseInsensitiveCompare($1.folderPath) == .orderedAscending
        }
    }

    func setFolderIconPaddingFraction(folderPath: String, paddingFraction: CGFloat?) {
        guard let existing = folderIconOverrides.first(where: { $0.folderPath == folderPath }) else {
            return
        }
        setFolderIconOverride(
            folderPath: folderPath,
            iconPath: existing.iconPath,
            paddingFraction: paddingFraction
        )
    }

    func folderIconOverridePadding(forPath path: String) -> CGFloat {
        folderIconOverride(forPath: path)?.paddingFraction ?? 0
    }

    func removeFolderIconOverride(folderPath: String) {
        folderIconOverrides.removeAll { $0.folderPath == folderPath }
    }

    var effectiveLaunchpadIconOverrideURL: URL? {
        guard let path = launchpadIconPath, !path.isEmpty else {
            return nil
        }
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    /// Padding fraction (0...0.5) for the Launchpad override icon. Returns
    /// 0 when no override or no padding is configured.
    var effectiveLaunchpadIconOverridePadding: CGFloat {
        guard effectiveLaunchpadIconOverrideURL != nil else { return 0 }
        return launchpadIconPaddingFraction ?? 0
    }

    func isAppHiddenInDocky(bundleIdentifier: String) -> Bool {
        // Docky reports itself as effectively hidden so any surface that
        // gates on this returns the right answer even though Docky never
        // actually shows up in the explicit hidden list.
        if bundleIdentifier == Bundle.main.bundleIdentifier { return true }
        return hiddenAppBundleIdentifiers.contains(bundleIdentifier)
    }

    func setAppHiddenInDocky(bundleIdentifier: String, isHidden: Bool) {
        guard !bundleIdentifier.isEmpty else {
            return
        }
        // Docky never shows itself anywhere, so adding it to the
        // hidden-apps list would be a confusing no-op, refuse it.
        if bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }

        var bundleIdentifiers = Set(hiddenAppBundleIdentifiers)
        if isHidden {
            bundleIdentifiers.insert(bundleIdentifier)
        } else {
            bundleIdentifiers.remove(bundleIdentifier)
        }

        hiddenAppBundleIdentifiers = bundleIdentifiers.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private enum Keys {
        static let windowPosition = "docky.windowPosition"
        static let windowDisplayTarget = "docky.windowDisplayTarget"
        static let windowSpaceBehavior = "docky.windowSpaceBehavior"
        static let autohidesWindow = "docky.autohidesWindow"
        static let showsAppBadges = "docky.showsAppBadges"
        static let allowsWidgetLinkInstalls = "docky.allowsWidgetLinkInstalls"
        static let folderBadgeMode = "docky.folderBadgeMode"
        static let folderBadgePreviewStyle = "docky.folderBadgePreviewStyle"
        static let opensAtLogin = "docky.opensAtLogin"
        static let autohideWindowDelay = "docky.autohideWindowDelay"
        static let windowsTaskbarHeight = "docky.windowsTaskbarHeight"
        static let fullscreenRevealDelay = "docky.fullscreenRevealDelay"
        static let windowPreviewHoverDelay = "docky.windowPreviewHoverDelay"
        static let enablesWidgetHoverPreview = "docky.enablesWidgetHoverPreview"
        static let widgetHoverPreviewSpans = "docky.widgetHoverPreviewSpans"
        static let widgetHoverPreviewDelay = "docky.widgetHoverGrowDelay"
        static let showsRunningApps = "docky.showsRunningApps"
        static let showsMinimizedWindows = "docky.showsMinimizedWindows"
        static let enablesShelveMode = "docky.enablesShelveMode"
        static let shelveHidesFinder = "docky.shelveHidesFinder"
        static let shelveHidesTrash = "docky.shelveHidesTrash"
        static let hidesRecentApps = "docky.hidesRecentApps"
        static let taskbarSpaceScope = "docky.taskbarSpaceScope"
        static let hidesProfileStrip = "docky.hidesProfileStrip"
        static let appTileFrontmostClickBehavior = "docky.appTileFrontmostClickBehavior"
        static let fileBrowser = "docky.fileBrowser"
        static let appIconOverrides = "docky.appIconOverrides"
        static let trashIconOverrides = "docky.trashIconOverrides"
        static let folderIconOverrides = "docky.folderIconOverrides"
        static let launchpadIconPath = "docky.launchpadIconPath"
        static let launchpadIconPaddingFraction = "docky.launchpadIconPaddingFraction"
        static let hiddenAppBundleIdentifiers = "docky.hiddenAppBundleIdentifiers"
        static let showsGroupedOpenedAppsInDock = "docky.showsGroupedOpenedAppsInDock"
        static let enablesLaunchpadOverlay = "docky.enablesLaunchpadOverlay"
        static let enablesStartMenuOverlay = "docky.enablesStartMenuOverlay"
        static let opensStartMenuFromFinderTile = "docky.opensStartMenuFromFinderTile"
        static let launchpadOverlayTransparency = "docky.launchpadOverlayTransparency"
        static let launchpadGridColumnCount = "docky.launchpadGridColumnCount"
        static let launchpadGridRowCount = "docky.launchpadGridRowCount"
        static let launchpadBaseIconSize = "docky.launchpadBaseIconSize"
        static let launchpadColumnSpacing = "docky.launchpadColumnSpacing"
        static let launchpadBackgroundImagePath = "docky.launchpadBackgroundImagePath"
        static let launchpadBackgroundBlursImage = "docky.launchpadBackgroundBlursImage"
        static let launchpadLayoutAxis = "docky.launchpadLayoutAxis"
        static let launchpadSortMode = "docky.launchpadSortMode"
        static let launchpadShortcut = "docky.launchpadShortcut"
        static let enablesWindowSwitcher = "docky.enablesWindowSwitcher"
        static let includesMinimizedWindows = "docky.includesMinimizedWindows"
        static let windowSwitcherShortcut = "docky.windowSwitcherShortcut"
        static let replacesSystemCommandTab = "docky.windowSwitcherReplacesCommandTab"
        static let showsWindowSwitcherFocusPreview = "docky.showsWindowSwitcherFocusPreview"
        static let windowSwitcherPreviewMode = "docky.windowSwitcherPreviewMode"
        static let windowSwitcherSpaceScope = "docky.windowSwitcherSpaceScope"
        static let windowSwitcherFontSize = "docky.windowSwitcherFontSize"
        static let windowSwitcherIconSize = "docky.windowSwitcherIconSize"
        static let switcherMinimizeKeyCode = "docky.switcherMinimizeKeyCode"
        static let switcherCloseKeyCode = "docky.switcherCloseKeyCode"
        static let switcherZoomKeyCode = "docky.switcherZoomKeyCode"
        static let pinnedAppBundleIdentifiers = "docky.pinnedAppBundleIdentifiers"
        static let pinnedItems = "docky.pinnedItems"
        static let widgetPlacements = "docky.widgetPlacements"
        static let appWidgetDisplays = "docky.appWidgetDisplays"
        static let trailingItems = "docky.trailingItems"
        static let hasSeenDockEditorHint = "docky.hasSeenDockEditorHint"
        static let photoFrameBookmarks = "docky.photoFrameBookmarks"
    }

    private enum DefaultValues {
        static let windowPosition: DockWindowPosition = .system
        static let windowDisplayTarget: DockWindowDisplayTarget = .primaryDisplay
        static let windowSpaceBehavior: DockWindowSpaceBehavior = .allSpaces
        static let autohidesWindow = false
        static let showsAppBadges = true
        static let allowsWidgetLinkInstalls = false
        static let folderBadgeMode: FolderBadgeMode = .combined
        static let folderBadgePreviewStyle: FolderBadgePreviewStyle = .dot
        static let opensAtLogin = true
        static let autohideWindowDelay: TimeInterval = 0.5
        static let fullscreenRevealDelay: TimeInterval = 0.5
        static let windowPreviewHoverDelay: TimeInterval = 1.0
        static let enablesWidgetHoverPreview = true
        static let widgetHoverPreviewSpans: Set<TileSpan> = Set(TileSpan.allCases)
        static let widgetHoverPreviewDelay: TimeInterval = 1
        static let showsRunningApps = true
        static let showsMinimizedWindows = true
        static let enablesShelveMode = false
        static let shelveHidesFinder = true
        static let shelveHidesTrash = true
        static let hidesRecentApps = false
        static let taskbarSpaceScope: SpaceScope = .allSpaces
        static let hidesProfileStrip = false
        static let appTileFrontmostClickBehavior: AppTileFrontmostClickBehavior = .none
        static let fileBrowser: FileBrowser = .finder
        static let appIconOverrides: [AppIconOverride] = []
        static let trashIconOverrides: [TrashIconOverride] = []
        static let folderIconOverrides: [FolderIconOverride] = []
        static let launchpadIconPath: String? = nil
        static let launchpadIconPaddingFraction: CGFloat? = nil
        static let hiddenAppBundleIdentifiers: [String] = []
        static let showsGroupedOpenedAppsInDock = true
        static let enablesLaunchpadOverlay = true
        static let enablesStartMenuOverlay = true
        static let opensStartMenuFromFinderTile = false
        static let launchpadOverlayTransparency: CGFloat = 0.75
        static let launchpadGridColumnCount = 7
        static let launchpadGridRowCount = 5
        static let launchpadBaseIconSize: CGFloat = 128
        static let launchpadBaseIconSizeMin: CGFloat = 48
        static let launchpadBaseIconSizeMax: CGFloat = 192
        static let launchpadColumnSpacing: CGFloat = 96
        static let launchpadSpacingMin: CGFloat = 0
        static let launchpadSpacingMax: CGFloat = 96
        static let launchpadBackgroundImagePath: String? = nil
        static let launchpadBackgroundBlursImage = true
        static let launchpadLayoutAxis: LaunchpadLayoutAxis = .defaultForCurrentOS
        static let launchpadSortMode: LaunchpadSortMode = .manual
        static let launchpadShortcut = KeyboardShortcut.empty
        static let enablesWindowSwitcher = true
        static let includesMinimizedWindows = true
        static let windowSwitcherShortcut = KeyboardShortcut(keyCode: 48, modifierFlags: [.option])
        static let replacesSystemCommandTab = false
        static let showsWindowSwitcherFocusPreview = false
        static let windowSwitcherPreviewMode: WindowSwitcherPreviewMode = .inPlace
        static let windowSwitcherSpaceScope: SpaceScope = .allSpaces
        static let switcherMinimizeKeyCode: UInt16 = 46
        static let switcherCloseKeyCode: UInt16 = 13
        static let switcherZoomKeyCode: UInt16 = 6
        static let pinnedAppBundleIdentifiers: [String] = []
        static let pinnedItems: [PinnedTileItem] = []
        static let widgetPlacements: [WidgetPlacement] = []
        static let appWidgetDisplays: [AppWidgetDisplay] = []
        static let trailingItems: [TrailingTileItem] = []
        static let hasSeenDockEditorHint = false
    }

    private init() {
        self.defaults = .standard
        DockLegacyPreferenceMigration.discardOverlapSettings(in: defaults)
        let storedWindowPosition = defaults.string(forKey: Keys.windowPosition)
        let storedWindowDisplayTarget = defaults.string(forKey: Keys.windowDisplayTarget)
        let storedWindowSpaceBehavior = defaults.string(forKey: Keys.windowSpaceBehavior)
        let storedAutohidesWindow = defaults.object(forKey: Keys.autohidesWindow) as? Bool
        let storedShowsAppBadges = defaults.object(forKey: Keys.showsAppBadges) as? Bool
        let storedAllowsWidgetLinkInstalls = defaults.object(forKey: Keys.allowsWidgetLinkInstalls) as? Bool
        let storedFolderBadgeMode = defaults.string(forKey: Keys.folderBadgeMode)
        let storedFolderBadgePreviewStyle = defaults.string(forKey: Keys.folderBadgePreviewStyle)
        let storedOpensAtLogin = defaults.object(forKey: Keys.opensAtLogin) as? Bool
        let storedAutohideWindowDelay = defaults.object(forKey: Keys.autohideWindowDelay) as? Double
        let storedWindowsTaskbarHeight = defaults.object(forKey: Keys.windowsTaskbarHeight) as? Double
        let storedFullscreenRevealDelay = defaults.object(forKey: Keys.fullscreenRevealDelay) as? Double
        let storedWindowPreviewHoverDelay = defaults.object(forKey: Keys.windowPreviewHoverDelay) as? Double
        let storedEnablesWidgetHoverPreview = defaults.object(forKey: Keys.enablesWidgetHoverPreview) as? Bool
        let storedWidgetHoverPreviewSpans = defaults.array(forKey: Keys.widgetHoverPreviewSpans) as? [Int]
        let storedWidgetHoverPreviewDelay = defaults.object(forKey: Keys.widgetHoverPreviewDelay) as? Double
        let storedShowsRunningApps = defaults.object(forKey: Keys.showsRunningApps) as? Bool
        let storedShowsMinimizedWindows = defaults.object(forKey: Keys.showsMinimizedWindows) as? Bool
        let storedEnablesShelveMode = defaults.object(forKey: Keys.enablesShelveMode) as? Bool
        let storedShelveHidesFinder = defaults.object(forKey: Keys.shelveHidesFinder) as? Bool
        let storedShelveHidesTrash = defaults.object(forKey: Keys.shelveHidesTrash) as? Bool
        let storedHidesRecentApps = defaults.object(forKey: Keys.hidesRecentApps) as? Bool
        let storedTaskbarSpaceScope = defaults.string(forKey: Keys.taskbarSpaceScope)
        let storedHidesProfileStrip = defaults.object(forKey: Keys.hidesProfileStrip) as? Bool
        let storedAppTileFrontmostClickBehavior = defaults.string(forKey: Keys.appTileFrontmostClickBehavior)
        let storedFileBrowser = defaults.string(forKey: Keys.fileBrowser)
        let storedAppIconOverrides = defaults.data(forKey: Keys.appIconOverrides)
        let storedTrashIconOverrides = defaults.data(forKey: Keys.trashIconOverrides)
        let storedFolderIconOverrides = defaults.data(forKey: Keys.folderIconOverrides)
        let storedLaunchpadIconPath = defaults.string(forKey: Keys.launchpadIconPath)
        let storedLaunchpadIconPaddingFraction = defaults.object(forKey: Keys.launchpadIconPaddingFraction) as? Double
        let storedHiddenAppBundleIdentifiers = defaults.stringArray(forKey: Keys.hiddenAppBundleIdentifiers)
        let storedShowsGroupedOpenedAppsInDock = defaults.object(forKey: Keys.showsGroupedOpenedAppsInDock) as? Bool
        let storedEnablesLaunchpadOverlay = defaults.object(forKey: Keys.enablesLaunchpadOverlay) as? Bool
        let storedEnablesStartMenuOverlay = defaults.object(forKey: Keys.enablesStartMenuOverlay) as? Bool
        let storedOpensStartMenuFromFinderTile = defaults.object(forKey: Keys.opensStartMenuFromFinderTile) as? Bool
        let storedLaunchpadOverlayTransparency = defaults.object(forKey: Keys.launchpadOverlayTransparency) as? Double
        let storedLaunchpadGridColumnCount = defaults.object(forKey: Keys.launchpadGridColumnCount) as? Int
        let storedLaunchpadGridRowCount = defaults.object(forKey: Keys.launchpadGridRowCount) as? Int
        let storedLaunchpadBaseIconSize = defaults.object(forKey: Keys.launchpadBaseIconSize) as? Double
        let storedLaunchpadColumnSpacing = defaults.object(forKey: Keys.launchpadColumnSpacing) as? Double
        let storedLaunchpadBackgroundImagePath = defaults.string(forKey: Keys.launchpadBackgroundImagePath)
        let storedLaunchpadBackgroundBlursImage = defaults.object(forKey: Keys.launchpadBackgroundBlursImage) as? Bool
        let storedLaunchpadLayoutAxis = defaults.string(forKey: Keys.launchpadLayoutAxis)
        let storedLaunchpadSortMode = defaults.string(forKey: Keys.launchpadSortMode)
        let storedLaunchpadShortcut = defaults.data(forKey: Keys.launchpadShortcut)
        let storedEnablesWindowSwitcher = defaults.object(forKey: Keys.enablesWindowSwitcher) as? Bool
        let storedIncludesMinimizedWindows = defaults.object(forKey: Keys.includesMinimizedWindows) as? Bool
        let storedWindowSwitcherShortcut = defaults.data(forKey: Keys.windowSwitcherShortcut)
        let storedReplacesSystemCommandTab = defaults.object(forKey: Keys.replacesSystemCommandTab) as? Bool
        let storedShowsWindowSwitcherFocusPreview = defaults.object(forKey: Keys.showsWindowSwitcherFocusPreview) as? Bool
        let storedWindowSwitcherPreviewMode = defaults.string(forKey: Keys.windowSwitcherPreviewMode)
        let storedWindowSwitcherSpaceScope = defaults.string(forKey: Keys.windowSwitcherSpaceScope)
        let storedWindowSwitcherFontSize = defaults.object(forKey: Keys.windowSwitcherFontSize) as? Double
        let storedWindowSwitcherIconSize = defaults.object(forKey: Keys.windowSwitcherIconSize) as? Double
        let storedSwitcherMinimizeKeyCode = defaults.object(forKey: Keys.switcherMinimizeKeyCode) as? Int
        let storedSwitcherCloseKeyCode = defaults.object(forKey: Keys.switcherCloseKeyCode) as? Int
        let storedSwitcherZoomKeyCode = defaults.object(forKey: Keys.switcherZoomKeyCode) as? Int
        let storedPinnedAppBundleIdentifiers = defaults.stringArray(forKey: Keys.pinnedAppBundleIdentifiers)
        let storedPinnedItems = defaults.data(forKey: Keys.pinnedItems)
        let storedWidgetPlacements = defaults.data(forKey: Keys.widgetPlacements)
        let storedAppWidgetDisplays = defaults.data(forKey: Keys.appWidgetDisplays)
        let storedTrailingItems = defaults.data(forKey: Keys.trailingItems)
        let storedHasSeenDockEditorHint = defaults.object(forKey: Keys.hasSeenDockEditorHint) as? Bool
        let initialPinnedAppBundleIdentifiers = storedPinnedAppBundleIdentifiers ?? DefaultValues.pinnedAppBundleIdentifiers
        let initialPinnedItems = Self.decodePinnedItems(from: storedPinnedItems)
            ?? initialPinnedAppBundleIdentifiers.map(PinnedTileItem.app(bundleIdentifier:))
        self.windowPosition = (storedWindowPosition.flatMap(DockWindowPosition.init(rawValue:)) ?? DefaultValues.windowPosition)
        self.windowDisplayTarget = (storedWindowDisplayTarget.flatMap(DockWindowDisplayTarget.init(rawValue:)) ?? DefaultValues.windowDisplayTarget)
        self.windowSpaceBehavior = (storedWindowSpaceBehavior.flatMap(DockWindowSpaceBehavior.init(rawValue:)) ?? DefaultValues.windowSpaceBehavior)
        self.autohidesWindow = storedAutohidesWindow ?? DefaultValues.autohidesWindow
        self.showsAppBadges = storedShowsAppBadges ?? DefaultValues.showsAppBadges
        self.allowsWidgetLinkInstalls = storedAllowsWidgetLinkInstalls ?? DefaultValues.allowsWidgetLinkInstalls
        self.folderBadgeMode = storedFolderBadgeMode
            .flatMap(FolderBadgeMode.init(rawValue:))
            ?? DefaultValues.folderBadgeMode
        self.folderBadgePreviewStyle = storedFolderBadgePreviewStyle
            .flatMap(FolderBadgePreviewStyle.init(rawValue:))
            ?? DefaultValues.folderBadgePreviewStyle
        self.opensAtLogin = storedOpensAtLogin ?? LaunchAtLoginService.shared.isEnabled
        self.autohideWindowDelay = max(storedAutohideWindowDelay ?? DefaultValues.autohideWindowDelay, 0)
        self.windowsTaskbarHeight = WindowsTaskbarMetrics.clampedHeight(
            storedWindowsTaskbarHeight.map { CGFloat($0) } ?? WindowsTaskbarMetrics.standardHeight)
        self.fullscreenRevealDelay = max(storedFullscreenRevealDelay ?? DefaultValues.fullscreenRevealDelay, 0)
        self.windowPreviewHoverDelay = max(storedWindowPreviewHoverDelay ?? DefaultValues.windowPreviewHoverDelay, 0)
        self.enablesWidgetHoverPreview = storedEnablesWidgetHoverPreview ?? DefaultValues.enablesWidgetHoverPreview
        self.widgetHoverPreviewSpans = storedWidgetHoverPreviewSpans
            .map { Set($0.compactMap(TileSpan.init(rawValue:))) }
            ?? DefaultValues.widgetHoverPreviewSpans
        self.widgetHoverPreviewDelay = max(storedWidgetHoverPreviewDelay ?? DefaultValues.widgetHoverPreviewDelay, 0)
        self.showsRunningApps = storedShowsRunningApps ?? DefaultValues.showsRunningApps
        self.showsMinimizedWindows = storedShowsMinimizedWindows ?? DefaultValues.showsMinimizedWindows
        self.enablesShelveMode = storedEnablesShelveMode ?? DefaultValues.enablesShelveMode
        self.shelveHidesFinder = storedShelveHidesFinder ?? DefaultValues.shelveHidesFinder
        self.shelveHidesTrash = storedShelveHidesTrash ?? DefaultValues.shelveHidesTrash
        self.hidesRecentApps = storedHidesRecentApps ?? DefaultValues.hidesRecentApps
        self.taskbarSpaceScope = storedTaskbarSpaceScope.flatMap(SpaceScope.init(rawValue:))
            ?? DefaultValues.taskbarSpaceScope
        self.hidesProfileStrip = storedHidesProfileStrip ?? DefaultValues.hidesProfileStrip
        self.appTileFrontmostClickBehavior = storedAppTileFrontmostClickBehavior
            .flatMap(AppTileFrontmostClickBehavior.init(rawValue:))
            ?? DefaultValues.appTileFrontmostClickBehavior
        self.fileBrowser = storedFileBrowser.flatMap(FileBrowser.init(rawValue:)) ?? DefaultValues.fileBrowser
        self.appIconOverrides = Self.decodeAppIconOverrides(from: storedAppIconOverrides) ?? DefaultValues.appIconOverrides
        self.trashIconOverrides = Self.decodeTrashIconOverrides(from: storedTrashIconOverrides) ?? DefaultValues.trashIconOverrides
        self.folderIconOverrides = Self.decodeFolderIconOverrides(from: storedFolderIconOverrides) ?? DefaultValues.folderIconOverrides
        self.launchpadIconPath = storedLaunchpadIconPath ?? DefaultValues.launchpadIconPath
        self.launchpadIconPaddingFraction = storedLaunchpadIconPaddingFraction.map { CGFloat($0) }
        self.hiddenAppBundleIdentifiers = Self.normalizedBundleIdentifiers(storedHiddenAppBundleIdentifiers ?? DefaultValues.hiddenAppBundleIdentifiers)
        self.showsGroupedOpenedAppsInDock = storedShowsGroupedOpenedAppsInDock ?? DefaultValues.showsGroupedOpenedAppsInDock
        self.enablesLaunchpadOverlay = storedEnablesLaunchpadOverlay ?? DefaultValues.enablesLaunchpadOverlay
        self.enablesStartMenuOverlay = storedEnablesStartMenuOverlay ?? DefaultValues.enablesStartMenuOverlay
        self.opensStartMenuFromFinderTile = storedOpensStartMenuFromFinderTile ?? DefaultValues.opensStartMenuFromFinderTile
        self.launchpadOverlayTransparency = min(max(
            storedLaunchpadOverlayTransparency.map { CGFloat($0) } ?? DefaultValues.launchpadOverlayTransparency,
            0
        ), 1)
        self.launchpadGridColumnCount = max(storedLaunchpadGridColumnCount ?? DefaultValues.launchpadGridColumnCount, 1)
        self.launchpadGridRowCount = max(storedLaunchpadGridRowCount ?? DefaultValues.launchpadGridRowCount, 1)
        self.launchpadBaseIconSize = min(
            max(
                storedLaunchpadBaseIconSize.map { CGFloat($0) } ?? DefaultValues.launchpadBaseIconSize,
                DefaultValues.launchpadBaseIconSizeMin
            ),
            DefaultValues.launchpadBaseIconSizeMax
        )
        self.launchpadColumnSpacing = min(
            max(
                storedLaunchpadColumnSpacing.map { CGFloat($0) } ?? DefaultValues.launchpadColumnSpacing,
                DefaultValues.launchpadSpacingMin
            ),
            DefaultValues.launchpadSpacingMax
        )
        self.launchpadBackgroundImagePath = storedLaunchpadBackgroundImagePath
        self.launchpadBackgroundBlursImage = storedLaunchpadBackgroundBlursImage ?? DefaultValues.launchpadBackgroundBlursImage
        self.launchpadLayoutAxis = storedLaunchpadLayoutAxis
            .flatMap(LaunchpadLayoutAxis.init(rawValue:))
            ?? DefaultValues.launchpadLayoutAxis
        self.launchpadSortMode = storedLaunchpadSortMode
            .flatMap(LaunchpadSortMode.init(rawValue:))
            ?? DefaultValues.launchpadSortMode
        self.launchpadShortcut = Self.decodeKeyboardShortcut(from: storedLaunchpadShortcut) ?? DefaultValues.launchpadShortcut
        self.enablesWindowSwitcher = storedEnablesWindowSwitcher ?? DefaultValues.enablesWindowSwitcher
        self.includesMinimizedWindows = storedIncludesMinimizedWindows ?? DefaultValues.includesMinimizedWindows
        self.windowSwitcherShortcut = Self.decodeKeyboardShortcut(from: storedWindowSwitcherShortcut) ?? DefaultValues.windowSwitcherShortcut
        self.replacesSystemCommandTab = storedReplacesSystemCommandTab ?? DefaultValues.replacesSystemCommandTab
        self.showsWindowSwitcherFocusPreview = storedShowsWindowSwitcherFocusPreview ?? DefaultValues.showsWindowSwitcherFocusPreview
        self.windowSwitcherPreviewMode = storedWindowSwitcherPreviewMode.flatMap(WindowSwitcherPreviewMode.init(rawValue:)) ?? DefaultValues.windowSwitcherPreviewMode
        self.windowSwitcherSpaceScope = storedWindowSwitcherSpaceScope.flatMap(SpaceScope.init(rawValue:))
            ?? DefaultValues.windowSwitcherSpaceScope
        self.windowSwitcherFontSize = WindowSwitcherGeometry.clampedFontSize(
            storedWindowSwitcherFontSize.map { CGFloat($0) } ?? WindowSwitcherGeometry.Metrics.defaultFontSize)
        self.windowSwitcherIconSize = WindowSwitcherGeometry.clampedIconSize(
            storedWindowSwitcherIconSize.map { CGFloat($0) } ?? WindowSwitcherGeometry.Metrics.defaultIconSize)
        self.switcherMinimizeKeyCode = storedSwitcherMinimizeKeyCode.map(UInt16.init) ?? DefaultValues.switcherMinimizeKeyCode
        self.switcherCloseKeyCode = storedSwitcherCloseKeyCode.map(UInt16.init) ?? DefaultValues.switcherCloseKeyCode
        self.switcherZoomKeyCode = storedSwitcherZoomKeyCode.map(UInt16.init) ?? DefaultValues.switcherZoomKeyCode
        self.pinnedAppBundleIdentifiers = initialPinnedAppBundleIdentifiers
        self.pinnedItems = initialPinnedItems
        self.widgetPlacements = Self.decodeWidgetPlacements(from: storedWidgetPlacements) ?? DefaultValues.widgetPlacements
        self.appWidgetDisplays = Self.decodeAppWidgetDisplays(from: storedAppWidgetDisplays) ?? DefaultValues.appWidgetDisplays
        self.trailingItems = Self.decodeTrailingItems(from: storedTrailingItems) ?? DefaultValues.trailingItems
        self.hasSeenDockEditorHint = storedHasSeenDockEditorHint ?? DefaultValues.hasSeenDockEditorHint
        self.photoFrameBookmarks = (defaults.array(forKey: Keys.photoFrameBookmarks) as? [Data]) ?? []
    }

    func applySystemDockVisibilityPreference() {
        // Legacy overlap/coexistence preferences no longer change behavior,
        // including values imported from older profiles and backups.
        DockLegacyPreferenceMigration.discardOverlapSettings(in: defaults)
        SystemDockVisibilityService.shared.hide()
        syncSystemDockPositionIfNeeded()
    }

    func applyOpenAtLoginPreference() {
        guard !LaunchAtLoginService.shared.setEnabled(opensAtLogin) else {
            return
        }

        syncOpenAtLoginPreferenceFromSystem()
    }

    func enableOpenAtLoginOnFirstLaunchIfNeeded() {
        guard defaults.object(forKey: Keys.opensAtLogin) == nil else {
            return
        }

        opensAtLogin = true
    }

    /// Resets every setting in Settings' Taskbar pane: size, position,
    /// auto-hide, apps, app folders, and shelve mode. Profiles, app icons,
    /// hidden apps, and pinned tiles are untouched.
    func resetTaskbarToDefaults() {
        windowsTaskbarHeight = WindowsTaskbarMetrics.standardHeight

        // Position
        windowPosition = DefaultValues.windowPosition
        windowDisplayTarget = DefaultValues.windowDisplayTarget
        windowSpaceBehavior = DefaultValues.windowSpaceBehavior

        // Auto-hide
        autohidesWindow = DefaultValues.autohidesWindow
        autohideWindowDelay = DefaultValues.autohideWindowDelay
        fullscreenRevealDelay = DefaultValues.fullscreenRevealDelay

        // Apps
        showsRunningApps = DefaultValues.showsRunningApps
        hidesRecentApps = DefaultValues.hidesRecentApps
        taskbarSpaceScope = DefaultValues.taskbarSpaceScope
        showsMinimizedWindows = DefaultValues.showsMinimizedWindows
        showsAppBadges = DefaultValues.showsAppBadges
        appTileFrontmostClickBehavior = DefaultValues.appTileFrontmostClickBehavior

        // App folders
        showsGroupedOpenedAppsInDock = DefaultValues.showsGroupedOpenedAppsInDock
        folderBadgeMode = DefaultValues.folderBadgeMode
        folderBadgePreviewStyle = DefaultValues.folderBadgePreviewStyle

        // Shelve mode
        enablesShelveMode = DefaultValues.enablesShelveMode
        shelveHidesFinder = DefaultValues.shelveHidesFinder
        shelveHidesTrash = DefaultValues.shelveHidesTrash
    }

    func resetToDefaults() {
        windowPosition = DefaultValues.windowPosition
        windowDisplayTarget = DefaultValues.windowDisplayTarget
        windowSpaceBehavior = DefaultValues.windowSpaceBehavior
        autohidesWindow = DefaultValues.autohidesWindow
        showsAppBadges = DefaultValues.showsAppBadges
        folderBadgeMode = DefaultValues.folderBadgeMode
        folderBadgePreviewStyle = DefaultValues.folderBadgePreviewStyle
        opensAtLogin = DefaultValues.opensAtLogin
        autohideWindowDelay = DefaultValues.autohideWindowDelay
        fullscreenRevealDelay = DefaultValues.fullscreenRevealDelay
        windowsTaskbarHeight = WindowsTaskbarMetrics.standardHeight
        windowPreviewHoverDelay = DefaultValues.windowPreviewHoverDelay
        enablesWidgetHoverPreview = DefaultValues.enablesWidgetHoverPreview
        widgetHoverPreviewSpans = DefaultValues.widgetHoverPreviewSpans
        widgetHoverPreviewDelay = DefaultValues.widgetHoverPreviewDelay
        showsRunningApps = DefaultValues.showsRunningApps
        showsMinimizedWindows = DefaultValues.showsMinimizedWindows
        enablesShelveMode = DefaultValues.enablesShelveMode
        shelveHidesFinder = DefaultValues.shelveHidesFinder
        shelveHidesTrash = DefaultValues.shelveHidesTrash
        hidesRecentApps = DefaultValues.hidesRecentApps
        taskbarSpaceScope = DefaultValues.taskbarSpaceScope
        appTileFrontmostClickBehavior = DefaultValues.appTileFrontmostClickBehavior
        fileBrowser = DefaultValues.fileBrowser
        appIconOverrides = DefaultValues.appIconOverrides
        trashIconOverrides = DefaultValues.trashIconOverrides
        folderIconOverrides = DefaultValues.folderIconOverrides
        launchpadIconPath = DefaultValues.launchpadIconPath
        launchpadIconPaddingFraction = DefaultValues.launchpadIconPaddingFraction
        hiddenAppBundleIdentifiers = DefaultValues.hiddenAppBundleIdentifiers
        showsGroupedOpenedAppsInDock = DefaultValues.showsGroupedOpenedAppsInDock
        enablesLaunchpadOverlay = DefaultValues.enablesLaunchpadOverlay
        enablesStartMenuOverlay = DefaultValues.enablesStartMenuOverlay
        opensStartMenuFromFinderTile = DefaultValues.opensStartMenuFromFinderTile
        launchpadOverlayTransparency = DefaultValues.launchpadOverlayTransparency
        launchpadGridColumnCount = DefaultValues.launchpadGridColumnCount
        launchpadGridRowCount = DefaultValues.launchpadGridRowCount
        launchpadShortcut = DefaultValues.launchpadShortcut
        enablesWindowSwitcher = DefaultValues.enablesWindowSwitcher
        includesMinimizedWindows = DefaultValues.includesMinimizedWindows
        windowSwitcherShortcut = DefaultValues.windowSwitcherShortcut
        replacesSystemCommandTab = DefaultValues.replacesSystemCommandTab
        showsWindowSwitcherFocusPreview = DefaultValues.showsWindowSwitcherFocusPreview
        windowSwitcherPreviewMode = DefaultValues.windowSwitcherPreviewMode
        windowSwitcherSpaceScope = DefaultValues.windowSwitcherSpaceScope
        windowSwitcherFontSize = WindowSwitcherGeometry.Metrics.defaultFontSize
        windowSwitcherIconSize = WindowSwitcherGeometry.Metrics.defaultIconSize
        switcherMinimizeKeyCode = DefaultValues.switcherMinimizeKeyCode
        switcherCloseKeyCode = DefaultValues.switcherCloseKeyCode
        switcherZoomKeyCode = DefaultValues.switcherZoomKeyCode
        appWidgetDisplays = DefaultValues.appWidgetDisplays
        hasSeenDockEditorHint = DefaultValues.hasSeenDockEditorHint
    }

    private func syncSystemDockPositionIfNeeded() {
        // Only move the hidden macOS Dock to an edge the taskbar actually uses.
        guard windowPosition == effectiveWindowPosition else { return }

        let orientation: DockSettingsService.Orientation
        switch windowPosition {
        case .system, .top:
            return
        case .left:
            orientation = .left
        case .right:
            orientation = .right
        case .bottom:
            orientation = .bottom
        }

        SystemDockVisibilityService.shared.setOrientation(orientation)
    }

    private func syncOpenAtLoginPreferenceFromSystem() {
        let actualValue = LaunchAtLoginService.shared.isEnabled
        guard opensAtLogin != actualValue else {
            defaults.set(actualValue, forKey: Keys.opensAtLogin)
            return
        }

        isSyncingOpenAtLoginPreference = true
        opensAtLogin = actualValue
        isSyncingOpenAtLoginPreference = false
    }

    private func persistPinnedItems(_ items: [PinnedTileItem]) {
        guard let data = try? encoder.encode(items) else {
            defaults.removeObject(forKey: Keys.pinnedItems)
            return
        }

        defaults.set(data, forKey: Keys.pinnedItems)
    }

    private func persistWidgetPlacements(_ placements: [WidgetPlacement]) {
        guard let data = try? encoder.encode(placements) else {
            defaults.removeObject(forKey: Keys.widgetPlacements)
            return
        }

        defaults.set(data, forKey: Keys.widgetPlacements)
    }

    private func persistAppWidgetDisplays(_ displays: [AppWidgetDisplay]) {
        guard let data = try? encoder.encode(displays) else {
            defaults.removeObject(forKey: Keys.appWidgetDisplays)
            return
        }

        defaults.set(data, forKey: Keys.appWidgetDisplays)
    }

    private func persistTrailingItems(_ items: [TrailingTileItem]) {
        guard let data = try? encoder.encode(items) else {
            defaults.removeObject(forKey: Keys.trailingItems)
            return
        }

        defaults.set(data, forKey: Keys.trailingItems)
    }

    private func persistAppIconOverrides(_ overrides: [AppIconOverride]) {
        guard let data = try? encoder.encode(overrides) else {
            defaults.removeObject(forKey: Keys.appIconOverrides)
            return
        }

        defaults.set(data, forKey: Keys.appIconOverrides)
    }

    private func persistTrashIconOverrides(_ overrides: [TrashIconOverride]) {
        guard let data = try? encoder.encode(overrides) else {
            defaults.removeObject(forKey: Keys.trashIconOverrides)
            return
        }

        defaults.set(data, forKey: Keys.trashIconOverrides)
    }

    private func persistFolderIconOverrides(_ overrides: [FolderIconOverride]) {
        guard let data = try? encoder.encode(overrides) else {
            defaults.removeObject(forKey: Keys.folderIconOverrides)
            return
        }

        defaults.set(data, forKey: Keys.folderIconOverrides)
    }

    private func persistWindowSwitcherShortcut(_ shortcut: KeyboardShortcut) {
        guard let data = try? encoder.encode(shortcut) else {
            defaults.removeObject(forKey: Keys.windowSwitcherShortcut)
            return
        }

        defaults.set(data, forKey: Keys.windowSwitcherShortcut)
    }

    private func persistLaunchpadShortcut(_ shortcut: KeyboardShortcut) {
        guard let data = try? encoder.encode(shortcut) else {
            defaults.removeObject(forKey: Keys.launchpadShortcut)
            return
        }

        defaults.set(data, forKey: Keys.launchpadShortcut)
    }

    private static func decodeWidgetPlacements(from data: Data?) -> [WidgetPlacement]? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode([WidgetPlacement].self, from: data)
    }

    private static func decodeAppWidgetDisplays(from data: Data?) -> [AppWidgetDisplay]? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode([AppWidgetDisplay].self, from: data)
    }

    private static func decodeAppIconOverrides(from data: Data?) -> [AppIconOverride]? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode([AppIconOverride].self, from: data)
    }

    private static func decodeTrashIconOverrides(from data: Data?) -> [TrashIconOverride]? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode([TrashIconOverride].self, from: data)
    }

    private static func decodeFolderIconOverrides(from data: Data?) -> [FolderIconOverride]? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode([FolderIconOverride].self, from: data)
    }

    private static func decodeKeyboardShortcut(from data: Data?) -> KeyboardShortcut? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode(KeyboardShortcut.self, from: data)
    }

    private static func decodePinnedItems(from data: Data?) -> [PinnedTileItem]? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode([PinnedTileItem].self, from: data)
    }

    private static func decodeTrailingItems(from data: Data?) -> [TrailingTileItem]? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode([TrailingTileItem].self, from: data)
    }

    private static func normalizedBundleIdentifiers(_ bundleIdentifiers: [String]) -> [String] {
        Array(Set(bundleIdentifiers.filter { !$0.isEmpty })).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}
