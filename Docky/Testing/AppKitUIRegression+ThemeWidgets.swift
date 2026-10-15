#if DEBUG
    import AppKit
    import Combine

    extension AppKitUIRegression {
        static func checkThemeWidgetRemoval() async {
            let suite = RegressionDefaults("docky.theme-widget-regression")
            defer { suite.remove() }
            let defaults = suite.defaults
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("docky.theme-widget-regression." + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let fixture = directory.appendingPathComponent("fixture-search")
            do {
                try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
            } catch { preconditionFailure("Cannot create fixture: \(error)") }
            let json = """
                {"schemaVersion":1,"id":"fixture-search","name":"Search fixture","appearance":{},
                 "layout":{"insertions":[{"kind":"search","span":4,"after":"pinned:com.apple.finder"},
                                         {"kind":"flexibleSpacer","after":"divider:trailing"}]}}
                """
            do {
                try Data(json.utf8).write(to: fixture.appendingPathComponent("theme.json"))
            } catch { preconditionFailure("Cannot write fixture: \(error)") }
            let manager = ThemeManager(defaults: defaults, directoryURL: directory)
            manager.setActive("fixture-search")
            precondition(manager.activeThemeID == "fixture-search", "Isolated fixture theme required")
            let base = [
                Tile(id: "pinned:com.apple.finder", content: .app(
                    AppTile(bundleIdentifier: "com.apple.finder", displayName: "Finder"))),
                Tile(id: "widget:user-search", content: .widget(WidgetCatalog.search.makeTile())),
                Tile(id: "divider:trailing", content: .divider)
            ]
            func displayedTiles(_ themeManager: ThemeManager) -> [Tile] {
                TileStore.applyingThemeLayoutInsertions(to: base, themeManager: themeManager)
            }
            let original = displayedTiles(manager)
            guard let search = original.first(where: { $0.id == "theme:insert:0:search" }),
                  case .widget(let widget) = search.content else {
                preconditionFailure("Theme Search widget required")
            }
            var visibleIDs: [String] = []
            let observation = observeChanges { visibleIDs = displayedTiles(manager).map(\.id) }
            defer { observation.cancel() }
            var interaction = DockTileInteraction(
                tile: search, isDragging: false, isDocumentDropTarget: false,
                isAppFolderDropTarget: false, isTrashDropTarget: false)
            interaction.themeManager = manager
            let actions = interaction.searchWidgetActions(widget)
            guard let removal = actions.first(where: { $0.title == "Remove Widget" }) else {
                preconditionFailure("Search context menu must offer removal")
            }
            removal.handler()
            let deadline = ContinuousClock.now.advanced(by: .seconds(1))
            while visibleIDs.contains(search.id) {
                precondition(ContinuousClock.now < deadline, "Removal must refresh the observed layout")
                await Task.yield()
            }
            precondition(displayedTiles(manager) == original.filter { $0.id != search.id },
                "Removal must preserve user widgets and structural theme tiles")
            removal.handler()
            precondition(manager.removedLayoutInsertionIDsByTheme["fixture-search"] == [search.id],
                "Repeated removal must be idempotent")
            manager.removeLayoutInsertion(tileID: "widget:user-search", themeID: "fixture-search")
            precondition(manager.removedLayoutInsertionIDsByTheme["fixture-search"] == [search.id])
            checkThemeWidgetPersistence(
                manager: manager, defaults: defaults, base: base, original: original, search: search)
            print("Theme widget removal regression passed")
        }

        private static func checkThemeWidgetPersistence(
            manager: ThemeManager, defaults: UserDefaults, base: [Tile], original: [Tile], search: Tile
        ) {
            func displayedTiles(_ themeManager: ThemeManager) -> [Tile] {
                TileStore.applyingThemeLayoutInsertions(to: base, themeManager: themeManager)
            }
            manager.setActive("snow-leopard")
            precondition(manager.activeThemeID == "snow-leopard")
            precondition(manager.removedLayoutInsertionIDsByTheme["snow-leopard"] == nil,
                "Removal choices must be scoped to their theme")
            manager.clearActive()
            precondition(displayedTiles(manager) == base)
            manager.setActive("fixture-search")
            precondition(!displayedTiles(manager).contains { $0.id == search.id },
                "Switching themes must preserve removal choices")
            let restored = ThemeManager(defaults: defaults, directoryURL: manager.themesDirectoryURL)
            precondition(restored.activeThemeID == "fixture-search")
            precondition(displayedTiles(restored) == original.filter { $0.id != search.id },
                "Removed theme widgets must stay removed after relaunch")
        }
    }
#endif
