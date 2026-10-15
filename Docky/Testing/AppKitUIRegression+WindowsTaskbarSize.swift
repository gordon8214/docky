#if DEBUG
    import AppKit

    extension AppKitUIRegression {
        /// Runs with the Windows theme active and the taskbar at its standard height.
        static func checkWindowsTaskbarSize() async {
            let prefs = DockyPreferences.shared
            defer { prefs.windowsTaskbarHeight = WindowsTaskbarMetrics.standardHeight }
            checkWindowsTaskbarMetrics()
            prefs.windowsTaskbarHeight = 72
            precondition(DockSettingsService.shared.displayTileSize == 60)
            // Leaves the shared chrome size at 72 points for the root view fixtures.
            checkWindowsMainWindowResize()
            checkWindowsLargeTaskbarViews()
            checkWindowsTaskbarDragEvents()
            checkWindowsResizeHandle()
            await checkWindowsTaskbarSizeSetting()
            print("Windows taskbar resize regressions passed")
        }
        private static func checkWindowsTaskbarMetrics() {
            let standard = WindowsTaskbarMetrics.standard
            precondition(
                standard.height == 48 && standard.inset == 4 && standard.buttonSize == 40 && standard.pitch == 44
                    && standard.buttonOffset == 2 && standard.margin == 12 && standard.iconSize == 24
                    && standard.iconOrigin == 8, "Standard metrics must match the fixed Windows 11 layout")
            precondition(
                standard.indicatorY == 36 && standard.indicatorHeight == 3 && standard.activeIndicatorWidth == 16
                    && standard.inactiveIndicatorWidth == 6 && standard.badgeHeight == 16 && standard.badgeY == 2)
            precondition(
                standard.overflowWidth == 32 && standard.clockWidth == 98 && standard.clockFontSize == 12
                    && standard.menuExtraSlotWidth == 32 && standard.menuExtraButtonHeight == 32
                    && standard.menuExtrasMaximumWidth == 448 && standard.resizeHandleHeight == 4)
            let large = WindowsTaskbarMetrics(height: 72)
            precondition(
                large.inset == 6 && large.buttonSize == 60 && large.pitch == 66 && large.iconSize == 36
                    && large.iconOrigin == 12 && large.indicatorY == 54 && large.activeIndicatorWidth == 24
                    && large.inactiveIndicatorWidth == 9 && large.clockWidth == 147 && large.margin == 18)
            precondition(WindowsTaskbarMetrics(height: 10).height == 32)
            precondition(WindowsTaskbarMetrics(height: 500).height == 96)
            precondition(WindowsTaskbarMetrics(height: 47.6).height == 48)
            precondition(WindowsTaskbarMetrics(height: .nan).height == 48)
            for height in 32...96 {
                let metrics = WindowsTaskbarMetrics(height: CGFloat(height))
                precondition(metrics.iconOrigin >= 0 && metrics.iconOrigin + metrics.iconSize <= metrics.indicatorY)
                precondition(metrics.indicatorY + metrics.indicatorHeight <= metrics.buttonSize)
                precondition(metrics.menuExtraButtonHeight <= metrics.buttonSize)
                precondition(metrics.menuExtraSlotWidth >= 32, "Native menu extras never shrink")
                precondition(metrics.badgeHeight < metrics.buttonSize)
                precondition(metrics.resizeHandleHeight <= metrics.inset + 1)
            }
            let geometry = WindowsTaskbarGeometry(width: 1000, appCount: 3, trayWidth: 200, metrics: large)
            precondition(geometry.tray.height == 72 && geometry.apps.height == 72 && geometry.contentWidth == 198)
            let status = WindowsTaskbarStatusView()
            status.metrics = large
            precondition(status.preferredWidth == 165)
        }
        private static func checkWindowsLargeTaskbarViews() {
            let root = DockRootView(frame: CGRect(x: 0, y: 0, width: 1000, height: 72))
            let window = NSWindow(contentRect: root.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = root
            defer {
                root.canvas.clearWindowsTaskbar()
                window.contentView = nil
                window.close()
            }
            root.layoutSubtreeIfNeeded()
            let metrics = root.canvas.windowsMetrics
            precondition(metrics.height == 72)
            precondition(!root.resizeHandle.isHidden)
            precondition(root.resizeHandle.frame == CGRect(x: 0, y: 0, width: 1000, height: 6))
            for (index, id) in root.canvas.windowsTileIDs.enumerated() {
                guard let tile = root.canvas.tiles[id] else { preconditionFailure("Taskbar tile required") }
                precondition(tile.frame == CGRect(x: CGFloat(index) * 66 + 3, y: 6, width: 60, height: 60))
                tile.layoutSubtreeIfNeeded()
                precondition(tile.imageView.frame == CGRect(x: 12, y: 12, width: 36, height: 36))
                precondition(tile.interaction.renderedTileSize == 60)
                tile.layoutWindowsTile()
                precondition(tile.indicator.frame == CGRect(x: 18, y: 54, width: 24, height: 5))
                precondition(tile.badge.frame.height == 24)
            }
            guard let status = root.canvas.windowsStatus else { preconditionFailure("Taskbar tray required") }
            status.layoutSubtreeIfNeeded()
            precondition(status.frame.height == 72 && status.metrics == metrics)
            precondition(status.subviews.allSatisfy { $0.isHidden || ($0.frame.minY == 6 && $0.frame.height == 60) })
            captureWindowsSnapshots(root: root, suffix: "-72")
        }
        private static func checkWindowsMainWindowResize() {
            let main = MainWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            main.isReleasedWhenClosed = false
            defer { main.close() }
            let prefs = DockyPreferences.shared
            main.applyCurrentFrame(animated: false)
            precondition(main.frame.height == 72 && DockLayoutService.shared.chromeSize.height == 72)
            main.beginTaskbarResize()
            main.applyTaskbarResize(height: 80.4)
            precondition(main.isResizingTaskbar && prefs.windowsTaskbarHeight == 80 && main.frame.height == 80)
            precondition(DockLayoutService.shared.chromeSize.height == 80)
            main.endTaskbarResize()
            precondition(!main.isResizingTaskbar && main.frame.height == 80)
            prefs.windowsTaskbarHeight = 72
            main.applyCurrentFrame(animated: false)
            precondition(main.frame.height == 72)
        }
        /// Drives the real nib-loaded window through `sendEvent`, so AppKit's own
        /// event routing decides who receives the drag.
        private static func checkWindowsTaskbarDragEvents() {
            var objects: NSArray?
            guard Bundle.main.loadNibNamed("MainWindow", owner: nil, topLevelObjects: &objects),
                let main = (objects as? [Any])?.compactMap({ $0 as? MainWindow }).first,
                let root = main.contentView?.subviews.first as? DockRootView else {
                preconditionFailure("Main window nib required")
            }
            defer { main.close() }
            // ScreenCaptureKit's ReplayKit adds `.resizable`, after which AppKit
            // resizes the panel from its top edge instead of delivering the drag.
            main.styleMask.insert(.resizable)
            precondition(!main.styleMask.contains(.resizable), "The dock panel must never be natively resizable")
            main.orderFront(nil)
            main.applyCurrentFrame(animated: false)
            root.layoutSubtreeIfNeeded()
            let prefs = DockyPreferences.shared
            let start = prefs.windowsTaskbarHeight
            defer { prefs.windowsTaskbarHeight = start }
            let top = main.frame.height - 2
            precondition(main.contentView?.superview?.hitTest(CGPoint(x: 400, y: top)) === root.resizeHandle)
            func send(_ type: NSEvent.EventType, y: CGFloat) {
                guard let event = NSEvent.mouseEvent(
                    with: type, location: CGPoint(x: 400, y: y), modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: main.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1) else {
                    preconditionFailure("Mouse fixture required")
                }
                main.sendEvent(event)
            }
            send(.leftMouseDown, y: top)
            precondition(main.isResizingTaskbar, "The resize handle must receive the mouse-down")
            send(.leftMouseDragged, y: top + 16)
            precondition(prefs.windowsTaskbarHeight == start + 16 && main.frame.height == start + 16)
            root.layoutSubtreeIfNeeded()
            let metrics = root.canvas.windowsMetrics
            precondition(metrics.height == start + 16, "The taskbar content must scale with the window")
            precondition(root.canvas.tiles.values.allSatisfy { $0.frame.size.height == metrics.buttonSize })
            send(.leftMouseUp, y: top + 16)
            precondition(!main.isResizingTaskbar)
        }
        private static func checkWindowsResizeHandle() {
            let prefs = DockyPreferences.shared
            let tileSize = DockSettingsService.shared.tileSize
            let root = DockRootView(frame: CGRect(x: 0, y: 0, width: 1000, height: 72))
            let window = WindowsResizeWindow(
                contentRect: root.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = root
            defer {
                root.canvas.clearWindowsTaskbar()
                window.contentView = nil
                window.close()
            }
            root.layoutSubtreeIfNeeded()
            let handle = root.resizeHandle
            // Window coordinates are unflipped, so the handle spans the top of the window.
            let top = CGPoint(x: 500, y: root.bounds.height - 2)
            precondition(root.hitTest(top) === handle, "The top edge must hit the resize handle")
            precondition(root.hitTest(CGPoint(x: 500, y: 20)) !== handle, "Taskbar buttons must stay clickable")
            func event(_ type: NSEvent.EventType, y: CGFloat, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
                guard let event = NSEvent.mouseEvent(
                    with: type, location: CGPoint(x: top.x, y: y), modifierFlags: modifiers, timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                    pressure: 1) else {
                    preconditionFailure("Mouse fixture required")
                }
                return event
            }
            let held = window.interactionTokens.count
            handle.mouseDown(with: event(.leftMouseDown, y: top.y))
            precondition(handle.isDragging && window.isResizing && window.interactionTokens.count == held + 1)
            handle.mouseDragged(with: event(.leftMouseDragged, y: top.y + 10.3))
            precondition(prefs.windowsTaskbarHeight == 82, "Dragging up grows the bar in whole points")
            handle.mouseDragged(with: event(.leftMouseDragged, y: top.y + 1000))
            precondition(prefs.windowsTaskbarHeight == 96)
            handle.mouseDragged(with: event(.leftMouseDragged, y: top.y - 1000))
            precondition(prefs.windowsTaskbarHeight == 32)
            handle.mouseUp(with: event(.leftMouseUp, y: top.y - 1000))
            precondition(!handle.isDragging && !window.isResizing && window.endCount == 1)
            precondition(window.interactionTokens.count == held, "Releasing must free the taskbar hold")
            precondition(DockSettingsService.shared.tileSize == tileSize, "The Dock's tile size must not change")
            var titles: [String] = []
            defer { ContextActionMenuPresenter.testInterceptor = nil }
            ContextActionMenuPresenter.testInterceptor = { menu, _, _ in titles = menu.items.map(\.title) }
            handle.mouseDown(with: event(.leftMouseDown, y: top.y, modifiers: .control))
            let settings = String(localized: "Settings...")
            precondition(!handle.isDragging && titles.contains(settings))
            titles = []
            root.hitTest(top)?.rightMouseDown(with: event(.rightMouseDown, y: top.y))
            precondition(titles.contains(settings), "Right-clicking the top edge opens the taskbar menu")
        }
        private static func checkWindowsTaskbarSizeSetting() async {
            let controller = NativeSettingsPaneController(id: "appearanceTileLayout")
            _ = controller.view
            func titles() -> [String] {
                controller.stack.arrangedSubviews.compactMap { ($0 as? NativeFormRow)?.accessibilityLabel() }
            }
            precondition(controller.showsTaskbarSize && titles().contains(String(localized: "Taskbar Size")))
            precondition(!titles().contains(String(localized: "Tile Size")))
            let manager = ThemeManager.shared
            manager.clearActive()
            for _ in 0..<50 where controller.showsTaskbarSize { await Task.yield() }
            precondition(!controller.showsTaskbarSize && titles().contains(String(localized: "Tile Size")))
            manager.setActive("windows")
            for _ in 0..<50 where !controller.showsTaskbarSize { await Task.yield() }
            precondition(controller.showsTaskbarSize, "Switching back to Windows restores the taskbar size row")
        }
    }

    /// Records resize calls and taskbar holds without moving the real Docky window.
    private final class WindowsResizeWindow: NSWindow, DockWindowInteractionHolding, WindowsTaskbarResizing {
        private(set) var interactionTokens: Set<UUID> = []
        private(set) var isResizing = false
        private(set) var endCount = 0
        func beginInteraction() -> UUID? {
            let token = UUID()
            interactionTokens.insert(token)
            return token
        }
        func endInteraction(_ token: UUID?) {
            if let token { interactionTokens.remove(token) }
        }
        func beginTaskbarResize() { isResizing = true }
        func applyTaskbarResize(height: CGFloat) {
            precondition(isResizing, "Resizing must begin before it applies")
            DockyPreferences.shared.windowsTaskbarHeight = height
        }
        func endTaskbarResize() {
            isResizing = false
            endCount += 1
        }
    }
#endif
