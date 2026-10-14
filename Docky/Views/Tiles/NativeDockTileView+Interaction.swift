import AppKit

extension NativeDockTileView {
    func nativeUpdateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        guard !isDragPreview else { return }
        tracking = NSTrackingArea(
            rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self)
        if let tracking { addTrackingArea(tracking) }
    }
    func nativeMouseEntered(with event: NSEvent) { hover(true) }
    func nativeMouseExited(with event: NSEvent) { hover(false) }
    func hover(_ value: Bool) {
        interaction.updateHoverState(isHovering: value)
        TilePressService.shared.registerHover(tileID: interaction.tile.id, isHovering: value)
        interaction.updateWidgetExpansionPresentation(isHovering: value, sourceFrame: interaction.globalTileFrame)
        refresh()
    }
    func nativeMouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
            return
        }
        mouseDownPoint = canvas?.convert(event.locationInWindow, from: nil)
        wasDragging = false
        canceledMouseSession = false
    }
    func nativeMouseDragged(with event: NSEvent) {
        guard let canvas, let start = mouseDownPoint, canvas.controller.isTileDraggable(interaction.tile) else {
            return
        }
        let location = canvas.convert(event.locationInWindow, from: nil)
        let translation = CGSize(width: location.x - start.x, height: location.y - start.y)
        guard wasDragging || hypot(translation.width, translation.height) >= 4 else { return }
        if !wasDragging {
            dragWindow = window as? MainWindow
            dragInteractionToken = dragWindow?.beginInteraction()
            dragWindow?.makeFirstResponder(canvas)
            dragWindow?.setSearchFocus(true)
        }
        wasDragging = true
        canvas.dragTranslation = translation
        canvas.controller.updateDrag(
            for: interaction.tile, value: DockPointerDrag(location: location, translation: translation))
    }
    func nativeMouseUp(with event: NSEvent) {
        if canceledMouseSession {
            canceledMouseSession = false
            return
        }
        defer {
            mouseDownPoint = nil
            wasDragging = false
        }
        if wasDragging, let canvas, let start = mouseDownPoint {
            let location = canvas.convert(event.locationInWindow, from: nil)
            canvas.controller.endDrag(
                for: interaction.tile,
                value: DockPointerDrag(
                    location: location, translation: CGSize(width: location.x - start.x, height: location.y - start.y)))
            dragWindow?.setSearchFocus(false)
            dragWindow?.endInteraction(dragInteractionToken)
            dragWindow = nil
        } else if bounds.contains(convert(event.locationInWindow, from: nil)) {
            activate()
        }
    }
    func nativeRightMouseDown(with event: NSEvent) {
        ContextActionMenuPresenter.popUpMenu(
            actions: interaction.contextActions(modifierFlags: event.modifierFlags), from: self,
            preferredEdge: interaction.inwardMenuEdge,
            onPresentationChanged: { [weak self] value in
                self?.interaction.updateContextMenuPresentation(isPresented: value)
            })
    }
    func showAccessibilityMenu() -> Bool {
        ContextActionMenuPresenter.popUpMenu(
            actions: interaction.contextActions(modifierFlags: []), from: self,
            preferredEdge: interaction.inwardMenuEdge,
            onPresentationChanged: { [weak self] in
                self?.interaction.updateContextMenuPresentation(isPresented: $0)
            })
        return true
    }
    func performTilePress() -> Bool {
        activate()
        return true
    }
    func nativeKeyDown(with event: NSEvent) {
        if let stack = content as? NativeSmartStackView, [123, 124, 125, 126].contains(event.keyCode) {
            stack.cycle(event.keyCode == 123 || event.keyCode == 126 ? -1 : 1)
            return
        }
        if event.keyCode == 36 || event.keyCode == 49 { activate() } else { super.keyDown(with: event) }
    }
    func activate() {
        if let stack = content as? NativeSmartStackView {
            stack.activateSelected()
            return
        }
        interaction.handleTap()
        if interaction.isFolderListMenuPresented || interaction.isAppFolderListMenuPresented {
            showFolderMenu()
        } else if interaction.isFolderPopoverPresented || interaction.isAppFolderPopoverPresented {
            showFolderPopover()
        } else {
            folderPopover?.close()
        }
    }

    func showFolderMenu() {
        let actions: [ContextAction]
        switch interaction.tile.content {
        case .folder(let folder): actions = folderNavigationContextActions(for: folder.url)
        case .appFolder(let folder):
            actions = folder.apps.map { app in
                .action(app.displayName) {
                    WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
                }
            }
        default: actions = []
        }
        ContextActionMenuPresenter.popUpMenu(actions: actions, from: self, preferredEdge: interaction.inwardMenuEdge)
        interaction.isFolderListMenuPresented = false
        interaction.isAppFolderListMenuPresented = false
    }
    func showFolderPopover() {
        if let fan {
            fan.dismiss()
            return
        }
        if presentFolderFanIfNeeded() { return }

        if let existing = folderPopover, existing.isShown {
            existing.close()
            return
        }
        let folder: FolderTile?
        let appFolder: AppFolderTile?
        switch interaction.tile.content {
        case .folder(let value):
            folder = FolderTile(
                url: value.url, displayName: value.displayName, displayMode: interaction.folderDisplayMode,
                contentViewMode: interaction.folderContentViewMode, sortMode: interaction.folderSortMode)
            appFolder = nil
        case .appFolder(let value):
            folder = nil
            appFolder = value
        default: return
        }
        let browser = NativeFolderController(folder: folder, appFolder: appFolder, tileID: interaction.tile.id)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        if !holdsFolderInteraction {
            heldFolderWindow = window as? MainWindow
            folderInteractionToken = heldFolderWindow?.beginInteraction()
            holdsFolderInteraction = true
        }
        popover.contentViewController = browser
        popover.contentSize = CGSize(width: 540, height: 420)
        browser.onClose = { [weak self, weak popover] in
            popover?.close()
            self?.interaction.isFolderPopoverPresented = false
            self?.interaction.isAppFolderPopoverPresented = false
            self?.interaction.lastFolderPopoverDismissedAt = Date.timeIntervalSinceReferenceDate
        }
        folderPopover = popover
        popover.show(relativeTo: bounds, of: self, preferredEdge: interaction.inwardPopoverEdge)
    }

    func presentFolderFanIfNeeded() -> Bool {
        if case .folder(let folder) = interaction.tile.content,
            interaction.folderContentViewMode == .fan, interaction.position == .bottom {
            let items = FolderAccessService.shared.sortedItems(
                in: FolderAccessService.shared.snapshot(of: folder.url), sortMode: interaction.folderSortMode)
            if !items.isEmpty && items.count <= 10 {
                let fan = NativeFolderFanController(
                    anchor: self, items: items, iconSize: interaction.effectiveTileSize * 0.82)
                fan.onClose = { [weak self] in
                    self?.fan = nil
                    self?.popoverDidClose(Notification(name: NSPopover.didCloseNotification))
                }
                self.fan = fan
                if !holdsFolderInteraction {
                    heldFolderWindow = window as? MainWindow
                    folderInteractionToken = heldFolderWindow?.beginInteraction()
                    holdsFolderInteraction = true
                }
                fan.present()
                return true
            }
        }

        return false
    }

    func cancelDrag() {
        if mouseDownPoint != nil { canceledMouseSession = true }
        if wasDragging {
            dragWindow?.setSearchFocus(false)
            dragWindow?.endInteraction(dragInteractionToken)
            dragWindow = nil
        }
        wasDragging = false
        mouseDownPoint = nil
    }
    func popoverDidClose(_ notification: Notification) {
        interaction.isFolderPopoverPresented = false
        interaction.isAppFolderPopoverPresented = false
        interaction.lastFolderPopoverDismissedAt = Date.timeIntervalSinceReferenceDate
        if holdsFolderInteraction {
            heldFolderWindow?.endInteraction(folderInteractionToken)
            heldFolderWindow = nil
            holdsFolderInteraction = false
        }
        folderPopover = nil
    }
    func dismissTransientPresentation() {
    folderPreviewTask?.cancel()
    folderPreviewTask = nil
    folderPreviewNeedsRefresh = true
    cancelDrag()
    if holdsFolderInteraction {
        heldFolderWindow?.endInteraction(folderInteractionToken)
        heldFolderWindow = nil
        holdsFolderInteraction = false
    }
    fan?.dismiss()
    folderPopover?.close()
    interaction.widgetExpansionTask?.cancel()
    interaction.windowPreviewDelayTask?.cancel()
    TilePressService.shared.clearHover(tileID: interaction.tile.id)
    WindowPreviewWindowController.shared.dismiss(sourceTileID: interaction.tile.id)
    WidgetExpansionWindowController.shared.dismiss(sourceTileID: interaction.tile.id)
    }

    func nativeViewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil && canvas?.isUpdatingHierarchy == true { return }
        if let watchedFolder {
            FolderAccessService.shared.endWatching(watchedFolder, ownerID: folderWatcherID)
            self.watchedFolder = nil
        }
        if window != nil, !isDragPreview, case .folder(let folder) = interaction.tile.content {
            watchedFolder = folder.url
            FolderAccessService.shared.beginWatching(folder.url, ownerID: folderWatcherID)
        }
        if window == nil {
            dismissTransientPresentation()
        } else {
            refresh()
        }
    }
}
