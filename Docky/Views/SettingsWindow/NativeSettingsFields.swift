import AppKit

@MainActor
enum NativeSettingsFields {
    static func rows(for pane: String) -> [NSView] {
        let builders: [String: () -> [NSView]] = [
            "appearanceGeneral": appearanceGeneralRows,
            "behaviorPlacement": behaviorPlacementRows,
            "behaviorVisibility": behaviorVisibilityRows,
            "behaviorWidgets": behaviorWidgetsRows,
            "behaviorLaunch": behaviorLaunchRows,
            "behaviorSystemDock": behaviorSystemDockRows,
            "menuExtras": menuExtrasRows,
            "behaviorAppFolders": behaviorAppFoldersRows,
            "startMenu": startMenuRows,
            "launchpad": launchpadRows,
            "windowManagement": windowManagementRows,
            "profiles": profilesRows,
            "appIcons": appIconsRows,
            "behaviorAppTileClick": behaviorAppTileClickRows,
            "behaviorGeneral": behaviorGeneralRows
        ]
        return builders[pane]?() ?? []
    }
    static func appearanceGeneralRows() -> [NSView] {
        let range = WindowsTaskbarMetrics.heightRange
        return [
            NativePreferenceField.number(
                String(localized: "Taskbar Size"), \.windowsTaskbarHeight,
                range: Double(range.lowerBound)...Double(range.upperBound))
        ]
    }

    static func behaviorPlacementRows() -> [NSView] {
        return [
            NativePreferenceField.choice(
                "Display", \.windowDisplayTarget, values: DockWindowDisplayTarget.allCases, name: { $0.title }),
            NativePreferenceField.choice(
                "Window Position", \.windowPosition, values: DockWindowPosition.allCases, name: { $0.title }),
            NativePreferenceField.choice(
                "Spaces", \.windowSpaceBehavior, values: DockWindowSpaceBehavior.allCases, name: { $0.title })
        ]
    }

    static func behaviorVisibilityRows() -> [NSView] {
        return [
            NativePreferenceField.number("Autohide Window Delay", \.autohideWindowDelay, range: 0...5),
            NativePreferenceField.boolean("Autohide Window", \.autohidesWindow),
            NativePreferenceField.boolean("Shelve Mode", \.enablesShelveMode),
            NativePreferenceField.choice(
                "Folder Badges", \.folderBadgeMode, values: FolderBadgeMode.allCases, name: { $0.title }),
            NativePreferenceField.choice(
                "Per-App Badge Style", \.folderBadgePreviewStyle, values: FolderBadgePreviewStyle.allCases,
                name: { $0.title }),
            NativePreferenceField.number("Fullscreen Reveal Delay", \.fullscreenRevealDelay, range: 0...2),
            NativePreferenceField.boolean("Disable Recent Apps", \.hidesRecentApps),
            NativePreferenceField.boolean(
                "List Minimized Windows in Switcher & Previews", \.includesMinimizedWindows),
            NativePreferenceField.boolean("Hide Finder", \.shelveHidesFinder),
            NativePreferenceField.boolean("Hide Trash", \.shelveHidesTrash),
            NativePreferenceField.boolean("Show Notification Badges", \.showsAppBadges),
            NativePreferenceField.boolean("Show Minimized Windows", \.showsMinimizedWindows),
            NativePreferenceField.boolean("Show Running Apps", \.showsRunningApps)
        ]
    }

    static func behaviorWidgetsRows() -> [NSView] {
        return [
            NativePreferenceField.boolean("Show Expanded Preview on Hover", \.enablesWidgetHoverPreview),
            NativePreferenceField.number("Widget Hover Preview Delay", \.widgetHoverPreviewDelay, range: 0...2)
        ]
    }

    static func behaviorLaunchRows() -> [NSView] {
        return [
            NativePreferenceField.boolean("Open at Login", \.opensAtLogin)
        ]
    }

    static func behaviorAppFoldersRows() -> [NSView] {
        return [
            NativePreferenceField.boolean("Shows Grouped Opened Apps In Dock", \.showsGroupedOpenedAppsInDock)
        ]
    }

    static func startMenuRows() -> [NSView] {
        return [
            NativePreferenceField.boolean("Enable Start Menu", \.enablesStartMenuOverlay),
            NativePreferenceField.boolean("Open Start Menu from Finder tile", \.opensStartMenuFromFinderTile)
        ]
    }

    static func launchpadRows() -> [NSView] {
        return [
            NativePreferenceField.boolean("Enable Launchpad", \.enablesLaunchpadOverlay),
            NativePreferenceField.boolean("Blur Background Image", \.launchpadBackgroundBlursImage),
            NativePreferenceField.image("Launchpad Background Image", \.launchpadBackgroundImagePath),
            NativePreferenceField.number("Icon Size", \.launchpadBaseIconSize, range: 48...192),
            NativePreferenceField.number("Column Spacing", \.launchpadColumnSpacing, range: 0...96),
            NativePreferenceField.integer("Columns", \.launchpadGridColumnCount, range: 1...12),
            NativePreferenceField.integer("Rows", \.launchpadGridRowCount, range: 1...10),
            NativePreferenceField.choice(
                "Scroll Direction", \.launchpadLayoutAxis, values: LaunchpadLayoutAxis.allCases, name: { $0.title }),
            NativePreferenceField.number(
                "Launchpad Overlay Transparency", \.launchpadOverlayTransparency, range: 0...1),
            NativePreferenceField.shortcut("Launchpad Shortcut", \.launchpadShortcut)
        ]
    }

