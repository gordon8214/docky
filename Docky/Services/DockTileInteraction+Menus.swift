import AppKit
import OSLog

extension DockTileInteraction {
    func contextActions(modifierFlags: NSEvent.ModifierFlags) -> [ContextAction] {
        if tile.content == .divider && !isDockyPinnedTile && !isDockyTrailingTile { return dividerContextActions }
        if let actions = MenuCatalogService.shared.contextActions(for: tile, modifierFlags: modifierFlags),
            let merged = catalogContextActions(actions, flags: modifierFlags) {
            return merged
        }
        return defaultContextActions(modifierFlags: modifierFlags)
    }
    func catalogContextActions(_ catalog: [ContextAction], flags: NSEvent.ModifierFlags) -> [ContextAction]? {
        switch tile.content {
        case .app(let app): return appContextActions(for: app, modifierFlags: flags, baseActions: catalog)
        case .trash: return catalog
        case .launchpad, .startMenu: return appendingCustomActions(to: catalog)
        case .folder: return appendingFolderRemoval(to: folderPresentationContextActions + [.divider] + catalog)
        default: return nil
        }
    }
    func defaultContextActions(modifierFlags: NSEvent.ModifierFlags) -> [ContextAction] {
        switch tile.content {
        case .app(let app): return appContextActions(for: app, modifierFlags: modifierFlags)
        case .minimizedWindow(let window):
            return minimizedWindowContextActions(for: window, modifierFlags: modifierFlags)
        case .appFolder(let folder): return appFolderContextActions(for: folder)
        case .launchpad, .startMenu: return launcherContextActions()
        case .widget(let widget): return widgetContextActions(for: widget)
        case .smartStack(let stack): return smartStackContextActions(for: stack)
        case .folder(let folder): return folderContextActions(folder)
        case .trash: return trashContextActions
        case .spacer, .flexibleSpacer, .divider: return customDockyTileActions
        }
    }
    func appendingCustomActions(to base: [ContextAction]) -> [ContextAction] {
        guard !customDockyTileActions.isEmpty else { return base }
        return base + (base.isEmpty ? [] : [.divider]) + customDockyTileActions
    }
    func appendingFolderRemoval(to base: [ContextAction]) -> [ContextAction] {
        guard isDockyTrailingTile else { return base }
        return base + [.divider, .action(String(localized: "Remove from Dock")) { removeDockyTile() }]
    }
    func launcherContextActions() -> [ContextAction] {
        let action: ContextAction?
        if case .launchpad = tile.content {
            action =
                preferences.enablesLaunchpadOverlay
                ? .action(String(localized: "Open Launchpad")) { LaunchpadOverlayService.shared.present() } : nil
        } else {
            action =
                preferences.enablesStartMenuOverlay
                ? .action(String(localized: "Open Start Menu")) { StartMenuService.shared.present() } : nil
        }
        return appendingCustomActions(to: action.map { [$0] } ?? [])
    }
    func folderContextActions(_ folder: FolderTile) -> [ContextAction] {
        appendingFolderRemoval(
            to: folderPresentationContextActions + [
                .divider,
                .action(String(localized: "Open in Finder")) {
                    Task { _ = await AppleScriptService.shared.openFinderWindow(for: folder.url) }
                },
                .action(String(localized: "Reveal in Finder")) {
                    Task { _ = await AppleScriptService.shared.revealInFinder(folder.url) }
                }
            ])
    }
    var trashContextActions: [ContextAction] {
        [
            .action(String(localized: "Open Trash")) { Task { _ = await AppleScriptService.shared.openTrash() } },
            .divider,
            .action(String(localized: "Empty Trash"), isDestructive: true) {
                Task { _ = await AppleScriptService.shared.emptyTrash() }
            }
        ]
    }

    var folderPresentationContextActions: [ContextAction] {
        guard case .folder(let folder) = tile.content else {
            return []
        }

        return [
            .submenu(
                String(localized: "Display as"),
                children: [
                    .action(String(localized: "Folder"), isOn: folderDisplayMode == .folder) {
                        TileStore.shared.setFolderDisplayMode(tileID: tile.id, folderURL: folder.url, mode: .folder)
                    },
                    .action(String(localized: "Contents"), isOn: folderDisplayMode == .contents) {
                        TileStore.shared.setFolderDisplayMode(tileID: tile.id, folderURL: folder.url, mode: .contents)
                    }
                ]),
            .submenu(String(localized: "View Content as"), children: viewContentSubmenuChildren(folder: folder)),
            .submenu(
                String(localized: "Sort By"),
                children: FolderTileSortMode.allCases.map { mode in
                    .action(mode.title, isOn: folderSortMode == mode) {
                        TileStore.shared.setFolderSortMode(tileID: tile.id, folderURL: folder.url, mode: mode)
                    }
                })
        ]
    }

