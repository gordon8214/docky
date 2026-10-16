import AppKit

extension NativeSettingsContent {
    static func windowManagementSections() -> [NativeSettingsSection] {
        let preferences = { DockyPreferences.shared }
        let switcherOn: @MainActor () -> Bool = { preferences().enablesWindowSwitcher }
        let fontSizes = WindowSwitcherGeometry.Metrics.fontSizeRange
        let iconSizes = WindowSwitcherGeometry.Metrics.iconSizeRange
        let shortcutDescription = String(
            localized: "Choose the global shortcut that opens Docky's Cmd-Tab-style window switcher.")
        return [
            NativeSettingsSection(
                String(localized: "Window Switcher"),
                rows: [
                    NativePreferenceField.toggle(
                        String(localized: "Enable Window Switcher"),
                        description: String(
                            localized:
                                "Turn Docky's Cmd-Tab-style switcher on or off without clearing its shortcut or preview preference."),
                        \.enablesWindowSwitcher),
                    NativePreferenceField.toggle(
                        String(localized: "Replace macOS ⌘Tab"),
                        description: String(
                            localized: "⌘Tab opens Docky's switcher, and the macOS app switcher is off while Docky runs."),
                        \.replacesSystemCommandTab
                    ).enabled(when: switcherOn),
                    NativePreferenceField.shortcut(
                        String(localized: "Shortcut"), \.windowSwitcherShortcut,
                        overriddenBy: { preferences().replacesSystemCommandTab ? .commandTab : nil }
                    ).describing {
                        preferences().replacesSystemCommandTab
                            ? String(localized: "⌘Tab opens the switcher while Replace macOS ⌘Tab is on.")
                            : shortcutDescription
                    }.enabled(when: switcherOn),
                    NativePreferenceField.choice(
                        String(localized: "Show Windows From"), \.windowSwitcherSpaceScope,
                        values: WindowSwitcherSpaceScope.allCases, name: \.title
                    ).enabled(when: switcherOn),
                    NativePreferenceField.toggle(
                        String(localized: "Include Minimized Windows"),
                        description: String(
                            localized: "Minimized windows appear dimmed in the switcher and in window previews."),
                        \.includesMinimizedWindows)
                ]),
            NativeSettingsSection(
                String(localized: "Switcher Appearance"),
                rows: [
                    NativePreferenceField.stepper(
                        String(localized: "Switcher Font Size"), \.windowSwitcherFontSize,
                        range: Double(fontSizes.lowerBound)...Double(fontSizes.upperBound), format: .points),
                    NativePreferenceField.stepper(
                        String(localized: "Switcher Icon Size"), \.windowSwitcherIconSize,
                        range: Double(iconSizes.lowerBound)...Double(iconSizes.upperBound), format: .points),
                    NativePreferenceField.toggle(
                        String(localized: "Enable Switcher Preview"),
                        description: String(localized: "Shows the selected window behind the switcher."),
                        \.showsWindowSwitcherFocusPreview),
                    NativePreferenceField.choice(
                        String(localized: "Preview Mode"), \.windowSwitcherPreviewMode,
                        values: WindowSwitcherPreviewMode.allCases, name: \.title
                    ).describing { preferences().windowSwitcherPreviewMode.summary }
                        .enabled(when: { preferences().showsWindowSwitcherFocusPreview })
                ]
            ).enablingRows(when: switcherOn),
            NativeSettingsSection(
                String(localized: "Action Keys"),
                footer: String(
                    localized:
                        "Keys that act on the selected window while the switcher is open. Tab, the arrow keys, Escape, and Return keep their usual roles."),
                rows: [
                    NativePreferenceField.key(String(localized: "Close Window"), \.switcherCloseKeyCode),
                    NativePreferenceField.key(String(localized: "Minimize Window"), \.switcherMinimizeKeyCode),
                    NativePreferenceField.key(String(localized: "Zoom Window"), \.switcherZoomKeyCode)
                ]
            ).enablingRows(when: switcherOn),
            NativeSettingsSection(
                String(localized: "Window Preview"),
                rows: [
                    NativePreferenceField.slider(
                        String(localized: "Hover Delay"),
                        description: String(
                            localized:
                                "How long to wait before the per-tile window preview appears when hovering an app or app folder."),
                        \.windowPreviewHoverDelay, range: 0...2, step: 0.05, format: .seconds)
                ])
        ]
    }
}

extension NativeSettingsSection {
    /// Disables every row while `condition` is false. A row with its own
    /// condition stays disabled while either is false.
    @discardableResult
    func enablingRows(when condition: @escaping @MainActor () -> Bool) -> Self {
        observe { [weak self] in self?.rowsEnabled = condition() }
        return self
    }
}
