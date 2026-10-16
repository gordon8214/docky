import AppKit

extension NativeSettingsContent {
    static func taskbarAppsSection() -> NativeSettingsSection {
        let preferences = { DockyPreferences.shared }
        return NativeSettingsSection(
            String(localized: "Apps"),
            rows: [
                NativePreferenceField.toggle(
                    String(localized: "Show Running Apps"),
                    description: String(localized: "Shows apps that are open but not pinned."),
                    \.showsRunningApps),
                NativePreferenceField.toggle(
                    String(localized: "Show Recently Quit App"),
                    description: String(
                        localized: "If the most recently opened app quits, its button stays until another app opens."),
                    get: { !preferences().hidesRecentApps }, set: { preferences().hidesRecentApps = !$0 }
                ).enabled(when: { preferences().showsRunningApps }),
                NativePreferenceField.toggle(
                    String(localized: "Show Minimized Windows"),
                    description: String(localized: "Lists each minimized window in the taskbar's overflow menu."),
                    \.showsMinimizedWindows),
                NativePreferenceField.toggle(
                    String(localized: "Show Notification Badges"),
                    description: String(
                        localized: "Shows counts like Mail's unread total on app buttons. Needs Accessibility access."),
                    \.showsAppBadges),
                NativePreferenceField.choice(
                    String(localized: "When App Is Already Active"),
                    description: String(
                        localized:
                            "Choose what happens when you click the tile of an app that already has the focus. Clicking idle apps always launches, focuses, or restores their last minimized window."),
                    \.appTileFrontmostClickBehavior, values: AppTileFrontmostClickBehavior.allCases, name: \.title)
            ])
    }

    static func appFoldersSection() -> NativeSettingsSection {
        let preferences = { DockyPreferences.shared }
        return NativeSettingsSection(
            String(localized: "App Folders"),
            rows: [
                NativePreferenceField.toggle(
                    String(localized: "Group Open Apps with Their Folder"),
                    description: String(
                        localized:
                            "Shows an app folder's open apps together on the taskbar, and lets the folder show how many are open."),
                    \.showsGroupedOpenedAppsInDock),
                NativePreferenceField.choice(
                    String(localized: "Folder Badges"),
                    description: String(
                        localized: "One combined total on the folder, or a badge on each app inside it."),
                    \.folderBadgeMode, values: FolderBadgeMode.allCases, name: \.title
                ).enabled(when: { preferences().showsAppBadges }),
                NativePreferenceField.choice(
                    String(localized: "Per-App Badge Style"),
                    description: String(
                        localized: "On the folder's preview, a dot or the full count on each badged app."),
                    \.folderBadgePreviewStyle, values: FolderBadgePreviewStyle.allCases, name: \.title
                ).enabled(when: { preferences().showsAppBadges && preferences().folderBadgeMode == .perApp })
            ])
    }
}
