import AppKit

extension NativeSettingsContent {
    static func startMenuSections() -> [NativeSettingsSection] {
        [
            NativeSettingsSection(
                String(localized: "Availability"),
                rows: [
                    NativePreferenceField.toggle(
                        String(localized: "Enable Start Menu"),
                        description: String(
                            localized:
                                "Lets the Start button open Docky's Start menu. Press ⌃⌥S to open it from anywhere."),
                        \.enablesStartMenuOverlay)
                ]),
            NativeSettingsSection(
                String(localized: "Finder Tile"),
                rows: [
                    NativePreferenceField.toggle(
                        String(localized: "Open Start Menu from Finder Tile"),
                        description: String(
                            localized:
                                "When on, clicking the Finder tile opens the Start menu instead of activating Finder. Right-click still surfaces Finder's normal actions."),
                        \.opensStartMenuFromFinderTile
                    ).enabled(when: { DockyPreferences.shared.enablesStartMenuOverlay })
                ])
        ]
    }
}
