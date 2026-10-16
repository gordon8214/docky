#if DEBUG
    import AppKit

    /// The switcher's and the taskbar's Space scopes: which windows and apps
    /// each keeps, and their Settings rows.
    extension AppKitUIRegression {
        static func checkSpaceScopes() async {
            print("Checking Space scopes")
            fflush(stdout)
            precondition(SpaceScope.allSpaces.includes(windowOnActiveSpace: false),
                         "All Spaces keeps windows on other Spaces")
            precondition(!SpaceScope.activeSpace.includes(windowOnActiveSpace: false),
                         "Active Space drops windows on other Spaces")
            precondition(SpaceScope.activeSpace.includes(windowOnActiveSpace: true),
                         "Active Space keeps windows on a Space shown now")

            func countsAsOpen(_ scope: SpaceScope, _ openOnActiveSpace: Set<String>?) -> Bool {
                WorkspaceService.countsAsOpen(bundleIdentifier: "app", scope: scope, openOnActiveSpace: openOnActiveSpace)
            }
            precondition(countsAsOpen(.allSpaces, []), "All Spaces keeps apps with windows elsewhere")
            precondition(countsAsOpen(.activeSpace, ["app"]), "Active Space keeps apps open on a Space shown now")
            precondition(!countsAsOpen(.activeSpace, ["other"]), "Active Space drops apps open only elsewhere")
            precondition(countsAsOpen(.activeSpace, nil), "Without a window list, Active Space keeps every app")

            await checkSpaceScopeChoice(
                pane: .windowManagement, rowTitle: String(localized: "Show Windows From"),
                key: "docky.windowSwitcherSpaceScope", \.windowSwitcherSpaceScope)
            await checkSpaceScopeChoice(
                pane: .taskbar, rowTitle: String(localized: "Show Apps From"),
                key: "docky.taskbarSpaceScope", \.taskbarSpaceScope)
            await checkRecentlyQuitAppFollowsTaskbarScope()
        }

        /// A Space choice shows the stored value, writes the preference, and
        /// follows changes made elsewhere.
        private static func checkSpaceScopeChoice(
            pane settingsPane: SettingsPane,
            rowTitle: String,
            key: String,
            _ keyPath: ReferenceWritableKeyPath<DockyPreferences, SpaceScope>
        ) async {
            let preferences = DockyPreferences.shared
            let previous = preferences[keyPath: keyPath]
            let stored = UserDefaults.standard.object(forKey: key)
            // A failed precondition skips `defer`, so restore before failing
            // too; the installed app shares this defaults domain.
            func restore() {
                preferences[keyPath: keyPath] = previous
                if let stored { UserDefaults.standard.set(stored, forKey: key) } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
            func require(_ condition: Bool, _ message: String) {
                if !condition {
                    restore()
                    preconditionFailure("\(rowTitle): \(message)")
                }
            }
            defer { restore() }

            // Start from the non-default value, which the popup can't show by
            // falling back to its first item.
            preferences[keyPath: keyPath] = .activeSpace
            let pane = NativeSettingsPaneController(pane: settingsPane)
            _ = pane.view
            guard let popup = SettingsLookup.control(NSPopUpButton.self, inRow: rowTitle, in: pane.view) else {
                restore()
                preconditionFailure("\(settingsPane) must offer \(rowTitle)")
            }
            require(popup.itemTitles == SpaceScope.allCases.map(\.title), "The popup lists every scope")
            await waitUntil { popup.titleOfSelectedItem == SpaceScope.activeSpace.title }
            require(popup.titleOfSelectedItem == SpaceScope.activeSpace.title, "The popup shows the stored scope")

            popup.selectItem(withTitle: SpaceScope.allSpaces.title)
            popup.sendAction(popup.action, to: popup.target)
            require(preferences[keyPath: keyPath] == .allSpaces, "Choosing a scope saves it")
            require(UserDefaults.standard.string(forKey: key) == SpaceScope.allSpaces.rawValue, "The scope persists")

            // Let the observer re-track after the popup's own change.
            await Task.yield()
            preferences[keyPath: keyPath] = .activeSpace
            await waitUntil { popup.titleOfSelectedItem == SpaceScope.activeSpace.title }
            require(popup.titleOfSelectedItem == SpaceScope.activeSpace.title, "Preference changes update the popup")
        }

        /// Active Space never keeps a quit app's button, so the taskbar turns
        /// Show Recently Quit App off and says why.
        private static func checkRecentlyQuitAppFollowsTaskbarScope() async {
            let preferences = DockyPreferences.shared
            let keys = ["docky.taskbarSpaceScope", "docky.showsRunningApps"]
            let stored = keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
            let previousScope = preferences.taskbarSpaceScope
            let previousShowsRunningApps = preferences.showsRunningApps
            func restore() {
                preferences.taskbarSpaceScope = previousScope
                preferences.showsRunningApps = previousShowsRunningApps
                for (key, value) in stored {
                    if let value { UserDefaults.standard.set(value, forKey: key) } else {
                        UserDefaults.standard.removeObject(forKey: key)
                    }
                }
            }
            func require(_ condition: Bool, _ message: String) {
                if !condition {
                    restore()
                    preconditionFailure(message)
                }
            }
            defer { restore() }

            preferences.showsRunningApps = true
            preferences.taskbarSpaceScope = .activeSpace
            let pane = NativeSettingsPaneController(pane: .taskbar)
            _ = pane.view
            let title = String(localized: "Show Recently Quit App")
            guard let row = SettingsLookup.row(title, in: pane.view),
                  let toggle = SettingsLookup.control(NSSwitch.self, inRow: title, in: pane.view)
            else {
                restore()
                preconditionFailure("Taskbar must offer \(title)")
            }
            let activeSpaceNote = String(localized: "Off while Show Apps From is set to Active Space.")
            require(!toggle.isEnabled && toggle.state == .off, "Active Space turns Show Recently Quit App off")
            require(row.descriptionText == activeSpaceNote, "Show Recently Quit App says why it's off")

            preferences.taskbarSpaceScope = .allSpaces
            let storedState: NSControl.StateValue = preferences.hidesRecentApps ? .off : .on
            await waitUntil { toggle.isEnabled && toggle.state == storedState && row.descriptionText != activeSpaceNote }
            require(toggle.isEnabled, "All Spaces turns Show Recently Quit App back on")
            require(toggle.state == storedState, "All Spaces shows the stored Show Recently Quit App value")
            require(row.descriptionText != activeSpaceNote, "All Spaces restores its description")
        }

        /// Lets observers catch up, for a bounded number of main-actor turns.
        private static func waitUntil(_ condition: () -> Bool) async {
            for _ in 0..<50 where !condition() { await Task.yield() }
        }
    }
#endif
