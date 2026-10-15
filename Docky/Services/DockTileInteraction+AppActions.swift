import AppKit
import OSLog

extension DockTileInteraction {
    func viewContentSubmenuChildren(folder: FolderTile) -> [ContextAction] {
        var children: [ContextAction] = [
            .action(String(localized: "Grid"), isOn: folderContentViewMode == .grid) {
                TileStore.shared.setFolderContentViewMode(tileID: tile.id, folderURL: folder.url, mode: .grid)
            },
            .action(String(localized: "List"), isOn: folderContentViewMode == .list) {
                TileStore.shared.setFolderContentViewMode(tileID: tile.id, folderURL: folder.url, mode: .list)
            }
        ]

        if position == .bottom {
            children.append(
                .action(String(localized: "Fan"), isOn: folderContentViewMode == .fan) {
                    TileStore.shared.setFolderContentViewMode(tileID: tile.id, folderURL: folder.url, mode: .fan)
                }
            )
        }

        children.append(.divider)
        children.append(
            .action(String(localized: "Finder Window"), isOn: folderContentViewMode == .finder) {
                TileStore.shared.setFolderContentViewMode(tileID: tile.id, folderURL: folder.url, mode: .finder)
            }
        )

        return children
    }

    func appFolderContextActions(for folder: AppFolderTile) -> [ContextAction] {
        var actions = customDockyTileActions

        if !folder.apps.isEmpty {
            if !actions.isEmpty {
                actions.append(.divider)
            }
            actions.append(
                .action(String(localized: "Open All")) {
                    for app in folder.apps {
                        WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
                    }
                })
        }

        if let windowsSubmenu = appFolderWindowsSubmenu(for: folder) {
            if !actions.isEmpty {
                actions.append(.divider)
            }
            actions.append(windowsSubmenu)
        }

        let appActions = folder.apps.map { app in
            ContextAction.submenu(
                app.displayName,
                children: [
                    .action(String(localized: "Open")) {
                        WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
                    },
                    .action(String(localized: "Remove from Folder")) {
                        TileStore.shared.removeAppFromFolder(tileID: tile.id, bundleIdentifier: app.bundleIdentifier)
                    }
                ])
        }

        if !appActions.isEmpty {
            if !actions.isEmpty {
                actions.append(.divider)
            }
            actions.append(.submenu(String(localized: "Apps"), children: appActions))
        }

        return actions
    }

    /// "Windows" submenu for the folder tile: lists every visible (non-
    /// minimized) window across the folder's apps on every Space, in
    /// WindowRegistry MRU order, each focusable, plus a Tile sub-section for
    /// arranging the top two (or four) windows on the active Space side-by-side
    /// / stacked / in quarters. Returns nil when there are no visible windows
    /// so the submenu doesn't appear.
    func appFolderWindowsSubmenu(for folder: AppFolderTile) -> ContextAction? {
        let bundleIDs = Set(folder.apps.map(\.bundleIdentifier))
        guard !bundleIDs.isEmpty else { return nil }

        let windows = WindowRegistry.shared.windows.filter { window in
            bundleIDs.contains(window.bundleIdentifier) && !window.isMinimized
        }
        guard !windows.isEmpty else { return nil }

        var children: [ContextAction] = windows.map { window in
            .action(appWindowMenuTitle(for: window)) {
                _ = WorkspaceService.shared.focus(window: window)
            }
        }

        // Tiling arranges windows on the current Space only; moving windows
        // from other Spaces would flip between desktops while tiling.
        let tileable = windows.filter(\.isOnActiveSpace)
        if tileable.count >= 2 {
            let workspace = WorkspaceService.shared
            children.append(.divider)
            children.append(contentsOf: [
                .action(
                    "Left and Right",
                    image: contextMenuSymbol("rectangle.lefthalf.filled")
                ) { _ = workspace.tile(windows: tileable, layout: .leftRight) },
                .action(
                    "Right and Left",
                    image: contextMenuSymbol("rectangle.righthalf.filled")
                ) { _ = workspace.tile(windows: tileable, layout: .rightLeft) },
                .action(
                    "Top and Bottom",
                    image: contextMenuSymbol("rectangle.tophalf.filled")
                ) { _ = workspace.tile(windows: tileable, layout: .topBottom) },
                .action(
                    "Bottom and Top",
                    image: contextMenuSymbol("rectangle.bottomhalf.filled")
                ) { _ = workspace.tile(windows: tileable, layout: .bottomTop) }
            ])
            if tileable.count >= 3 {
                children.append(
                    .action(
                        "Quarters",
                        image: contextMenuSymbol("rectangle.split.2x2")
                    ) { _ = workspace.tile(windows: tileable, layout: .quarters) }
                )
            }
        }

        return .submenu(String(localized: "Windows"), children: children)
    }

