#if DEBUG
    import AppKit
    import QuartzCore

    extension AppKitUIRegression {
        static func checkWindowsReviewRegressions() async {
            checkWindowsSavedContent()
            checkWindowsEmptyDropRegion()
            checkWindowsTrayFolderDrop()
            let root = DockRootView(frame: CGRect(x: 0, y: 0, width: 1000, height: 48))
            let window = WindowsReviewWindow(contentRect: root.frame, styleMask: .borderless,
                                             backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = root
            root.layoutSubtreeIfNeeded()
            defer {
                root.canvas.clearWindowsTaskbar()
                window.contentView = nil
                window.close()
            }
            checkWindowsPopupOverflow(anchor: root)
            checkWindowsBackgroundMenu(root: root)
            checkWindowsLayoutCleanup(root: root)
            await checkWindowsPresentationVisibility()
            checkWindowsPreviewKeyboard()
        }
        private static func checkWindowsSavedContent() {
            var battery = WidgetCatalog.batteries.makeTile()
            battery.settings = ["fixture": .string("saved battery")]
            var calendar = WidgetCatalog.calendar.makeTile()
            calendar.settings = ["fixture": .string("saved calendar")]
            let tiles = [
                Tile(id: "date", content: .widget(WidgetCatalog.calendarDate.makeTile())),
                Tile(id: "battery", content: .widget(battery)),
                Tile(id: "calendar", content: .widget(calendar)),
                Tile(id: "folder", content: .appFolder(AppFolderTile(
                    identifier: "folder", displayName: "Folder",
                    apps: [AppTile(bundleIdentifier: "com.apple.finder", displayName: "Finder")]))),
                Tile(id: "trash", content: .trash)
            ]
            let extras = DockCanvasView.windowsExtraTiles(from: tiles)
            precondition(
                extras == [tiles[1], tiles[3]],
                "Saved battery widgets stay in the overflow popup, and Trash has its own tray button")
            let overflow = NativeDockTileView(tile: tiles[3])
            overflow.frame = CGRect(x: 0, y: 0, width: 84, height: 60)
            overflow.refresh()
            overflow.layoutSubtreeIfNeeded()
            precondition(overflow.windowsIndicator.isHidden)
            precondition(abs(overflow.indicator.frame.midX - overflow.imageView.frame.midX) < 0.001)
            precondition(
                overflow.indicator.layer?.backgroundColor == WindowsTaskbarStyle.Tray.indicatorColor.cgColor,
                "Tray tiles keep the accent underline")
            precondition(
                overflow.interaction.appliedTileIconPadding == WindowsTaskbarStyle.Tray.iconPadding
                    && overflow.interaction.contentPadding == WindowsTaskbarStyle.Tray.verticalPadding)
            let wide = NativeDockTileView(tile: Tile(
                id: "wide", content: .widget(WidgetCatalog.batteries.makeTile(span: .two))))
            precondition(
                wide.interaction.nonAppContentPadding == 0 && wide.interaction.appliedTileIconPadding == 0
                    && wide.interaction.nonAppTileCornerRadius == 0,
                "Wide tray widgets fill their tile")
        }
        private static func checkWindowsEmptyDropRegion() {
            let controller = DockCanvasController()
            // A taskbar with only Start. The shared store holds this Mac's pinned apps, which have
            // no frames here, so the drop would land after them instead of at the front.
            controller.store = TileStore.makeEmptyForTesting()
            controller.tileFrames = ["windows:start": CGRect(x: 100, y: 4, width: 40, height: 40)]
            controller.visibleTileFrames = controller.tileFrames
            precondition(controller.isPointInPinnedDropRegion(120))
            controller.updateExternalAppDrop(at: CGPoint(x: 120, y: 20))
            precondition(controller.dockDrag.destinationIndex == 0)
            precondition(controller.dockDrag.destinationSection == .pinned)
            controller.dockDrag.clear()
        }
        private static func checkWindowsTrayFolderDrop() {
            let controller = DockCanvasController()
            controller.store = TileStore.makeEmptyForTesting()
            controller.tileFrames = ["windows:start": CGRect(x: 100, y: 4, width: 40, height: 40)]
            controller.visibleTileFrames = controller.tileFrames
            controller.trayFrame = CGRect(x: 800, y: 0, width: 200, height: 48)
            defer { controller.dockDrag.clear() }
            controller.updateExternalFolderDrop(at: CGPoint(x: 400, y: 20))
            precondition(controller.dockDrag.destinationIndex == nil, "Folders don't drop among the app buttons")
            controller.updateExternalFolderDrop(at: CGPoint(x: 900, y: 20))
            precondition(
                controller.dockDrag.destinationSection == .trailing && controller.dockDrag.destinationIndex == 0
                    && controller.isTrayDropTarget,
                "A folder dropped on the tray joins the trailing items")
        }
        private static func checkWindowsPopupOverflow(anchor: NSView) {
            let visible = anchor.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            let extras = WindowsTaskbarExtraContent(tiles: (0..<120).map {
                Tile(id: "extra:\($0)", content: .spacer)
            })
            let overflow = WindowsTaskbarPopup(content: extras, size: extras.desiredSize)
            overflow.present(from: anchor)
            overflow.panel.contentView?.layoutSubtreeIfNeeded()
            precondition(overflow.panel.frame.height <= visible.height)
            guard let final = extras.subviews.last else { preconditionFailure("Last extra tile required") }
            overflow.panel.sendEvent(windowsKey(119, window: overflow.panel))
            precondition(!final.visibleRect.isEmpty, "The last overflow tile must remain reachable")
            overflow.dismiss()
        }
        private static func checkWindowsBackgroundMenu(root: DockRootView) {
            guard let window = root.window as? WindowsReviewWindow,
                let chrome = root.subviews.first(where: { $0 is DockChromeView }) else {
                preconditionFailure("Taskbar window and chrome required")
            }
            // The root fills the window, so one point serves the hit test and the event.
            let point = CGPoint(x: 10, y: 10)
            guard let click = NSEvent.mouseEvent(
                with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else {
                preconditionFailure("Right-click fixture required")
            }
            let prefs = DockyPreferences.shared
            let hidesWindow = prefs.autohidesWindow
            let held = window.interactionTokens.count
            var items: [NSMenuItem] = []
            var anchor = CGRect.null
            var anchorView: NSView?
            defer { ContextActionMenuPresenter.testInterceptor = nil }
            ContextActionMenuPresenter.testInterceptor = { menu, rect, view in
                precondition(window.interactionTokens.count == held + 1, "An open menu must hold the taskbar")
                items = menu.items
                anchor = rect
                anchorView = view
            }
            root.hitTest(point)?.rightMouseDown(with: click)
            let titles = items.map(\.title)
            precondition(
                titles.contains(String(localized: "Settings...")),
                "Blank canvas clicks must reach the native background menu")
            let hidingTitle = hidesWindow ? String(localized: "Turn Hiding Off") : String(localized: "Turn Hiding On")
            guard let hiding = items.first(where: { $0.title == hidingTitle }) else {
                preconditionFailure("The menu's hiding item must match the current hiding setting")
            }
            precondition(titles.contains(String(localized: "Edit Taskbar...")), "The menu must enter edit mode")
            precondition(
                items.first { $0.title == String(localized: "Troubleshoot") }?.submenu?.items.map(\.title)
                    == [String(localized: "Sync Dock")],
                "Troubleshoot must offer Sync Dock")
            // About and a red Quit end the menu, set apart by a divider.
            guard let quit = items.last, items.count >= 3 else { preconditionFailure("Background menu items required") }
            precondition(
                quit.title == String(localized: "Quit Docky")
                    && (quit.representedObject as? ContextAction)?.isDestructive == true
                    && items[items.count - 2].title == String(localized: "About Docky")
                    && items[items.count - 3].isSeparatorItem,
                "The background menu must end with About Docky and Quit Docky below a divider")
            precondition(
                anchorView === chrome && abs(anchor.minX - chrome.convert(point, from: nil).x) < 0.001
                    && anchor.height == chrome.bounds.height,
                "The background menu must open at the pointer")
            precondition(window.interactionTokens.count == held, "Closing a menu must release the taskbar hold")
            // Toggle and restore before asserting, so a failure can't leave the real setting flipped.
            (hiding.representedObject as? ContextAction)?.handler()
            let toggled = prefs.autohidesWindow
            prefs.autohidesWindow = hidesWindow
            precondition(toggled != hidesWindow, "The hiding item must toggle hiding")
        }
        private static func checkWindowsLayoutCleanup(root: DockRootView) {
            root.canvas.layoutWindowsTaskbar()
            checkWindowsRemovalGhost(canvas: root.canvas)
            guard let tile = root.canvas.tiles.values.first else { preconditionFailure("Taskbar tile required") }
            let motion = CABasicAnimation(keyPath: "position")
            motion.duration = 10
            tile.layer?.add(motion, forKey: "taskbar-position")
            tile.layer?.add(motion, forKey: "unrelated-motion")
            root.canvas.clearWindowsTaskbar()
            precondition(tile.layer?.animation(forKey: "taskbar-position") == nil)
            precondition(tile.layer?.animation(forKey: "unrelated-motion") != nil)
        }
        private static func checkWindowsRemovalGhost(canvas: DockCanvasView) {
            guard !WindowsTaskbarStyle.reducesMotion,
                let document = canvas.sectionViews["windows-apps"] else { return }
            let fixture = Tile(id: "windows:removed", content: .app(
                AppTile(bundleIdentifier: "com.apple.finder", displayName: "Finder")))
            let tile = canvas.view(for: fixture)
            document.addSubview(tile)
            tile.frame = CGRect(x: 2, y: 4, width: 40, height: 40)
            tile.layoutSubtreeIfNeeded()
            let icon = canvas.convert(tile.imageView.frame, from: tile)
            canvas.windowsTileIDs.append(fixture.id)
            canvas.layoutWindowsTaskbar()
            guard let ghost = canvas.subviews.compactMap({ $0 as? NSImageView }).last else {
                preconditionFailure("Removal ghost required")
            }
            precondition(ghost.frame == icon && ghost.frame.size == CGSize(width: 24, height: 24))
        }
        private static func checkWindowsPresentationVisibility() async {
            let canvas = DockCanvasView(frame: CGRect(x: 0, y: 0, width: 200, height: 48))
            canvas.isLayingOut = true // Keep the fixture hierarchy independent of the saved layout.
            let window = NSWindow(contentRect: canvas.frame, styleMask: .borderless,
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = canvas
            let document = WindowsTaskbarDocumentView(frame: CGRect(x: 0, y: 0, width: 500, height: 48))
            document.wantsLayer = true
            canvas.configureSectionHost(document, id: "fixture", frame: canvas.bounds, vertical: false)
            let tile = canvas.view(for: Tile(id: "fixture", content: .app(
                AppTile(bundleIdentifier: "com.apple.finder", displayName: "Finder"))))
            document.addSubview(tile)
            tile.frame = CGRect(x: 0, y: 4, width: 40, height: 40)
            window.orderFront(nil)
            CATransaction.flush()
            tile.frame.origin.x = 400
            let motion = CABasicAnimation(keyPath: "position")
            motion.isAdditive = true
            motion.fromValue = NSValue(point: CGPoint(x: -400, y: 0))
            motion.toValue = NSValue(point: .zero)
            motion.duration = 2
            tile.layer?.add(motion, forKey: "fixture-motion")
            CATransaction.flush()
            let deadline = ContinuousClock.now.advanced(by: .seconds(1))
            while tile.layer?.presentation() == nil {
                precondition(ContinuousClock.now < deadline, "Presentation layer must become available")
                await Task.yield()
            }
            precondition(tile.visibleRect.isEmpty, "Destination must lie outside the viewport")
            canvas.refreshFrames(force: true)
            precondition(canvas.controller.visibleTileFrames[tile.interaction.tile.id]?.isEmpty == false,
                         "Visible presentation geometry must remain interactive despite an offscreen destination")
            window.contentView = nil
            window.close()
        }
        private static func checkWindowsPreviewKeyboard() {
            let controller = WindowPreviewWindowController.shared
            guard let panel = controller.window as? WindowsTaskbarPanel else {
                preconditionFailure("Preview must use a nonactivating key-capable panel")
            }
            let content = WindowsPreviewContent(frame: CGRect(x: 0, y: 0, width: 220, height: 180))
            var delivered = 0
            content.onKey = { _ in delivered += 1 }
            let viewController = NSViewController()
            viewController.view = content
            panel.contentViewController = viewController
            panel.setContentSize(content.frame.size)
            panel.orderFront(nil)
            precondition(!panel.isKeyWindow, "Hover presentation must remain passive")
            controller.focusForKeyboardInteraction()
            precondition(panel.firstResponder === content && panel.isKeyWindow)
            panel.sendEvent(windowsKey(124, window: panel))
            precondition(delivered == 1, "Preview keys must travel through the window responder chain")
            controller.dismissImmediately()
            precondition(!panel.isVisible && !panel.isKeyWindow, "Dismissing must close the preview")
            panel.contentViewController = nil
        }
        private static func windowsKey(_ code: UInt16, window: NSWindow? = nil) -> NSEvent {
            guard let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window?.windowNumber ?? 0, context: nil, characters: "",
                charactersIgnoringModifiers: "", isARepeat: false, keyCode: code) else {
                preconditionFailure("Keyboard fixture required")
            }
            return event
        }
    }

    /// Counts taskbar visibility holds so menu checks can prove each hold is released.
    private final class WindowsReviewWindow: NSWindow, DockWindowInteractionHolding {
        private(set) var interactionTokens: Set<UUID> = []
        func beginInteraction() -> UUID? {
            let token = UUID()
            interactionTokens.insert(token)
            return token
        }
        func endInteraction(_ token: UUID?) {
            if let token { interactionTokens.remove(token) }
        }
    }
#endif
