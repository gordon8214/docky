//
//  Tile.swift
//  Docky
//

import Foundation

struct Tile: Identifiable, Equatable {
    let id: String
    var content: TileContent

    nonisolated init(id: String = UUID().uuidString, content: TileContent) {
        self.id = id
        self.content = content
    }
}

enum TileContent: Equatable {
    case app(AppTile)
    case minimizedWindow(AppWindow)
    case appFolder(AppFolderTile)
    case launchpad(LaunchpadTile)
    case startMenu(StartMenuTile)
    case widget(WidgetTile)
    case smartStack(SmartStackTile)
    case folder(FolderTile)
    case spacer
    case flexibleSpacer
    case divider
    case trash
}

struct AppTile: Equatable {
    let bundleIdentifier: String
    let displayName: String
    let displayedWidget: WidgetTile?

    nonisolated init(
        bundleIdentifier: String,
        displayName: String,
        displayedWidget: WidgetTile? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.displayedWidget = displayedWidget
    }
}

struct AppFolderTile: Equatable {
    let identifier: String
    let displayName: String
    let apps: [AppTile]
    let displayMode: AppFolderTileDisplayMode
    let contentViewMode: FolderTileContentViewMode

    nonisolated init(
        identifier: String,
        displayName: String,
        apps: [AppTile],
        displayMode: AppFolderTileDisplayMode = .grid,
        contentViewMode: FolderTileContentViewMode = .grid
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.apps = apps
        self.displayMode = displayMode
        self.contentViewMode = contentViewMode
    }

    nonisolated var bundleIdentifiers: [String] {
        apps.map(\.bundleIdentifier)
    }
}

struct LaunchpadTile: Equatable {
    nonisolated static let spotlightBundleIdentifier = "com.apple.Spotlight"

    let identifier: String
    let title: String

    nonisolated init(identifier: String, title: String = "Launchpad") {
        self.identifier = identifier
        self.title = title
    }
}

/// Tile that, when clicked, toggles Docky's Start menu overlay. Renders
/// as a regular AppTileView pointed at Docky's own bundle id so the icon
/// pipeline resolves to the running app icon (and the user can swap it
/// out via the App Icons settings pane like the Launchpad tile).
struct StartMenuTile: Equatable {
    nonisolated static let iconBundleIdentifier = "gt.quintero.Docky"

    let identifier: String
    let title: String

    nonisolated init(identifier: String, title: String = "Start") {
        self.identifier = identifier
        self.title = title
    }
}

struct WidgetPlacement: Codable, Equatable, Identifiable {
    let kind: WidgetKind
    let ownerBundleIdentifier: String
    let span: TileSpan

    var id: String {
        "\(ownerBundleIdentifier):\(kind.rawValue)"
    }
}

struct AppWidgetDisplay: Codable, Equatable, Identifiable {
    let bundleIdentifier: String
    let kind: WidgetKind
    let span: TileSpan

    var id: String {
        bundleIdentifier
    }
}

struct WidgetTile: Equatable {
    let identifier: String
    let title: String
    let kind: WidgetKind
    let ownerBundleIdentifier: String
    let span: TileSpan
    /// Per-instance configuration; empty means default behavior.
    var settings: WidgetSettings = [:]

    @MainActor var effectiveSpan: TileSpan {
        kind.supportedSpans.contains(span) ? span : kind.supportedSpans.last ?? .one
    }
}

struct SmartStackTile: Equatable {
    let identifier: String
    let title: String
    let widgets: [WidgetTile]
    let span: TileSpan

    var allWidgetOwnerBundleIdentifiers: [String] {
        Array(Set(widgets.map(\.ownerBundleIdentifier))).sorted()
    }
}

struct FolderTile: Equatable {
    let url: URL
    let displayName: String
    let displayMode: FolderTileDisplayMode
    let contentViewMode: FolderTileContentViewMode
    let sortMode: FolderTileSortMode

    nonisolated init(
        url: URL,
        displayName: String,
        displayMode: FolderTileDisplayMode,
        contentViewMode: FolderTileContentViewMode = .grid,
        sortMode: FolderTileSortMode = .dateAdded
    ) {
        self.url = url
        self.displayName = displayName
        self.displayMode = displayMode
        self.contentViewMode = contentViewMode
        self.sortMode = sortMode
    }
}
