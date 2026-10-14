import AppKit

extension DockTileInteraction {
    var dividerContextActions: [ContextAction] {
        [
            .action(preferences.autohidesWindow ? "Turn Hiding Off" : "Turn Hiding On") {
                preferences.autohidesWindow.toggle()
            },
            .action(dockSettings.magnification ? "Turn Magnification Off" : "Turn Magnification On") {
                dockSettings.setMagnification(!dockSettings.magnification)
            },
            .submenu(String(localized: "Position on Screen"), children: positionActions),
            .divider,
            .divider,
            .action(String(localized: "Edit Dock...")) {
                DockEditModeService.shared.enter()
            },
            .divider,
            .submenu(String(localized: "Troubleshoot"), children: troubleshootActions),
            .action(String(localized: "Send Feedback...")) {
                SettingsNavigator.shared.requestPane(id: "feedback")
            },
            .divider,
            .action(String(localized: "About Docky")) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel(nil)
            },
            .action(String(localized: "Settings...")) {
                (NSApp.delegate as? AppDelegate)?.showSettingsWindow(nil)
            },
            .divider,
            .action(String(localized: "Quit Docky"), isDestructive: true) {
                NSApp.terminate(nil)
            }
        ]
    }

    var positionActions: [ContextAction] {
        DockWindowPosition.allCases.map { position in
            .action(position.title, isOn: preferences.windowPosition == position) {
                preferences.windowPosition = position
            }
        }
    }

    var troubleshootActions: [ContextAction] {
        [
            .action(String(localized: "Sync Dock")) {
                DockSettingsService.shared.refresh()
                TileStore.shared.refresh()
            }
        ]
    }

}