    var folderDisplayMode: FolderTileDisplayMode {
        guard case .folder(let folder) = tile.content else {
            return .contents
        }
        return TileStore.shared.folderDisplayMode(tileID: tile.id, folderURL: folder.url)
    }

    var folderContentViewMode: FolderTileContentViewMode {
        guard case .folder(let folder) = tile.content else {
            return .grid
        }

        return TileStore.shared.folderContentViewMode(tileID: tile.id, folderURL: folder.url)
    }

    var appFolderContentViewMode: FolderTileContentViewMode {
        guard case .appFolder = tile.content else {
            return .grid
        }

        return TileStore.shared.appFolderContentViewMode(tileID: tile.id)
    }

    var appFolderDisplayMode: AppFolderTileDisplayMode {
        guard case .appFolder = tile.content else {
            return .grid
        }

        return TileStore.shared.appFolderDisplayMode(tileID: tile.id)
    }

    var folderSortMode: FolderTileSortMode {
        guard case .folder(let folder) = tile.content else {
            return .dateAdded
        }

        return TileStore.shared.folderSortMode(tileID: tile.id, folderURL: folder.url)
    }

    var customDockyTileActions: [ContextAction] {
        guard isDockyPinnedTile || isDockyTrailingTile else {
            return []
        }

        var actions: [ContextAction] = [
            .action(String(localized: "Edit Dock...")) {
                DockEditModeService.shared.enter()
            }
        ]

        if case .spacer = tile.content {
            actions.append(.divider)
            actions.append(
                .action(String(localized: "Remove from Dock")) {
                    removeDockyTile()
                })
        }

        if case .flexibleSpacer = tile.content {
            actions.append(.divider)
            actions.append(
                .action(String(localized: "Remove from Dock")) {
                    removeDockyTile()
                })
        }

        if case .divider = tile.content {
            actions.append(.divider)
            actions.append(
                .action(String(localized: "Remove from Dock")) {
                    removeDockyTile()
                })
        }

        if case .widget = tile.content {
            actions.append(.divider)
            actions.append(
                .action(String(localized: "Remove from Dock")) {
                    removeDockyTile()
                })
        }

        if case .smartStack = tile.content {
            actions.append(.divider)
            actions.append(
                .action(String(localized: "Remove from Dock")) {
                    removeDockyTile()
                })
        }

        if case .appFolder = tile.content {
            actions.append(.divider)
            actions.append(
                .submenu(
                    String(localized: "Display As"),
                    children: [
                        .action(String(localized: "Grid"), isOn: appFolderDisplayMode == .grid) {
                            TileStore.shared.setAppFolderDisplayMode(tileID: tile.id, mode: .grid)
                        },
                        .action(String(localized: "Stack"), isOn: appFolderDisplayMode == .stack) {
                            TileStore.shared.setAppFolderDisplayMode(tileID: tile.id, mode: .stack)
                        }
                    ]))
            actions.append(
                .submenu(
                    String(localized: "View Content as"),
                    children: [
                        .action(String(localized: "Grid"), isOn: appFolderContentViewMode == .grid) {
                            TileStore.shared.setAppFolderContentViewMode(tileID: tile.id, mode: .grid)
                        },
                        .action(String(localized: "List"), isOn: appFolderContentViewMode == .list) {
                            TileStore.shared.setAppFolderContentViewMode(tileID: tile.id, mode: .list)
                        },
                        .action(String(localized: "Inline"), isOn: appFolderContentViewMode == .inline) {
                            TileStore.shared.setAppFolderContentViewMode(tileID: tile.id, mode: .inline)
                        }
                    ]))
            actions.append(.divider)
            actions.append(
                .action(String(localized: "Rename Folder...")) {
                    TileStore.shared.presentRenameAppFolderPrompt(tileID: tile.id)
                })
            actions.append(
                .action(String(localized: "Ungroup Folder")) {
                    TileStore.shared.ungroupAppFolder(tileID: tile.id)
                })
        }

        switch tile.content {
        case .launchpad, .startMenu:
            actions.append(.divider)
            actions.append(
                .action(String(localized: "Remove from Dock")) {
                    removeDockyTile()
                })
        default:
            break
        }

        return actions
    }
}
