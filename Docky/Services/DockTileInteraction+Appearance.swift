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

    var isAppContent: Bool {
        if case .app = tile.content { return true }
        return false
    }

    /// Content types that participate in the press/drop-target darken.
    /// Apps, folders (both kinds), and trash are launchable/drop targets
    /// where the darken communicates "this is the thing you're acting
    /// on"; widgets/spacers/dividers don't need the affordance.
    var participatesInPressDarken: Bool {
        switch tile.content {
        case .app, .appFolder, .folder, .trash:
            return true
        case .minimizedWindow, .spacer, .flexibleSpacer, .divider, .launchpad, .startMenu, .widget, .smartStack:
            return false
        }
    }

    /// Combined darken trigger: pressed (mouse-down before release,
    /// tracked by `TilePressService`'s NSEvent monitor) or active
    /// drop-target. Drives the `.brightness` darken below.
    var pressDarkenSignal: Bool {
        participatesInPressDarken && (tilePress.pressedTileID == tile.id || isDocumentDropTarget)
    }

    var showsAppFolderDropBackdrop: Bool {
        isAppContent && isAppFolderDropTarget
    }

    var tileBodyOpacity: Double {
        1
    }

    /// `brightness(-0.35)` darkens icons in place without thinning them
    /// out the way a 0.5 opacity dim would (since opacity also makes the
    /// background show through, which on a transparent dock reads as
    /// "fading away" rather than "being pressed").
    var pressDarkenAmount: Double {
        pressDarkenSignal ? -0.35 : 0
    }

    /// Background drawn behind the tile when the cursor is over it.
    /// Drives the Win10-style "lighten on hover" treatment; respects
    /// the theme/user-supplied color, image, opacity, and clip radius.
    /// `EmptyView` when no source is set so the tile stays transparent.
    var hasHoverBackground: Bool {
        guard supportsHoverBackground else { return false }
        return preferences.effectiveTileHoverBackgroundImageURL != nil
            || preferences.effectiveTileHoverBackgroundColor != nil
    }

    /// Only "tappable" tiles (icons that act like apps or files) get
    /// the hover treatment. Widgets, smart stacks, and structural
    /// fixtures (dividers, spacers) stay flat, a hover halo on a
    /// widget reads as a misfire.
    var supportsHoverBackground: Bool {
        switch tile.content {
        case .app, .appFolder, .folder, .trash, .launchpad, .startMenu:
            true
        case .widget, .smartStack, .divider, .spacer, .flexibleSpacer,
            .minimizedWindow:
            false
        }
    }

    /// Background drawn under the *foreground* (frontmost) app's tile.
    /// Independent of hover, both can stack, with hover painted on top.
    /// Updates live via `WorkspaceService.frontmostBundleIdentifier`.
    var hasActiveBackground: Bool {
        preferences.effectiveTileActiveBackgroundImageURL != nil
            || preferences.effectiveTileActiveBackgroundColor != nil
    }

    /// True when this tile represents the currently foreground app
    /// (or any app inside a grouped folder is foreground).
    var isFrontmostTile: Bool {
        switch tile.content {
        case .app(let app):
            return workspace.isFrontmost(bundleIdentifier: app.bundleIdentifier)
        case .appFolder(let folder):
            return folder.apps.contains { app in
                workspace.isFrontmost(bundleIdentifier: app.bundleIdentifier)
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

    /// Effective drop shadow applied behind the tile's icon content.
    /// Returns `Color.clear` when no shadow color is set, combined
    /// with a 0 radius below, that makes `.shadow(...)` a true no-op.
    var showsRunningIndicator: Bool {
        switch tile.content {
        case .app(let app):
            workspace.isRunning(bundleIdentifier: app.bundleIdentifier)
        case .minimizedWindow:
            false
        case .appFolder(let folder):
            folder.apps.contains { app in
                workspace.isRunning(bundleIdentifier: app.bundleIdentifier)
            }
        case .launchpad, .startMenu, .widget, .smartStack, .folder, .spacer, .flexibleSpacer, .divider, .trash:
            false
        }
    }

    var runningIndicatorSize: CGSize {
        switch preferences.effectiveActiveIndicatorShape {
        case .none:
            .zero
        case .dot:
            CGSize(width: runningIndicatorThickness, height: runningIndicatorThickness)
        case .pill:
            if position.isVertical {
                CGSize(width: runningIndicatorThickness, height: runningIndicatorLength)
            } else {
                CGSize(width: runningIndicatorLength, height: runningIndicatorThickness)
            }
        case .underline:
            // Span the icon's full extent along the dock axis; stay
            // thin along the screen-facing axis. The overlay alignment +
            // existing offset keep it flush against the screen-facing
            // edge.
            if position.isVertical {
                CGSize(width: runningIndicatorThickness, height: effectiveTileSize)
            } else {
                CGSize(width: effectiveTileSize, height: runningIndicatorThickness)
            }
        case .image:
            if position.isVertical {
                CGSize(width: runningIndicatorImageThickness, height: runningIndicatorImageLength)
            } else {
                CGSize(width: runningIndicatorImageLength, height: runningIndicatorImageThickness)
            }
        }
    }

    var runningIndicatorThickness: CGFloat {
        4 * runningIndicatorScale
    }

    var runningIndicatorLength: CGFloat {
        12 * runningIndicatorScale
    }

    var runningIndicatorImageThickness: CGFloat {
        10 * runningIndicatorScale
    }

    var runningIndicatorImageLength: CGFloat {
        20 * runningIndicatorScale
    }

    var runningIndicatorInset: CGFloat {
        max(1, round(2 * runningIndicatorScale))
    }

    var runningIndicatorScale: CGFloat {
        let baseScale = max(0.5, min(1, effectiveTileSize / 48))
        return baseScale * max(0.25, preferences.effectiveActiveIndicatorScale)
    }

    var runningIndicatorOffsetVector: CGSize {
        let baseInward = max((layout.scaled(preferences.effectiveTileVerticalPadding) / 2), 2)
        let totalInward = baseInward + preferences.effectiveActiveIndicatorOffset

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

    var runningIndicatorImage: NSImage? {
        guard let url = preferences.effectiveActiveIndicatorImageURL else {
            return nil
        }

        return NSImage(contentsOf: url)
    }

    var contentPadding: CGFloat {
        switch tile.content {
        case .divider:
            0
        default:
            layout.scaled(preferences.effectiveTileVerticalPadding)
        }
    }

    var nonAppContentPadding: CGFloat {
        // Per-span widget override wins for widget-hosting tiles ,
        // a theme/user can collapse padding to 0 on 2x/3x widgets for
        // an edge-to-edge taskbar look without touching 1x.
        if let span = widgetRenderedSpan,
            let override = preferences.effectiveWidgetContentPadding(for: span) {
            return override
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

    /// Resolved tile icon padding. Widget tiles whose span opts out
    /// (via the theme's `ignoresAddedPaddings` escape hatch) collapse
    /// to zero so the widget can fill its tile box, needed when a
    /// theme adds icon padding for chunky app tiles but wants 2x/3x
    /// widgets edge-to-edge.
    var appliedTileIconPadding: CGFloat {
        if let span = widgetRenderedSpan,
            preferences.effectiveWidgetIgnoresAddedPaddings(for: span) {
            return 0
        }
        return layout.scaled(preferences.effectiveTileIconPadding)
    }

    /// Returns the widget's *rendered* span (compressed to .one when
    /// overflow compaction or vertical orientation forces it) for any
    /// tile that hosts a widget. `nil` for non-widget tiles.
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
        renderedTileSize ?? layout.scaled(dockSettings.displayTileSize)
    }

    func renderedWidgetSpan(for span: TileSpan) -> TileSpan {
        if layout.compactsWidgetsForOverflow || position.isVertical {
            return .one
        }

        return span
    }

    var availableWidgetSpans: [TileSpan] {
        // `.four` is theme-only: it can be injected via
        // `layout.insertions` but is not surfaced in the user's "Span"
        // submenu / palette so the widget editor stays focused on the
        // three user-facing sizes.
        let userFacing = TileSpan.allCases.filter { $0 != .four }
        return position.isVertical ? [.one] : userFacing
    }

    var nonAppTileCornerRadius: CGFloat {
        let maximumCornerRadius = max(0, (effectiveTileSize - nonAppContentPadding * 2) / 2)
        // Per-span override wins for widget tiles. Clamp to the
        // maximum so a theme that sets `cornerRadius: 999` doesn't
        // produce a malformed clip when the tile is small.
        if let span = widgetRenderedSpan,
            let override = preferences.effectiveWidgetCornerRadius(for: span) {
            return min(override, maximumCornerRadius)
        }
        return preferences.effectiveTileClipShape.resolvedCornerRadius(
            base: effectiveTileSize * 0.225,
            maximum: maximumCornerRadius
        )
    }

    /// Corner radius used when painting the app-folder-drop intent backdrop
    /// behind a plain `.app` tile. Mirrors `AppFolderTileView.iconGrid`'s
    /// container so the in-progress folder visually matches a finished one.
    var appFolderDropTargetCornerRadius: CGFloat {
        let maximumCornerRadius = max(0, effectiveTileSize / 2)
        return preferences.effectiveTileClipShape.resolvedCornerRadius(
            base: effectiveTileSize * 0.225,
            maximum: maximumCornerRadius
        )
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
