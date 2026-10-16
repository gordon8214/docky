import AppKit
import OSLog

extension DockTileInteraction {
    var isDockyPinnedTile: Bool {
        tile.id.hasPrefix("pinned:")
    }

    var isDockyTrailingTile: Bool {
        tile.id.hasPrefix("trailing:")
    }

    func removeDockyTile() {
        if isDockyPinnedTile {
            TileStore.shared.removePinnedItem(tileID: tile.id)
        } else if isDockyTrailingTile {
            TileStore.shared.removeTrailingItem(tileID: tile.id)
        }
    }

    /// True when this tile represents the currently foreground app
    /// (or any app inside a grouped folder is foreground). Like the running
    /// indicator, it follows the taskbar's Space scope, so an app frontmost
    /// with no window on a Space shown now isn't highlighted.
    var isFrontmostTile: Bool {
        switch tile.content {
        case .app(let app):
            return workspace.isFrontmost(bundleIdentifier: app.bundleIdentifier)
                && workspace.isOpenOnTaskbar(bundleIdentifier: app.bundleIdentifier)
        case .appFolder(let folder):
            return folder.apps.contains { app in
                workspace.isFrontmost(bundleIdentifier: app.bundleIdentifier)
                    && workspace.isOpenOnTaskbar(bundleIdentifier: app.bundleIdentifier)
            }
        case .folder, .launchpad, .startMenu, .widget, .smartStack, .spacer, .flexibleSpacer, .divider, .trash,
            .minimizedWindow:
            return false
        }
    }

    /// Notification badge text to paint over this tile, or `nil` when the
    /// feature is off or the app has no badge. App folders show the summed
    /// numeric badge of the apps they contain (mirroring how the count rolls
    /// up when running apps collapse into a folder).
    var badgeText: String? {
        guard preferences.showsAppBadges else { return nil }
        switch tile.content {
        case .app(let app):
            return dockBadges.badge(forBundleIdentifier: app.bundleIdentifier)
        case .appFolder(let folder):
            // In per-app mode the badges are painted on the individual
            // preview icons instead of rolled up here — but the grid
            // preview is the only layout that can show them. Stack mode
            // can't badge buried icons, so it falls back to the combined
            // total like `.combined` does.
            if preferences.folderBadgeMode == .perApp, appFolderDisplayMode == .grid {
                return nil
            }
            let total = folder.apps.reduce(0) { sum, app in
                sum + (dockBadges.badge(forBundleIdentifier: app.bundleIdentifier).flatMap(Int.init) ?? 0)
            }
            return total > 0 ? String(total) : nil
        case .folder, .launchpad, .startMenu, .widget, .smartStack, .spacer, .flexibleSpacer, .divider, .trash,
            .minimizedWindow:
            return nil
        }
    }

    /// Whether the tile shows the running-app indicator. Under the taskbar's
    /// Active Space scope, only apps with a window on a Space shown now, and
    /// hidden apps, do (see `WorkspaceService.isOpenOnTaskbar`).
    var showsRunningIndicator: Bool {
        switch tile.content {
        case .app(let app):
            workspace.isOpenOnTaskbar(bundleIdentifier: app.bundleIdentifier)
        case .minimizedWindow:
            false
        case .appFolder(let folder):
            folder.apps.contains { app in
                workspace.isOpenOnTaskbar(bundleIdentifier: app.bundleIdentifier)
            }
        case .launchpad, .startMenu, .widget, .smartStack, .folder, .spacer, .flexibleSpacer, .divider, .trash:
            false
        }
    }

    /// An underline spanning the icon along the taskbar axis.
    var runningIndicatorSize: CGSize {
        if position.isVertical {
            CGSize(width: runningIndicatorThickness, height: effectiveTileSize)
        } else {
            CGSize(width: effectiveTileSize, height: runningIndicatorThickness)
        }
    }

    var runningIndicatorThickness: CGFloat {
        4 * runningIndicatorScale
    }

