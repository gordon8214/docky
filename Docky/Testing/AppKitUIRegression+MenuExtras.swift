#if DEBUG
    import AppKit

    extension AppKitUIRegression {
        static func checkMenuExtras() async {
            let display = CGRect(x: -1440, y: -900, width: 1440, height: 900)
            let icon = CGRect(x: -80, y: -900, width: 22, height: 28)
            precondition(MenuExtraGeometry.visibleItem(icon, on: display))
            precondition(!MenuExtraGeometry.visibleItem(icon.offsetBy(dx: 100, dy: 0), on: display))
            precondition(!MenuExtraGeometry.visibleItem(icon.offsetBy(dx: 0, dy: 80), on: display))
            precondition(!MenuExtraGeometry.visibleItem(CGRect(x: -80, y: -900, width: 22, height: 0), on: display))
            let visible = CGRect(x: -1440, y: -872, width: 1440, height: 824)
            let size = CGSize(width: 300, height: 240)
            let anchor = CGRect(x: -45, y: -40, width: 32, height: 32)
            let origin = MenuExtraGeometry.popupOrigin(size: size, anchor: anchor, visible: visible)
            precondition(visible.contains(CGRect(origin: origin, size: size)))
            precondition(origin.y + size.height == anchor.minY - 8)
            precondition(origin.x + size.width == visible.maxX)
            let backdrop = CGRect(x: -600, y: -872, width: 656, height: 962)
            let controls = CGRect(x: -425, y: -838, width: 290, height: 525)
            let movedOrigin = MenuExtraGeometry.windowOrigin(container: backdrop, content: controls,
                                                            anchor: anchor, visible: visible)
            let movedControls = controls.offsetBy(dx: movedOrigin.x - backdrop.minX,
                                                 dy: movedOrigin.y - backdrop.minY)
            precondition(visible.contains(movedControls), "Transparent backdrops must not determine popup placement")
            precondition(movedControls.maxY == anchor.minY - 8)
            await checkNativeMenuExtrasToggle()
            print("Menu-extra geometry and native-only toggle regressions passed")
        }

        private static func checkNativeMenuExtrasToggle() async {
            let bridge = MenuExtrasNativeBridge.shared
            let previous = bridge.enabled
            defer { bridge.enabled = previous }
            bridge.enabled = false
            precondition(SettingsPane.allCases.contains(.menuExtras))
            let pane = NativeSettingsPaneController(pane: .menuExtras)
            _ = pane.view
            guard let toggle = SettingsLookup.control(NSSwitch.self, identifier: "nativeMenuExtras", in: pane.view)
            else {
                preconditionFailure("Menu Extras settings must expose the shared toggle")
            }
            precondition(toggle.state == .off)
            // `NSSwitch` isn't an `NSButton`, so switch it the way a click does.
            toggle.state = .on
            toggle.sendAction(toggle.action, to: toggle.target)
            precondition(bridge.enabled && UserDefaults.standard.bool(forKey: "nativeMenuExtras"))
            checkNativeOnlyStatusIcons()
            bridge.enabled = false
            await Task.yield()
            precondition(toggle.state == .off, "Taskbar changes must update the settings switch")
            let extras = WindowsMenuExtrasView()
            extras.refresh()
            precondition(extras.preferredWidth == 0, "Disabled extras must occupy no taskbar space")
            precondition(MenuExtrasService.shared.items.isEmpty && bridge.hostedIDs.isEmpty)
            precondition(!bridge.isTracking && !UserDefaults.standard.bool(forKey: "nativeMenuExtras"))
            checkNativeOnlyStatusIcons()
        }

        private static func checkNativeOnlyStatusIcons() {
            let status = WindowsTaskbarStatusView()
            status.refresh()
            let buttons = status.subviews.compactMap { $0 as? WindowsStatusButton }
            precondition(buttons.map(\.glyph) == ["overflow", "trash", "clock"],
                         "Battery, Volume, and Wi-Fi must have no synthetic taskbar replacements")
            precondition(status.preferredWidth == 110,
                         "Unhosted system extras must reserve no taskbar space")
            precondition(buttons[0].isHidden && buttons[1].isHidden && buttons[2].isHidden == false,
                         "Without overflow tiles or a Trash tile, only the clock remains")
            status.trashTile = Tile(id: "trailing:trash", content: .trash)
            status.frame = CGRect(x: 0, y: 0, width: status.preferredWidth, height: status.metrics.height)
            status.layoutSubtreeIfNeeded()
            let trash = buttons[1]
            precondition(
                !trash.isHidden && trash.frame.minX == 0 && status.preferredWidth == 110 + status.metrics.overflowWidth,
                "The Trash button leads the tray when there are no overflow tiles")
            precondition(trash.image != nil && trash.contextActions?().isEmpty == false && trash.onActivate != nil,
                         "The Trash button shows Trash's icon, opens it, and offers its menu")
            status.isTrashDropTarget = true
            precondition(trash.isDropTarget, "The Trash button highlights as a drop target")
        }
    }
#endif