    func appContextActions(
        for app: AppTile,
        modifierFlags: NSEvent.ModifierFlags,
        baseActions: [ContextAction]? = nil
    ) -> [ContextAction] {
        guard !app.bundleIdentifier.isEmpty else {
            return []
        }

        let workspace = WorkspaceService.shared
        let windows = workspace.appWindows(bundleIdentifier: app.bundleIdentifier)
        let actions =
            if let baseActions {
                injectingDockyAppOptions(into: baseActions, for: app)
            } else {
                fallbackAppContextActions(for: app, modifierFlags: modifierFlags)
            }
        let withWindows = injectingAppWindowActions(windows, into: actions)
        let withFinder = injectingFinderHomeNavigation(into: withWindows, for: app)
        return injectingRemoveFromFolder(into: withFinder, for: app)
    }

    /// Tile id format for inline / grouped-opened children of an app folder:
    /// `folder-running:<folderID>:<bundleIdentifier>`. When the tile under
    /// the cursor matches this shape, surface a "Remove from Folder" action
    /// so the user has a non-drag path to detach the app from its folder.
    func injectingRemoveFromFolder(
        into actions: [ContextAction],
        for app: AppTile
    ) -> [ContextAction] {
        let prefix = "folder-running:"
        let suffix = ":\(app.bundleIdentifier)"
        guard tile.id.hasPrefix(prefix),
            tile.id.hasSuffix(suffix),
            tile.id.count > prefix.count + suffix.count
        else {
            return actions
        }
        // Inline-child tile ids embed the folder's raw identifier; the
        // store looks folders up by their pinned-tile id ("pinned:<id>"),
        // so re-prefix before calling removeAppFromFolder.
        let rawFolderID = String(tile.id.dropFirst(prefix.count).dropLast(suffix.count))
        let folderTileID = "pinned:\(rawFolderID)"
        let bundleIdentifier = app.bundleIdentifier

        var result = actions
        if !result.isEmpty, result.last?.kind != .divider {
            result.append(.divider)
        }
        result.append(
            .action(
                String(localized: "Remove from Folder"),
                image: NSImage(systemSymbolName: "folder.badge.minus", accessibilityDescription: nil)
            ) {
                TileStore.shared.removeAppFromFolder(
                    tileID: folderTileID,
                    bundleIdentifier: bundleIdentifier
                )
            })
        return result
    }

    func injectingFinderHomeNavigation(
        into actions: [ContextAction],
        for app: AppTile
    ) -> [ContextAction] {
        guard app.bundleIdentifier == Self.finderBundleIdentifier else {
            return actions
        }

        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let homeName =
            (try? homeURL.resourceValues(forKeys: [.localizedNameKey]).localizedName)
            ?? homeURL.lastPathComponent
        let homeIcon = IconCacheService.shared.icon(forFileURL: homeURL)

        let homeSubmenu = ContextAction.lazySubmenu(homeName, image: homeIcon) {
            folderNavigationContextActions(for: homeURL)
        }

        // Touch the singleton so its Spotlight query is running by the
        // time the user opens the menu. First-ever right-click may still
        // produce an empty list until the initial gather finishes.
        _ = RecentFilesService.shared
        let recentEntries = recentFilesContextActions()

        var result: [ContextAction] = [homeSubmenu]
        if !recentEntries.isEmpty {
            result.append(.divider)
            result.append(contentsOf: recentEntries)
        }
        if let first = actions.first, first.kind != .divider {
            result.append(.divider)
        }
        result.append(contentsOf: actions)
        return result
    }

}
