import AppKit

extension NativeSettingsContent {
    static func taskbarSections(_ context: NativeSettingsContext) -> [NativeSettingsSection] {
        let heights = WindowsTaskbarMetrics.heightRange
        let reset = NativeActionButton(String(localized: "Reset Taskbar Settings…")) {
            Task {
                guard
                    await context.sheets.confirm(
                        String(localized: "Reset the taskbar settings to their defaults?"),
                        informativeText: String(
                            localized:
                                "The taskbar's size, position, auto-hide, app, app folder, and shelve mode settings are reset. Profiles, app icons, and hidden apps don't change."),
                        confirmTitle: String(localized: "Reset"))
                else { return }
                DockyPreferences.shared.resetTaskbarToDefaults()
            }
        }
        return [
            NativeSettingsSection(rows: [
                NativePreferenceField.stepper(
                    String(localized: "Taskbar Size"), \.windowsTaskbarHeight,
                    range: Double(heights.lowerBound)...Double(heights.upperBound), format: .points)
            ]),
            positionSection(),
            autoHideSection(),
            taskbarAppsSection(),
            appFoldersSection(),
            shelveSection(),
            NativeSettingsSection(actions: [reset])
        ]
    }

    private static func positionSection() -> NativeSettingsSection {
        NativeSettingsSection(
            String(localized: "Position"),
            rows: [
                NativePreferenceField.choice(
                    String(localized: "Display"),
                    description: String(
                        localized:
                            "Choose whether the taskbar stays on the primary display or follows the display with the pointer."),
                    \.windowDisplayTarget, values: DockWindowDisplayTarget.allCases, name: \.title),
                // `effectiveWindowPosition` keeps the taskbar at the bottom until it lays out vertically.
                NativePreferenceField.choice(
                    String(localized: "Screen Edge"),
                    description: String(localized: "The taskbar stays at the bottom of the screen for now."),
                    \.windowPosition, values: DockWindowPosition.allCases, name: \.title
                ).enabled(when: { false }),
                NativePreferenceField.choice(
                    String(localized: "Spaces"),
                    description: String(
                        localized: "Choose whether the taskbar appears only in the active Space or in every Space."),
                    \.windowSpaceBehavior, values: DockWindowSpaceBehavior.allCases, name: \.title)
            ])
    }

    private static func autoHideSection() -> NativeSettingsSection {
        NativeSettingsSection(
            String(localized: "Auto-Hide"),
            rows: [
                NativePreferenceField.toggle(
                    String(localized: "Automatically Hide the Taskbar"),
                    description: String(localized: "The taskbar slides off-screen until the pointer reaches its edge."),
                    \.autohidesWindow),
                NativePreferenceField.slider(
                    String(localized: "Autohide Delay"),
                    description: String(localized: "How long the taskbar waits after the pointer leaves before it hides."),
                    \.autohideWindowDelay, range: 0...5, step: 0.05, format: .seconds
                ).enabled(when: { DockyPreferences.shared.autohidesWindow }),
                NativePreferenceField.slider(
                    String(localized: "Fullscreen Reveal Delay"),
                    description: String(
                        localized:
                            "How long the pointer must rest at the screen edge before the taskbar appears over a fullscreen app."),
                    \.fullscreenRevealDelay, range: 0...2, step: 0.05, format: .seconds)
            ])
    }

    private static func shelveSection() -> NativeSettingsSection {
        let isShelved: @MainActor () -> Bool = { DockyPreferences.shared.enablesShelveMode }
        return NativeSettingsSection(
            String(localized: "Shelve Mode"),
            rows: [
                NativePreferenceField.toggle(
                    String(localized: "Shelve Mode"),
                    description: String(
                        localized: "Treats the taskbar as a shelf for pinned apps and widgets, and can hide Finder and the Trash."),
                    \.enablesShelveMode),
                NativePreferenceField.toggle(String(localized: "Hide Finder"), \.shelveHidesFinder)
                    .enabled(when: isShelved),
                NativePreferenceField.toggle(String(localized: "Hide Trash"), \.shelveHidesTrash)
                    .enabled(when: isShelved)
            ])
    }
}
