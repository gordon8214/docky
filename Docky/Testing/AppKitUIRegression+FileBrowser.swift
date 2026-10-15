#if DEBUG
    import AppKit

    extension AppKitUIRegression {
        /// Checks the BetterFinder reveal URL, then the Settings popup, the fallback to Finder and
        /// the catalog titles with BetterFinder both installed and missing.
        static func checkFileBrowser() async {
            checkBetterFinderRevealURL()

            let preferences = DockyPreferences.shared
            let key = "docky.fileBrowser"
            let previous = preferences.fileBrowser
            let stored = UserDefaults.standard.object(forKey: key)
            // A failed precondition skips `defer`, so restore before failing
            // too; the installed app shares this defaults domain.
            func restore() {
                FileBrowserService.installedOverride = nil
                preferences.fileBrowser = previous
                if let stored { UserDefaults.standard.set(stored, forKey: key) } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
            func require(_ condition: Bool, _ message: String) {
                if !condition {
                    restore()
                    preconditionFailure(message)
                }
            }
            defer { restore() }

            for betterFinderInstalled in [true, false] {
                FileBrowserService.installedOverride = { $0 == .finder || betterFinderInstalled }
                await checkFileBrowserChoice(betterFinderInstalled: betterFinderInstalled, key: key, require: require)
            }
        }

        private static func checkFileBrowserChoice(
            betterFinderInstalled: Bool, key: String, require: (Bool, String) -> Void
        ) async {
            let preferences = DockyPreferences.shared
            let browsers = FileBrowser.allCases
            let finderIndex = browsers.firstIndex(of: .finder) ?? 0
            let betterFinderIndex = browsers.firstIndex(of: .betterFinder) ?? 0
            let state = betterFinderInstalled ? "installed" : "missing"

            // Start from the non-default value, which the popup can't show by
            // falling back to its first item. The popup reads which apps are
            // installed when it's built, so each state gets a fresh pane.
            preferences.fileBrowser = .betterFinder
            let pane = NativeSettingsPaneController(id: "behaviorGeneral")
            _ = pane.view
            let label = String(localized: "File Browser")
            let popups = pane.stack.arrangedSubviews.compactMap { $0 as? NativeFormRow }
                .flatMap(\.arrangedSubviews).compactMap { $0 as? NSPopUpButton }
            guard let popup = popups.first(where: { $0.accessibilityLabel() == label }) else {
                require(false, "Behavior — General has a File Browser popup")
                return
            }
            func waitForSelection(_ index: Int) async {
                for _ in 0..<50 where popup.indexOfSelectedItem != index { await Task.yield() }
            }

            require(popup.numberOfItems == browsers.count, "The popup lists every file browser")
            require(popup.item(at: finderIndex)?.isEnabled == true, "Finder can always be chosen")
            require(
                popup.item(at: betterFinderIndex)?.isEnabled == betterFinderInstalled,
                "BetterFinder can be chosen only when it's installed (\(state))")
            let betterFinderTitle =
                betterFinderInstalled
                ? FileBrowser.betterFinder.displayName
                : String(
                    localized: "\(FileBrowser.betterFinder.displayName) (Not Installed)",
                    comment: "A file browser app's name, followed by a note that it isn't installed")
            require(popup.item(at: betterFinderIndex)?.title == betterFinderTitle, "BetterFinder's item title (\(state))")
            await waitForSelection(betterFinderIndex)
            require(popup.indexOfSelectedItem == betterFinderIndex, "The popup shows the stored file browser (\(state))")
            checkFileBrowserTitles(expected: betterFinderInstalled ? .betterFinder : .finder, require: require)

            popup.selectItem(at: finderIndex)
            popup.sendAction(popup.action, to: popup.target)
            require(preferences.fileBrowser == .finder, "Choosing Finder saves it")
            require(UserDefaults.standard.string(forKey: key) == FileBrowser.finder.rawValue, "The choice persists")
            checkFileBrowserTitles(expected: .finder, require: require)

            guard betterFinderInstalled else { return }
            // Let the observer re-track after the popup's own change.
            await Task.yield()
            popup.selectItem(at: betterFinderIndex)
            popup.sendAction(popup.action, to: popup.target)
            require(preferences.fileBrowser == .betterFinder, "Choosing BetterFinder saves it")
            require(UserDefaults.standard.string(forKey: key) == FileBrowser.betterFinder.rawValue, "The choice persists")
            checkFileBrowserTitles(expected: .betterFinder, require: require)
        }

        /// The catalog's folder and app menus name the file browser in use, with no token left over.
        private static func checkFileBrowserTitles(expected: FileBrowser, require: (Bool, String) -> Void) {
            require(FileBrowserService.shared.current == expected, "Actions go to \(expected.displayName)")
            func titles(_ actions: [ContextAction]) -> [String] {
                actions.flatMap { [$0.title] + titles($0.children) }
            }
            let folder = FolderTile(
                url: FileManager.default.temporaryDirectory, displayName: "Test", displayMode: .folder, sortMode: .name)
            let app = AppTile(bundleIdentifier: "com.apple.TextEdit", displayName: "TextEdit")
            let catalog = MenuCatalogService.shared
            let menuTitles = [Tile(content: .folder(folder)), Tile(content: .app(app)), Tile(content: .trash)]
                .flatMap { titles(catalog.contextActions(for: $0, modifierFlags: []) ?? []) }
            // Catalog titles aren't localized, so they compare in English in every locale.
            let name = expected.displayName
            require(
                ["Open in \(name)", "Reveal in \(name)", "Show in \(name)"].allSatisfy { menuTitles.contains($0) },
                "Menus name \(name): \(menuTitles)")
            require(!menuTitles.contains { $0.contains("{{") }, "Every catalog token is replaced: \(menuTitles)")
        }

        private static func checkBetterFinderRevealURL() {
            let paths = [
                "/tmp/plain", "/tmp/with space", "/tmp/a&b=c", "/tmp/hash#tag", "/tmp/plus+sign",
                "/tmp/100%", "/tmp/what?", "/tmp/café ☕️"
            ]
            for path in paths {
                guard let url = FileBrowser.betterFinderRevealURL(for: URL(fileURLWithPath: path)),
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let query = components.percentEncodedQuery
                else { preconditionFailure("No reveal URL for \(path)") }
                precondition(components.scheme == "betterfinder" && components.host == "reveal")
                precondition(components.path.isEmpty)
                precondition(
                    components.queryItems == [URLQueryItem(name: "path", value: path)],
                    "Reveal URL round-trips \(path): \(url.absoluteString)")
                // A parser that reads `+` as a space, or splits on `&`, `=` or `#`, still gets the path.
                let encodedPath = query.dropFirst("path=".count)
                precondition(
                    query.hasPrefix("path=") && !encodedPath.contains(where: { "&=+#".contains($0) }),
                    "Reveal URL escapes query separators in \(path): \(query)")
            }
            precondition(
                FileBrowser.betterFinderRevealURL(for: URL(fileURLWithPath: "/tmp/dir/../up"))
                    .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
                    == [URLQueryItem(name: "path", value: "/tmp/up")],
                "Reveal URLs carry the standardized path")
            precondition(
                URL(string: "https://example.com/tmp").flatMap(FileBrowser.betterFinderRevealURL) == nil,
                "Only file URLs can be revealed")
        }
    }
#endif