    var runningIndicatorInset: CGFloat {
        max(1, round(2 * runningIndicatorScale))
    }

    var runningIndicatorScale: CGFloat {
        let baseScale = max(0.5, min(1, effectiveTileSize / 48))
        return baseScale * WindowsTaskbarStyle.Tray.indicatorScale
    }

    var runningIndicatorOffsetVector: CGSize {
        let baseInward = max((WindowsTaskbarStyle.Tray.verticalPadding / 2), 2)
        let totalInward = baseInward + WindowsTaskbarStyle.Tray.indicatorOffset

        switch position {
        case .top:
            return CGSize(width: 0, height: totalInward)
        case .bottom:
            return CGSize(width: 0, height: -totalInward)
        case .left:
            return CGSize(width: totalInward, height: 0)
        case .right:
            return CGSize(width: -totalInward, height: 0)
        }
    }

    var contentPadding: CGFloat {
        switch tile.content {
        case .divider:
            0
        default:
            WindowsTaskbarStyle.Tray.verticalPadding
        }
    }

    var nonAppContentPadding: CGFloat {
        if let span = widgetRenderedSpan, WindowsTaskbarStyle.Tray.fillsTile(span) {
            return 0
        }
        switch tile.content {
        case .app(let app) where app.displayedWidget != nil:
            return tileChromeInset
        case .appFolder, .widget, .smartStack, .folder, .trash:
            return tileChromeInset
        case .app, .launchpad, .startMenu, .minimizedWindow, .spacer, .flexibleSpacer, .divider:
            return 0
        }
    }

    /// Resolved tile icon padding. Widgets wider than one tile drop it
    /// so they fill their tile box.
    var appliedTileIconPadding: CGFloat {
        if let span = widgetRenderedSpan, WindowsTaskbarStyle.Tray.fillsTile(span) {
            return 0
        }
        return WindowsTaskbarStyle.Tray.iconPadding
    }

    /// Returns the widget's *rendered* span (compressed to .one when a
    /// vertical taskbar forces it) for any tile that hosts a widget. `nil`
    /// for non-widget tiles.
    var widgetRenderedSpan: TileSpan? {
        switch tile.content {
        case .widget(let widget):
            return renderedWidgetSpan(for: widget.effectiveSpan)
        case .smartStack(let stack):
            return renderedWidgetSpan(for: stack.span)
        case .app(let app) where app.displayedWidget != nil:
            return renderedWidgetSpan(for: app.displayedWidget?.effectiveSpan ?? .one)
        default:
            return nil
        }
    }

    var tileChromeInset: CGFloat {
        floor(effectiveTileSize * 3 / 32)
    }

    var contentInsets: CGSize {
        CGSize(
            width: nonAppContentPadding + (position.isVertical ? contentPadding : 0),
            height: nonAppContentPadding + (position.isVertical ? 0 : contentPadding)
        )
    }

    var effectiveTileSize: CGFloat {
        renderedTileSize ?? dockSettings.displayTileSize
    }

    func renderedWidgetSpan(for span: TileSpan) -> TileSpan {
        if position.isVertical {
            return .one
        }

        return span
    }

    var nonAppTileCornerRadius: CGFloat {
        if let span = widgetRenderedSpan, WindowsTaskbarStyle.Tray.fillsTile(span) {
            return 0
        }
        let maximumCornerRadius = max(0, (effectiveTileSize - nonAppContentPadding * 2) / 2)
        return min(effectiveTileSize * 0.225, maximumCornerRadius)
    }

    var position: ResolvedDockWindowPosition {
        preferences.effectiveWindowPosition.resolved(systemOrientation: dockSettings.orientation)
    }

    var inwardPopoverEdge: NSRectEdge {
        switch position {
        case .top:
            .minY
        case .left:
            .maxX
        case .right:
            .minX
        case .bottom:
            .maxY
        }
    }

    var inwardMenuEdge: NSRectEdge {
        inwardPopoverEdge
    }
}
