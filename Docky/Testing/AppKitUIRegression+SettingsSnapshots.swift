#if DEBUG
    import AppKit

    extension AppKitUIRegression {
        /// With `--settings-snapshots`, writes every Settings pane, and the Launchpad
        /// inspector's pane, in light and dark to /tmp/docky-settings-snapshots.
        static func captureSettingsSnapshots(suite: RegressionDefaults) {
            guard ProcessInfo.processInfo.arguments.contains("--settings-snapshots") else { return }
            let directory = URL(fileURLWithPath: "/tmp/docky-settings-snapshots", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch { preconditionFailure("Cannot create snapshots: \(error)") }
            let snapshot = SettingsWindowController(defaults: suite.defaults, autosavesFrame: false)
            guard let window = snapshot.window else { preconditionFailure("Settings needs a window") }
            for pane in SettingsPane.allCases {
                snapshot.showPane(pane)
                capture(window, name: pane.rawValue, in: directory)
            }
            snapshot.close()
            let inspector = NativeSettingsPaneController(pane: .launchpad, placement: .launchpadInspector)
            let panel = NSPanel(
                contentRect: CGRect(x: 0, y: 0, width: 440, height: 580),
                styleMask: [.titled, .closable, .utilityWindow, .hudWindow], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.contentViewController = inspector
            panel.setContentSize(CGSize(width: 440, height: 580))
            capture(panel, name: "launchpad-inspector", in: directory)
            panel.contentViewController = nil
            panel.close()
        }

        private static func capture(_ window: NSWindow, name: String, in directory: URL) {
            // The frame view also draws the titlebar and toolbar.
            guard let view = window.contentView?.superview ?? window.contentView else { return }
            for (appearanceName, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                window.appearance = NSAppearance(named: appearance)
                // Wrapping labels settle their height on a second pass.
                window.layoutIfNeeded()
                window.layoutIfNeeded()
                view.displayIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    preconditionFailure("Settings bitmap required")
                }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    preconditionFailure("Settings PNG required")
                }
                do {
                    try png.write(to: directory.appendingPathComponent("settings-\(name)-\(appearanceName).png"))
                } catch { preconditionFailure("Cannot save snapshot: \(error)") }
            }
        }
    }
#endif