    static func windowManagementRows() -> [NSView] {
        let closeKey = NativeKeyRecorderButton(key: \.switcherCloseKeyCode)
        let minimizeKey = NativeKeyRecorderButton(key: \.switcherMinimizeKeyCode)
        let zoomKey = NativeKeyRecorderButton(key: \.switcherZoomKeyCode)
        return [
            NativePreferenceField.boolean("Enable Window Switcher", \.enablesWindowSwitcher),
            NativePreferenceField.boolean("Replace macOS ⌘Tab", \.replacesSystemCommandTab),
            NativePreferenceField.boolean("Enable Switcher Preview", \.showsWindowSwitcherFocusPreview),
            NativeFormRow(
                title: String(localized: "Close Window"), control: closeKey),
            NativeFormRow(
                title: String(localized: "Minimize Window"),
                control: minimizeKey),
            NativeFormRow(
                title: String(localized: "Zoom Window"), control: zoomKey),
            NativePreferenceField.number("Window Preview Hover Delay", \.windowPreviewHoverDelay, range: 0...2),
            NativePreferenceField.choice(
                "Show Windows From", \.windowSwitcherSpaceScope, values: WindowSwitcherSpaceScope.allCases,
                name: { $0.title }),
            NativePreferenceField.choice(
                "Preview Mode", \.windowSwitcherPreviewMode, values: WindowSwitcherPreviewMode.allCases,
                name: { $0.title }),
            NativePreferenceField.shortcut(
                "Window Switcher Shortcut", \.windowSwitcherShortcut,
                overriddenBy: { DockyPreferences.shared.replacesSystemCommandTab ? .commandTab : nil })
        ]
    }

    static func profilesRows() -> [NSView] {
        return [
            NativePreferenceField.boolean("Hide Profile Strip", \.hidesProfileStrip)
        ]
    }

    static func appIconsRows() -> [NSView] {
        return [
            NativePreferenceField.optionalNumber(
                "Launchpad Icon Padding", \.launchpadIconPaddingFraction, range: 0...1),
            NativePreferenceField.image("Launchpad Icon", \.launchpadIconPath)
        ]
    }

    static func behaviorGeneralRows() -> [NSView] {
        [fileBrowserRow()]
    }

    /// File browsers that aren't installed stay listed but can't be chosen. A saved choice that
    /// isn't installed stays selected, and `FileBrowserService` uses Finder until it is.
    static func fileBrowserRow() -> NSView {
        let browsers = FileBrowser.allCases
        let control = NSPopUpButton()
        control.autoenablesItems = false
        for browser in browsers {
            let isInstalled = FileBrowserService.shared.isInstalled(browser)
            control.addItem(
                withTitle: isInstalled
                    ? browser.displayName
                    : String(
                        localized: "\(browser.displayName) (Not Installed)",
                        comment: "A file browser app's name, followed by a note that it isn't installed"))
            control.lastItem?.isEnabled = isInstalled
        }
        let row = NativeFormRow(title: String(localized: "File Browser"), control: control)
        row.bind(control) {
            if browsers.indices.contains(control.indexOfSelectedItem) {
                DockyPreferences.shared.fileBrowser = browsers[control.indexOfSelectedItem]
            }
        }
        row.observe { [weak control] in
            control?.selectItem(at: browsers.firstIndex(of: DockyPreferences.shared.fileBrowser) ?? 0)
        }
        return row
    }

    static func behaviorAppTileClickRows() -> [NSView] {
        return [
            NativePreferenceField.choice(
                "App Tile Frontmost Click Behavior", \.appTileFrontmostClickBehavior,
                values: AppTileFrontmostClickBehavior.allCases, name: { $0.title })
        ]
    }

}

extension NativeSettingsFields {
    static func behaviorSystemDockRows() -> [NSView] {
        let status = nativeLabel("")
        let error = NSTextField(wrappingLabelWithString: "")
        error.textColor = .secondaryLabelColor
        let retry = NativeActionButton("Retry") { WindowReservationService.shared.retryIntegration() }
        retry.setAccessibilityLabel(String(localized: "Retry system Dock integration"))
        let row = NativeFormRow(title: "System Integration", control: status, accessories: [retry])
        row.observe { [weak status, weak retry, weak error] in
            let service = WindowReservationService.shared
            let connected = service.backendStatus.contains("verified")
            status?.stringValue = service.lastError == nil
                ? (connected ? String(localized: "Connected") : String(localized: "Connecting…"))
                : String(localized: "Needs attention")
            status?.toolTip = service.lastError ?? service.backendDetails
            error?.stringValue = service.lastError ?? ""
            error?.isHidden = service.lastError == nil
            retry?.isHidden = service.lastError == nil
        }
        return [
            NSTextField(wrappingLabelWithString:
                "Docky replaces the system Dock while running. "
                    + "Your original Dock settings are restored when Docky quits."),
            row,
            error
        ]
    }

}
