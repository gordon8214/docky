#if DEBUG
    import AppKit
    import QuartzCore

    extension AppKitUIRegression {
        static func checkWindowsTaskbar() async {
            let manager = ThemeManager.shared
            let oldTheme = manager.activeThemeID
            let prefs = DockyPreferences.shared
            let settings = DockSettingsService.shared
            let oldPosition = prefs.windowPosition
            let oldSize = settings.tileSize
            let oldMagnification = settings.magnification
            defer {
                if let oldTheme { manager.setActive(oldTheme) } else { manager.clearActive() }
            }
            manager.setActive("windows")
            precondition(WindowsTaskbarStyle.isActive)
            precondition(
                prefs.effectiveWindowPosition == .bottom && prefs.effectiveWindowAxisSizing == .fullAxis)
            precondition(settings.displayTileSize == 40)
            precondition(
                prefs.windowPosition == oldPosition && settings.tileSize == oldSize
                    && settings.magnification == oldMagnification)
            guard let manifest = manager.activeManifest,
                let encoded = try? JSONEncoder().encode(manifest),
                let decoded = try? JSONDecoder().decode(ThemeManifest.self, from: encoded)
            else {
                preconditionFailure("Windows theme must round-trip")
            }
            precondition(decoded.behavior?.taskbarStyle == "windows11")
            precondition(decoded.layout?.insertions?.isEmpty == true, "The taskbar must not inject Search")
            checkWindowsArchiveRoundTrip()
            checkWindowsGeometryAndMotion()
            checkWindowsViews()
            await checkWindowsReviewRegressions()
            manager.clearActive()
            precondition(!WindowsTaskbarStyle.isActive && prefs.effectiveWindowPosition == oldPosition)
            precondition(settings.displayTileSize == oldSize)
            await Task.yield()
            print("Windows 11 taskbar regressions passed")
        }
        private static func checkWindowsArchiveRoundTrip() {
            let identifier = "docky.windows-export." + UUID().uuidString
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(identifier)
            guard let defaults = UserDefaults(suiteName: identifier) else {
                preconditionFailure("Isolated export defaults required")
            }
            defer {
                defaults.removePersistentDomain(forName: identifier)
                try? FileManager.default.removeItem(at: directory)
            }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let archive = directory.appendingPathComponent("windows.dockytheme")
                try ThemeManager.shared.exportCurrentAppearance(name: "Windows export fixture", to: archive)
                let restored = ThemeManager(
                    defaults: defaults, directoryURL: directory.appendingPathComponent("themes"))
                let imported = try restored.importTheme(from: archive)
                restored.setActive(imported.id)
                precondition(restored.activeManifest?.behavior?.taskbarStyle == "windows11")
                precondition(restored.activeManifest?.behavior?.tileSize == nil)
                precondition(restored.activeManifest?.behavior?.windowAxisSizing == nil)
                precondition(restored.activeManifest?.behavior?.magnification == nil)
            } catch { preconditionFailure("Windows archive round-trip failed: \(error)") }
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
            precondition(root.canvas.controller.magnificationPass().iconSizes.isEmpty)
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
            captureWindowsSnapshots(root: root)
            let label = NSTextField(labelWithString: "Test")
            let popup = WindowsTaskbarPopup(content: label, size: CGSize(width: 220, height: 48))
            guard let anchor = root.canvas.tiles.values.first else {
                preconditionFailure("Start tile required")
            }
            popup.present(from: anchor)
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
        private static func captureWindowsSnapshots(root: DockRootView) {
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
                    try png.write(to: directory.appendingPathComponent("taskbar-\(name).png"))
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
