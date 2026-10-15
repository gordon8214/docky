#if DEBUG
    import AppKit
    import QuartzCore

    extension AppKitUIRegression {
        static func checkWindowsReviewRegressions() async {
            checkWindowsSavedContent()
            checkWindowsEmptyDropRegion()
            let root = DockRootView(frame: CGRect(x: 0, y: 0, width: 1000, height: 48))
            let window = NSWindow(contentRect: root.frame, styleMask: .borderless,
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = root
            root.layoutSubtreeIfNeeded()
            defer {
                root.canvas.clearWindowsTaskbar()
                window.contentView = nil
                window.close()
            }
            await checkWindowsMenuNavigation(anchor: root)
            checkWindowsPopupOverflow(anchor: root)
            checkWindowsBackgroundMenu(root: root)
            checkWindowsLayoutCleanup(root: root)
            await checkWindowsPresentationVisibility()
            await checkWindowsPreviewKeyboard()
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
                    apps: [AppTile(bundleIdentifier: "com.apple.finder", displayName: "Finder")])))
            ]
            let extras = DockCanvasView.windowsExtraTiles(from: tiles)
            precondition(extras == [tiles[1], tiles[3]], "Saved battery widgets must remain in additional Dock items")
            let overflow = NativeDockTileView(tile: tiles[3])
            overflow.frame = CGRect(x: 0, y: 0, width: 84, height: 60)
            overflow.refresh()
            overflow.layoutSubtreeIfNeeded()
            precondition(overflow.windowsIndicator.isHidden)
            precondition(abs(overflow.indicator.frame.midX - overflow.imageView.frame.midX) < 0.001)
        }
        private static func checkWindowsEmptyDropRegion() {
            let controller = DockCanvasController()
            controller.tileFrames = ["windows:start": CGRect(x: 100, y: 4, width: 40, height: 40)]
            controller.visibleTileFrames = controller.tileFrames
            precondition(controller.isPointInPinnedDropRegion(120))
            controller.updateExternalAppDrop(at: CGPoint(x: 120, y: 20))
            precondition(controller.dockDrag.destinationIndex == 0)
            precondition(controller.dockDrag.destinationSection == .pinned)
            controller.dockDrag.clear()
        }
        private static func checkWindowsMenuNavigation(anchor: NSView) async {
            var invoked = 0
            let menu = WindowsMenuContent(actions: [
                .action("Close", isDestructive: true) {},
                .submenu("Submenu", children: [.action("Child") {}]), .action("Other") {}
            ])
            menu.onAction = { _, _ in invoked += 1 }
            menu.select(0)
            menu.keyDown(with: windowsKey(124))
            precondition(invoked == 0, "Right Arrow must not activate a leaf action")
            menu.keyDown(with: windowsKey(36))
            precondition(invoked == 1)
            menu.select(1)
            menu.keyDown(with: windowsKey(124))
            precondition(invoked == 2, "Right Arrow must open submenus")
            guard let row = menu.subviews.compactMap({ $0 as? WindowsMenuRow }).dropFirst().first else {
                preconditionFailure("Submenu row required")
            }
            row.mouseEntered(with: windowsKey(0))
            menu.keyDown(with: windowsKey(125))
            row.mouseExited(with: windowsKey(0))
            try? await Task.sleep(for: .milliseconds(350))
            precondition(invoked == 2, "Canceled hover must not open a stale submenu")
            let popup = WindowsTaskbarPopup(content: menu, size: menu.desiredSize)
            popup.present(from: anchor)
            precondition(popup.panel.firstResponder === menu)
            menu.select(0)
            popup.panel.sendEvent(windowsKey(124, window: popup.panel))
            precondition(invoked == 2, "Responder delivery must preserve safe arrow behavior")
            popup.dismiss()
        }
        private static func checkWindowsPopupOverflow(anchor: NSView) {
            let preview = FilePreviewMenuItemView(url: URL(fileURLWithPath: "/tmp/docky-review.txt"))
            let menu = WindowsMenuContent(actions: [.customView(preview)] + (0..<120).map { index in
                .action("Window \(index)") {}
            })
            precondition(menu.desiredSize.width >= preview.frame.width + 16)
            let popup = WindowsTaskbarPopup(content: menu, size: menu.desiredSize)
            popup.present(from: anchor)
            popup.panel.contentView?.layoutSubtreeIfNeeded()
            let visible = anchor.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            precondition(popup.panel.frame.height <= visible.height)
            menu.select(119)
            guard let last = menu.subviews.last else { preconditionFailure("Last menu row required") }
            precondition(!last.visibleRect.isEmpty, "Keyboard must reach the last oversized-menu row")
            popup.dismiss()
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
            let hit = root.hitTest(CGPoint(x: 10, y: 10))
            var titles: [String] = []
            let oldPresenter = ContextActionMenuPresenter.customPresenter
            defer { ContextActionMenuPresenter.customPresenter = oldPresenter }
            ContextActionMenuPresenter.customPresenter = { actions, _, _ in
                titles = actions.map(\.title)
                return true
            }
            hit?.rightMouseDown(with: windowsKey(0))
            precondition(titles.contains("Taskbar Settings"), "Blank canvas clicks must reach the background menu")
        }
        private static func checkWindowsLayoutCleanup(root: DockRootView) {
            let backdrop = NSView()
            root.canvas.addSubview(backdrop)
            root.canvas.groupBackdrops["old-theme"] = backdrop
            root.canvas.layoutWindowsTaskbar()
            precondition(root.canvas.groupBackdrops.isEmpty && backdrop.superview == nil)
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
            canvas.configureSectionHost(document, id: "fixture", frame: canvas.bounds,
                                        scrolling: true, vertical: false)
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
        private static func checkWindowsPreviewKeyboard() async {
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
            controller.configurePresenterStyle()
            panel.orderFront(nil)
            precondition(!panel.isKeyWindow, "Hover presentation must remain passive")
            controller.focusForKeyboardInteraction()
            precondition(panel.firstResponder === content && panel.isKeyWindow)
            panel.sendEvent(windowsKey(124, window: panel))
            precondition(delivered == 1, "Preview keys must travel through the window responder chain")
            ThemeManager.shared.clearActive()
            let deadline = ContinuousClock.now.advanced(by: .seconds(1))
            while panel.isVisible {
                precondition(ContinuousClock.now < deadline, "Theme switching must dismiss the old preview")
                await Task.yield()
            }
            ThemeManager.shared.setActive("windows")
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
#endif
