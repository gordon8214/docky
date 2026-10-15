import AppKit

@MainActor
enum NativeSettingsFields {
    static func rows(for pane: String) -> [NSView] {
        let builders: [String: () -> [NSView]] = [
            "appearanceGeneral": appearanceGeneralRows,
            "appearanceIndicators": appearanceIndicatorsRows,
            "appearanceTileLayout": appearanceTileLayoutRows,
            "appearanceWindowShape": appearanceWindowShapeRows,
            "appearanceWidgets": appearanceWidgetsRows,
            "appearanceWindowBackground": appearanceWindowBackgroundRows,
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
            "behaviorAppTileClick": behaviorAppTileClickRows
        ]
        return builders[pane]?() ?? []
    }
    static func appearanceGeneralRows() -> [NSView] {
        return [
            NativePreferenceField.boolean("Disable Glass Look", \.disablesGlassLook)
        ]
    }

    static func appearanceIndicatorsRows() -> [NSView] {
        return [
            NativePreferenceField.color("Active Indicator Color", \.activeIndicatorColor),
            NativePreferenceField.image("Active Indicator Image", \.activeIndicatorImagePath),
            NativePreferenceField.number("Inward Offset", \.activeIndicatorOffset, range: -20...20),
            NativePreferenceField.number("Size", \.activeIndicatorScale, range: 0.5...2),
            NativePreferenceField.choice(
                "Active Indicator Shape", \.activeIndicatorShape, values: DockTileIndicatorShape.allCases,
                name: { $0.title }),
            NativePreferenceField.image("Divider Image", \.dividerImagePath),
            NativePreferenceField.number("Image Size", \.dividerImageScale, range: 0.5...2),
            NativePreferenceField.number("Divider Offset", \.dividerOffset, range: -20...20),
            NativePreferenceField.number("Divider Opacity", \.dividerOpacity, range: 0...1),
            NativePreferenceField.number("Divider Padding", \.dividerPaddingFraction, range: 0...0.5),
            NativePreferenceField.image("Left Divider Image", \.leftDividerImagePath),
            NativePreferenceField.boolean("Mirror Left Side", \.mirrorsLeftDividerOnRight),
            NativePreferenceField.image("Right Divider Image", \.rightDividerImagePath),
            NativePreferenceField.color("Divider Color", \.dividerColor)
        ]
    }

    static func appearanceTileLayoutRows() -> [NSView] {
        return [
            NativePreferenceField.number("Icon Shadow Opacity", \.iconShadowOpacity, range: 0...1),
            NativePreferenceField.number("Icon Shadow Radius", \.iconShadowRadius, range: 0...32),
            NativePreferenceField.color("Tile Active Background Color", \.tileActiveBackgroundColor),
            NativePreferenceField.image("Tile Active Background Image", \.tileActiveBackgroundImagePath),
            NativePreferenceField.choice(
                "Tile Clip Shape", \.tileClipShape, values: DockClipShape.allCases, name: { $0.title }),
            NativePreferenceField.color("Tile Hover Background Color", \.tileHoverBackgroundColor),
            NativePreferenceField.image("Tile Hover Background Image", \.tileHoverBackgroundImagePath),
            NativePreferenceField.number("Icon Padding", \.tileIconPadding, range: 0...24),
            NativePreferenceField.number("Spacing", \.tileSpacing, range: 0...16),
            NativePreferenceField.number("Vertical Padding", \.tileVerticalPadding, range: 8...32),
            NativePreferenceField.color("Icon Shadow Color", \.iconShadowColor),
            NativePreferenceField.optionalNumber(
                "Tile Active Background Corner Radius", \.tileActiveBackgroundCornerRadius, range: 0...32),
            NativePreferenceField.optionalNumber(
                "Tile Active Background Opacity", \.tileActiveBackgroundOpacity, range: 0...1),
            NativePreferenceField.optionalNumber(
                "Tile Hover Background Corner Radius", \.tileHoverBackgroundCornerRadius, range: 0...32),
            NativePreferenceField.optionalNumber(
                "Tile Hover Background Opacity", \.tileHoverBackgroundOpacity, range: 0...1),
            NativePreferenceField.optionalNumber("Tile Hover Opacity", \.tileHoverOpacity, range: 0...1),
            NativePreferenceField.optionalNumber("Tile Hover Scale", \.tileHoverScale, range: 0.8...1.4)
        ]
    }

