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
            precondition(NativeSettingsController.panes.contains { $0.id == "menuExtras" })
            let rows = NativeSettingsFields.menuExtrasRows()
            guard let row = rows.first as? NativeFormRow,
                  let checkbox = row.arrangedSubviews.compactMap({ $0 as? NSButton }).first else {
                preconditionFailure("Menu Extras settings must expose the shared toggle")
            }
            precondition(checkbox.state == .off)
            checkbox.performClick(nil)
            precondition(bridge.enabled && UserDefaults.standard.bool(forKey: "nativeMenuExtras"))
            checkNativeOnlyStatusIcons()
            bridge.enabled = false
            await Task.yield()
            precondition(checkbox.state == .off, "Taskbar changes must update the settings checkbox")
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
            precondition(buttons.map(\.glyph) == ["overflow", "clock"],
                         "Battery, Volume, and Wi-Fi must have no synthetic taskbar replacements")
            precondition(status.preferredWidth == 110,
                         "Unhosted system extras must reserve no taskbar space")
            precondition(buttons.first?.isHidden == true && buttons.last?.isHidden == false,
                         "The clock must remain available with menu extras disabled")
        }
    }
#endif
