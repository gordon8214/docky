import AppKit
import OSLog

extension DockTileInteraction {
    var tooltipTitle: String? {
        switch tile.content {
        case .app(let app):
            app.displayName
        case .minimizedWindow(let window):
            window.windowTitle
        case .appFolder(let folder):
            folder.displayName
        case .launchpad(let launchpad):
            launchpad.title
        case .startMenu(let menu):
            menu.title
        case .widget(let widget):
            widget.title
        case .smartStack(let stack):
            stack.title
        case .folder(let folder):
            folder.displayName
        case .trash:
            "Trash"
        case .spacer, .flexibleSpacer, .divider:
            nil
        }
    }

    func updateHoverState(isHovering newValue: Bool) {
        guard expandableWidget != nil else {
            applyHoverState(newValue)
            return
        }

        if newValue {
            applyHoverState(true)
            return
        }

        applyHoverState(false)
    }

    func applyHoverState(_ isHovering: Bool) {
        self.isHovering = isHovering
        updateTooltipPresentation()
        updateWindowPreviewPresentation(isHovering: isHovering)
    }

    /// Hover-dwell trigger for the per-tile window preview window. Mirrors
    /// the widget expansion contract: present after a delay on hover-in,
    /// requestDismiss on hover-out (with a short grace so the cursor can
    /// transition into the preview window without dropping it). Both `.app`
    /// and `.appFolder` tiles participate, the app-folder case aggregates
    /// windows from every contained app.
    func updateWindowPreviewPresentation(isHovering: Bool) {
        // Freeze preview state while a context menu is open on this tile ,
        // the menu's mouse handling can drop us out of hover and prematurely
        // dismiss, or restart the dwell once the user moves off. The
        // preview's own hover monitor still keeps it alive if the cursor is
        // over it; we just don't react from the tile side.
        if isContextMenuPresented { return }

        windowPreviewDelayTask?.cancel()
        windowPreviewDelayTask = nil

        let bundleIDs = windowPreviewBundleIdentifiers
        guard !bundleIDs.isEmpty,
            !editMode.isActive,
            !isAppFolderPopoverPresented,
            !isAppFolderListMenuPresented
        else {
            WindowPreviewWindowController.shared.requestDismiss(sourceTileID: tile.id)
            return
        }

        if !isHovering {
            WindowPreviewWindowController.shared.requestDismiss(sourceTileID: tile.id)
            return
        }

        let workspace = WorkspaceService.shared
        let hasAnyWindow = bundleIDs.contains { id in
            !workspace.appWindows(bundleIdentifier: id).isEmpty
        }
        guard hasAnyWindow else {
            WindowPreviewWindowController.shared.requestDismiss(sourceTileID: tile.id)
            return
        }

        let delay = max(0, preferences.windowPreviewHoverDelay)
        windowPreviewDelayTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, self.isHovering else { return }
            WindowPreviewWindowController.shared.present(
                forBundleIdentifiers: bundleIDs,
                sourceTileID: tile.id,
                sourceFrame: globalTileFrame,
                preferredEdge: inwardPopoverEdge
            )
        }
    }

    /// Bundle identifiers whose windows should be merged into the hover
    /// preview for this tile. `.app` returns its single bundle; `.appFolder`
    /// returns every contained app's bundle.
    var windowPreviewBundleIdentifiers: [String] {
        switch tile.content {
        case .app(let app) where app.displayedWidget == nil:
            return app.bundleIdentifier.isEmpty ? [] : [app.bundleIdentifier]
        case .appFolder(let folder):
            return folder.apps
                .map(\.bundleIdentifier)
                .filter { !$0.isEmpty }
        default:
            return []
        }
    }

    var expandableWidget: WidgetTile? {
        let candidate: WidgetTile?
        switch tile.content {
        case .widget(let widget):
            candidate = widget
        case .app(let app) where app.displayedWidget != nil:
            candidate = app.displayedWidget
        default:
            candidate = nil
        }
        guard let candidate, candidate.kind.isExpandable else { return nil }
        return candidate
    }

    var expandableWidgetRenderedSpan: TileSpan {
        switch tile.content {
        case .widget(let widget):
            return renderedWidgetSpan(for: widget.effectiveSpan)
        case .app(let app):
            return renderedWidgetSpan(for: app.displayedWidget?.effectiveSpan ?? .one)
        default:
            return .one
        }
    }

    func updateWidgetExpansionPresentation(isHovering: Bool, sourceFrame: CGRect) {
        widgetExpansionTask?.cancel()
        widgetExpansionTask = nil

        guard preferences.enablesWidgetHoverPreview,
            preferences.widgetHoverPreviewSpans.contains(expandableWidgetRenderedSpan),
            isHovering,
            let widget = expandableWidget,
            !isContextMenuPresented,
            !editMode.isActive
        else {
            WidgetExpansionWindowController.shared.requestDismiss(sourceTileID: tile.id)
            return
        }

        widgetExpansionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(max(0, preferences.widgetHoverPreviewDelay)))
            guard !Task.isCancelled else { return }
            guard self.isHovering, !self.isContextMenuPresented, !self.editMode.isActive else { return }
            WidgetExpansionWindowController.shared.present(
                widget: widget,
                sourceTileID: tile.id,
                sourceFrame: sourceFrame,
                cornerRadius: nonAppTileCornerRadius,
                renderedSpan: expandableWidgetRenderedSpan
            )
        }
    }

    func updateContextMenuPresentation(isPresented: Bool) {
        isContextMenuPresented = isPresented
        updateTooltipPresentation()

        if isPresented {
            // Cancel any in-flight preview dwell and dismiss whatever is
            // already on screen, the context menu takes over input and
            // the preview shouldn't sit underneath it.
            windowPreviewDelayTask?.cancel()
            windowPreviewDelayTask = nil
            WindowPreviewWindowController.shared.dismiss(sourceTileID: tile.id)

            if expandableWidget != nil {
                widgetExpansionTask?.cancel()
                widgetExpansionTask = nil
                WidgetExpansionWindowController.shared.dismiss(sourceTileID: tile.id)
            }
        }
    }

    func updateTooltipPresentation() {
        tooltipDelayTask?.cancel()
        tooltipDelayTask = nil

        let shouldShow =
            isHovering
            && tooltipTitle != nil
            && !isFolderPopoverPresented
            && !isFolderListMenuPresented
            && !isAppFolderPopoverPresented
            && !isAppFolderListMenuPresented
            && !isContextMenuPresented
            && windowPreview.activeSourceTileID != tile.id

        guard shouldShow else {
            isTooltipPresented = false
            return
        }

        isTooltipPresented = true
    }

    var tileContentKindDescription: String {
        switch tile.content {
        case .app: return "app"
        case .minimizedWindow: return "minimizedWindow"
        case .appFolder: return "appFolder"
        case .folder: return "folder"
        case .launchpad: return "launchpad"
        case .startMenu: return "startMenu"
        case .widget: return "widget"
        case .smartStack: return "smartStack"
        case .trash: return "trash"
        case .spacer: return "spacer"
        case .flexibleSpacer: return "flexibleSpacer"
        case .divider: return "divider"
        }
    }

    func handleTap() {
        windowPreviewDelayTask?.cancel()
        windowPreviewDelayTask = nil
        WindowPreviewWindowController.shared.dismiss(sourceTileID: tile.id)
        dismissOtherStartMenu()
        isTooltipPresented = false
        switch tile.content {
        case .app(let app): tapApp(app)
        case .minimizedWindow(let window): _ = WorkspaceService.shared.restoreMinimizedWindow(window)
        case .appFolder(let folder): tapAppFolder(folder)
        case .launchpad: toggleLaunchpad()
        case .startMenu: toggleStartMenu()
        case .widget(let widget): handleWidgetTap(widget)
        case .folder(let folder): tapFolder(folder)
        case .trash: Task { _ = await AppleScriptService.shared.openTrash() }
        case .smartStack, .spacer, .flexibleSpacer, .divider: return
        }
    }
    func dismissOtherStartMenu() {
        guard StartMenuService.shared.isPresented else { return }
        switch tile.content {
        case .startMenu: return
        case .app(let app)
        where app.bundleIdentifier == "com.apple.finder"
            && preferences.opensStartMenuFromFinderTile && preferences.enablesStartMenuOverlay:
            return
        default: StartMenuService.shared.dismiss()
        }
    }
    func tapApp(_ app: AppTile) {
        if app.bundleIdentifier == "com.apple.finder", preferences.opensStartMenuFromFinderTile,
            preferences.enablesStartMenuOverlay {
            StartMenuService.shared.toggle()
        } else {
            WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
        }
    }
    func tapAppFolder(_ folder: AppFolderTile) {
        if appFolderContentViewMode == .inline {
            isAppFolderPopoverPresented = false
            isAppFolderListMenuPresented = false
            TileStore.shared.toggleInlineAppFolderExpansion(folderID: folder.identifier)
        } else if appFolderContentViewMode == .list {
            isAppFolderPopoverPresented = false
            isAppFolderListMenuPresented = true
        } else {
            isAppFolderPopoverPresented.toggle()
        }
    }
    func toggleLaunchpad() { if preferences.enablesLaunchpadOverlay { LaunchpadOverlayService.shared.toggle() } }
    func toggleStartMenu() { if preferences.enablesStartMenuOverlay { StartMenuService.shared.toggle() } }
    func tapFolder(_ folder: FolderTile) {
        if folderContentViewMode == .finder {
            isFolderPopoverPresented = false
            Task { _ = await AppleScriptService.shared.openFinderWindow(for: folder.url) }
            return
        }
        if folderContentViewMode == .list {
            isFolderPopoverPresented = false
            isFolderListMenuPresented = true
            return
        }
        if isFolderPopoverPresented {
            if folderContentViewMode != .fan { isFolderPopoverPresented = false }
            return
        }
        guard Date.timeIntervalSinceReferenceDate - lastFolderPopoverDismissedAt > Self.folderPopoverRetapGuardInterval
        else { return }
        folderSnapshot = FolderAccessService.shared.snapshot(of: folder.url)
        isFolderPopoverPresented = true
    }

    /// Children for the "View Content as" submenu on a folder tile.
    /// Always shows Grid and List; only shows Fan when the dock is at
    /// the bottom edge, since Fan rendering is hard-coded to sweep
    /// upward from the tile and only works visually for `.bottom`.
}