    static func appearanceWindowShapeRows() -> [NSView] {
        return [
            NativePreferenceField.choice(
                "Chrome Clip Shape", \.windowClipShape, values: DockClipShape.allCases, name: { $0.title }),
            NativePreferenceField.number("Window Content Inset Bottom", \.windowContentInsetBottom, range: 0...16),
            NativePreferenceField.number(
                "Window Content Inset Leading", \.windowContentInsetLeading, range: 0...16),
            NativePreferenceField.number("Window Content Inset Top", \.windowContentInsetTop, range: 0...16),
            NativePreferenceField.number(
                "Window Content Inset Trailing", \.windowContentInsetTrailing, range: 0...16),
            NativePreferenceField.number("Window Corner Radius", \.windowCornerRadius, range: 0...32),
            NativePreferenceField.optionalNumber(
                "Window Corner Radius Bottom Leading", \.windowCornerRadiusBottomLeading, range: 0...32),
            NativePreferenceField.optionalNumber(
                "Window Corner Radius Bottom Trailing", \.windowCornerRadiusBottomTrailing, range: 0...32),
            NativePreferenceField.optionalNumber(
                "Window Corner Radius Top Leading", \.windowCornerRadiusTopLeading, range: 0...32),
            NativePreferenceField.optionalNumber(
                "Window Corner Radius Top Trailing", \.windowCornerRadiusTopTrailing, range: 0...32)
        ]
    }

    static func appearanceWidgetsRows() -> [NSView] {
        return [
            NativePreferenceField.optionalNumber("1 Tile Content Padding", \.widget1xContentPadding, range: 0...32),
            NativePreferenceField.optionalNumber("1 Tile Corner Radius", \.widget1xCornerRadius, range: 0...32),
            NativePreferenceField.optionalNumber("2 Tile Content Padding", \.widget2xContentPadding, range: 0...32),
            NativePreferenceField.optionalNumber("2 Tile Corner Radius", \.widget2xCornerRadius, range: 0...32),
            NativePreferenceField.optionalNumber("3 Tile Content Padding", \.widget3xContentPadding, range: 0...32),
            NativePreferenceField.optionalNumber("3 Tile Corner Radius", \.widget3xCornerRadius, range: 0...32)
        ]
    }

    static func appearanceWindowBackgroundRows() -> [NSView] {
        return [
            NativePreferenceField.choice(
                "Background Image Mode", \.windowBackgroundImageMode, values: DockBackgroundImageMode.allCases,
                name: { $0.title }),
            NativePreferenceField.image("Window Background Image", \.windowBackgroundImagePath),
            NativePreferenceField.color("Window Border Color", \.windowBorderColor),
            NativePreferenceField.color("Window Tint Color", \.windowTintColor),
            NativePreferenceField.number("Background Opacity", \.windowTintOpacity, range: 0...1),
            NativePreferenceField.number("Window Border Width", \.windowBorderWidth, range: 0...8)
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
            NativePreferenceField.number("Autohide Animation Duration", \.autohideAnimationDuration, range: 0...1),
            NativePreferenceField.number("Autohide Window Delay", \.autohideWindowDelay, range: 0...5),
            NativePreferenceField.boolean("Autohide Window", \.autohidesWindow),
            NativePreferenceField.boolean("Dim Idle App Icons", \.dimsIdleAppIcons),
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
            NativePreferenceField.choice(
                "Overflow Behavior", \.overflowBehavior, values: DockOverflowBehavior.allCases, name: { $0.title }),
            NativePreferenceField.boolean("Hide Finder", \.shelveHidesFinder),
            NativePreferenceField.boolean("Hide Trash", \.shelveHidesTrash),
            NativePreferenceField.boolean("Show Active/Pinned Separator", \.showsActivePinnedSeparator),
            NativePreferenceField.boolean("Show Notification Badges", \.showsAppBadges),
            NativePreferenceField.boolean("Show Minimized Windows", \.showsMinimizedWindows),
            NativePreferenceField.boolean("Show Running Apps", \.showsRunningApps),
            NativePreferenceField.choice(
                "Window Axis Size", \.windowAxisSizing, values: DockWindowAxisSizing.allCases, name: { $0.title })
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

            NativePreferenceField.boolean("Shows Grouping Backdrop", \.showsGroupedOpenedAppsBackdrop),
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
                "Layout", \.windowPreviewLayout, values: WindowSwitcherLayout.allCases, name: { $0.title }),
            NativePreferenceField.choice(
                "Layout", \.windowSwitcherLayout, values: WindowSwitcherLayout.allCases, name: { $0.title }),
            NativePreferenceField.choice(
                "Preview Mode", \.windowSwitcherPreviewMode, values: WindowSwitcherPreviewMode.allCases,
                name: { $0.title }),
            NativePreferenceField.shortcut("Window Switcher Shortcut", \.windowSwitcherShortcut)
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
            NativePreferenceField.image("Launchpad Icon", \.launchpadIconPath),
            NativePreferenceField.optionalNumber(
                "Start Menu Icon Padding", \.startMenuIconPaddingFraction, range: 0...1),
            NativePreferenceField.image("Start Menu Icon", \.startMenuIconPath)
        ]
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
