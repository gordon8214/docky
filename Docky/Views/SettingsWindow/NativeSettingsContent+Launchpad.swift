import AppKit

extension NativeSettingsContent {
    /// The Launchpad inspector floats over the grid to tune its look, so it
    /// leaves out Availability and the taskbar tile.
    static func launchpadSections(_ context: NativeSettingsContext) -> [NativeSettingsSection] {
        let preferences = { DockyPreferences.shared }
        let inSettings = context.placement == .settingsWindow
        var sections: [NativeSettingsSection] = []
        if inSettings {
            sections.append(
                NativeSettingsSection(
                    String(localized: "Availability"),
                    rows: [
                        NativePreferenceField.toggle(
                            String(localized: "Enable Launchpad"),
                            description: String(
                                localized:
                                    "Turn Docky's Launchpad overlay on or off without removing its shortcut or layout preferences."),
                            \.enablesLaunchpadOverlay)
                    ]))
        }
        sections.append(
            NativeSettingsSection(
                String(localized: "Shortcut"),
                rows: [
                    NativePreferenceField.shortcut(
                        String(localized: "Global Shortcut"),
                        description: String(
                            localized:
                                "Optionally assign a global shortcut that toggles Docky's Launchpad overlay from anywhere."),
                        \.launchpadShortcut)
                ]))
        sections.append(
            NativeSettingsSection(
                String(localized: "Layout"),
                rows: [
                    NativePreferenceField.choice(
                        String(localized: "Scroll Direction"), \.launchpadLayoutAxis,
                        values: LaunchpadLayoutAxis.allCases, name: \.title
                    ).describing { preferences().launchpadLayoutAxis.summary },
                    NativePreferenceField.stepper(
                        String(localized: "Grid Columns"), \.launchpadGridColumnCount, range: 1...12),
                    NativePreferenceField.stepper(String(localized: "Grid Rows"), \.launchpadGridRowCount, range: 1...10)
                        .enabled(when: { preferences().launchpadLayoutAxis == .horizontal }),
                    NativePreferenceField.slider(
                        String(localized: "Icon Size"),
                        description: String(localized: "The largest icon size. Smaller screens scale it down."),
                        \.launchpadBaseIconSize, range: 48...192, step: 1, format: .points),
                    NativePreferenceField.slider(
                        String(localized: "Column Spacing"), \.launchpadColumnSpacing, range: 0...96, step: 1,
                        format: .points)
                ]))
        sections.append(
            NativeSettingsSection(
                String(localized: "Appearance"),
                rows: [
                    NativePreferenceField.slider(
                        String(localized: "Transparency"), \.launchpadOverlayTransparency, range: 0...1, step: 0.01,
                        format: .percent),
                    NativePreferenceField.image(
                        String(localized: "Background Image"),
                        description: String(localized: "When none is chosen, Launchpad shows your desktop picture."),
                        \.launchpadBackgroundImagePath, sheets: context.sheets),
                    NativePreferenceField.toggle(
                        String(localized: "Blur Background Image"), \.launchpadBackgroundBlursImage)
                ]))
        if inSettings {
            sections.append(
                NativeSettingsSection(
                    String(localized: "Taskbar Tile"),
                    rows: [
                        NativePreferenceField.image(
                            String(localized: "Launchpad Icon"),
                            description: String(localized: "Replaces the Launchpad tile's icon."),
                            \.launchpadIconPath, sheets: context.sheets),
                        // The tile pads its icon whether or not it's a custom image.
                        NativePreferenceField.slider(
                            String(localized: "Padding"),
                            get: { Double(preferences().launchpadIconPaddingFraction ?? 0) },
                            set: { preferences().launchpadIconPaddingFraction = $0 == 0 ? nil : CGFloat($0) },
                            range: 0...0.5, step: 0.01, format: .percent)
                    ]))
        }
        return sections
    }
}
