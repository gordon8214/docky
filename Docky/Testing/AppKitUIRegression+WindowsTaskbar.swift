#if DEBUG
    import AppKit
    import QuartzCore

    extension AppKitUIRegression {
        static func checkWindowsTaskbar() async {
            let prefs = DockyPreferences.shared
            let settings = DockSettingsService.shared
            let oldTaskbarHeight = prefs.windowsTaskbarHeight
            defer { prefs.windowsTaskbarHeight = oldTaskbarHeight }
            // The suite runs against the real defaults, so start from the standard size.
            prefs.windowsTaskbarHeight = WindowsTaskbarMetrics.standardHeight
            precondition(settings.displayTileSize == 40)
            checkWindowsGeometryAndMotion()
            checkWindowsViews()
            await checkWindowsReviewRegressions()
            await checkWindowsTaskbarSize()
            await Task.yield()
            print("Windows 11 taskbar regressions passed")
        }
        /// Files, folders and apps dropped on the tray's Trash button go to the Trash.
        private static func checkWindowsTrayTrash(root: DockRootView) {
            let canvas = root.canvas
            // Shelve mode can hide Trash, and then the tray has no Trash button.
            guard let trash = canvas.windowsStatus?.trashTile else {
                print("Skipped tray Trash drops: Shelve mode hides Trash")
                return
            }
            guard let frame = canvas.controller.visibleTileFrames[trash.id] else {
                preconditionFailure("The tray's Trash button must take drops")
            }
            let controller = canvas.controller
            defer { controller.dockDrag.clear() }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            controller.updateExternalDocumentDrop(at: center)
            precondition(controller.dockDrag.documentTargetTileID == trash.id, "Documents drop on Trash")
            controller.updateExternalFolderDrop(at: center)
            precondition(
                controller.dockDrag.documentTargetTileID == trash.id && controller.dockDrag.destinationIndex == nil,
                "A folder dropped on Trash goes to the Trash instead of the tray's items")
            controller.updateExternalAppDrop(at: center)
            precondition(controller.dockDrag.documentTargetTileID == trash.id, "Apps drop on Trash")
            // An app folder's apps are entries in a group; dropping one on Trash must not uninstall it.
            controller.dockDrag.sourceFolderTileID = "fixture-folder"
            controller.updateExternalAppDrop(at: center)
            precondition(
                controller.dockDrag.documentTargetTileID != trash.id, "Apps from an app folder never target Trash")
            precondition(
                !DockCanvasController.canTrash(Bundle.main.bundleURL), "Docky and running apps never go to the Trash")
            print("Tray Trash drop regressions passed")
        }
        private static func checkWindowsGeometryAndMotion() {
            for width: CGFloat in [0, 100, 320, 800, 1440, 3000] {
                for count in [0, 1, 4, 30, 100] {
                    let geometry = WindowsTaskbarGeometry(width: width, appCount: count, trayWidth: 220)
                    precondition(geometry.tray.maxX == width)
                    precondition(geometry.apps.minX >= 0 && geometry.apps.maxX <= geometry.tray.minX)
                    precondition(geometry.apps.width >= 0)
                    if geometry.contentWidth + 2 * 232 < width {
                        precondition(
                            abs(geometry.apps.midX - width / 2) < 0.001,
                            "Apps center against the whole screen")
                    }
                }
            }
            let layer = CALayer()
            layer.opacity = 0
            WindowsTaskbarStyle.animate(layer, keyPath: "opacity", to: 1, duration: 0.3)
            WindowsTaskbarStyle.animate(layer, keyPath: "opacity", to: 0.4, duration: 0.3)
            precondition(abs(layer.opacity - 0.4) < 0.001)
            precondition(WindowsTaskbarStyle.reducesMotion || layer.animation(forKey: "opacity") != nil)
        }
        private static func checkWindowsViews() {
            let root = DockRootView(frame: CGRect(x: 0, y: 0, width: 1000, height: 48))
            let window = NSWindow(
                contentRect: root.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = root
            root.layoutSubtreeIfNeeded()
            precondition(root.canvas.windowsStatus != nil)
            precondition(
                root.canvas.windowsAppTiles.first?.id == "windows:start"
                    || root.canvas.windowsAppTiles.first?.content.isWindowsStart == true)
            for tile in root.canvas.tiles.values {
                tile.layoutSubtreeIfNeeded()
                precondition(tile.bounds.size == CGSize(width: 40, height: 40))
                precondition(tile.imageView.frame.size == CGSize(width: 24, height: 24))
                tile.badge.stringValue = "999+"
                tile.layoutWindowsTile()
                precondition(tile.badge.frame.width >= tile.badge.intrinsicContentSize.width)
                checkWindowsIndicatorCentering(tile)
            }
            for tile in root.canvas.tiles.values {
                tile.mouseDownPoint = .zero
                TilePressService.shared.beginPress(tileID: tile.interaction.tile.id)
                tile.cancelDrag()
                precondition(TilePressService.shared.pressedTileID == nil)
                precondition(tile.mouseDownPoint == nil && tile.canceledMouseSession)
            }
            checkWindowsTrayTrash(root: root)
            captureWindowsSnapshots(root: root)
            let label = NSTextField(labelWithString: "Test")
            let popup = WindowsTaskbarPopup(content: label, size: CGSize(width: 220, height: 48))
            guard let anchor = root.canvas.tiles.values.first else {
                preconditionFailure("Start tile required")
            }
            popup.present(from: anchor)
            // A folder stack or fan opened from an overflow tile is a child window of the popup,
            // and clicking in it must not dismiss the popup out from under it.
            let presented = NSPanel(
                contentRect: CGRect(x: 0, y: 0, width: 40, height: 40), styleMask: [.borderless],
                backing: .buffered, defer: false)
            popup.panel.addChildWindow(presented, ordered: .above)
            precondition(WindowsTaskbarPopup.keepsPresented(forClickIn: popup.panel))
            precondition(WindowsTaskbarPopup.keepsPresented(forClickIn: presented))
            precondition(!WindowsTaskbarPopup.keepsPresented(forClickIn: window))
            precondition(!WindowsTaskbarPopup.keepsPresented(forClickIn: nil))
            popup.panel.removeChildWindow(presented)
            presented.close()
            popup.dismiss()
            precondition(!popup.panel.isVisible)
            root.canvas.clearWindowsTaskbar()
            precondition(root.canvas.windowsStatus == nil && root.canvas.windowsAnimationTimer == nil)
            window.contentView = nil
            window.close()

        }
        private static func checkWindowsIndicatorCentering(_ tile: NativeDockTileView) {
            for width: CGFloat in [6, 16, 6, 16] {
                tile.setWindowsIndicatorWidth(width)
                tile.layoutWindowsTile()
                let rendered = tile.windowsIndicator.frame.offsetBy(
                    dx: tile.indicator.frame.minX, dy: tile.indicator.frame.minY)
                precondition(abs(rendered.midX - tile.imageView.frame.midX) < 0.001)
                precondition(rendered.minY == 36 && rendered.size == CGSize(width: width, height: 3))
                if let animation = tile.windowsIndicator.animation(forKey: "bounds") as? CABasicAnimation {
                    for value in [animation.fromValue, animation.toValue] {
                        guard let bounds = (value as? NSValue)?.rectValue else {
                            preconditionFailure("Indicator width animation requires bounds")
                        }
                        let center = tile.windowsIndicator.position.x
                            + (0.5 - tile.windowsIndicator.anchorPoint.x) * bounds.width
                        precondition(abs(center - tile.indicator.bounds.midX) < 0.001)
                    }
                }
            }
            tile.updateWindowsIndicator()
        }
        static func captureWindowsSnapshots(root: DockRootView, suffix: String = "") {
            guard ProcessInfo.processInfo.arguments.contains("--windows-taskbar-snapshots") else { return }
            let directory = URL(fileURLWithPath: "/tmp/docky-windows-snapshots", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch { preconditionFailure("Cannot create snapshots: \(error)") }
            for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
                root.appearance = NSAppearance(named: appearance)
                root.layoutSubtreeIfNeeded()
                guard let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else {
                    preconditionFailure("Taskbar bitmap required")
                }
                root.cacheDisplay(in: root.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    preconditionFailure("Taskbar PNG required")
                }
                do {
                    try png.write(to: directory.appendingPathComponent("taskbar-\(name)\(suffix).png"))
                } catch { preconditionFailure("Cannot save snapshot: \(error)") }
            }
        }
    }

    extension TileContent {
        fileprivate var isWindowsStart: Bool {
            if case .startMenu = self { return true }
            return false
        }
    }
#endif
