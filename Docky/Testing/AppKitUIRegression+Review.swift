#if DEBUG
    import AppKit

    extension AppKitUIRegression {
        static func checkLaunchpadEditing() {
            let suite = "docky.review-regression." + UUID().uuidString
            guard let defaults = UserDefaults(suiteName: suite) else {
                preconditionFailure("Isolated defaults required")
            }
            defer { defaults.removePersistentDomain(forName: suite) }
            let service = LaunchpadLayoutService(defaults: defaults)
            service.seedIfEmpty([.app(bundleID: "A"), .app(bundleID: "B"), .app(bundleID: "C"), .app(bundleID: "D")])
            let controller = NativeLaunchpadController(layoutService: service)
            _ = controller.view
            func showItems() {
                controller.setItems(service.layout.items.map {
                    NativeBrowserItem(id: $0.id, title: $0.id, activate: {})
                })
            }
            showItems()
            precondition(controller.applyDrop(id: "app:A", at: 2, operation: .before))
            precondition(service.layout.items.map(\.id) == ["app:B", "app:A", "app:C", "app:D"])
            showItems()
            precondition(controller.applyDrop(id: "app:D", at: 0, operation: .before))
            precondition(service.layout.items.first?.id == "app:D")
            showItems()
            precondition(controller.applyDrop(id: "app:D", at: 4, operation: .before))
            precondition(service.layout.items.last?.id == "app:D")
            guard let folderID = service.createFolder(merging: "A", intoSlotOf: "B", name: "Folder") else {
                preconditionFailure("Fixture folder required")
            }
            let folder = AppFolderTile(identifier: "virtual:" + folderID, displayName: "Folder", apps: [])
            let item = controller.folderItem(folder)
            precondition(item.id == "folder:" + folderID)
            showItems()
            let target = controller.displayed.firstIndex(where: { $0.id == item.id }) ?? -1
            precondition(controller.applyDrop(id: "app:C", at: target, operation: .on))
            precondition(service.folder(withID: folderID)?.bundleIDs == ["B", "A", "C"])
            precondition(service.allReferencedBundleIDs == ["A", "B", "C", "D"],
                "A folder drop must preserve every app")
            controller.folder = folder
            precondition(controller.applyDrop(id: "app:B", at: 3, operation: .before))
            precondition(service.folder(withID: folderID)?.bundleIDs == ["A", "C", "B"])
            item.actions.first(where: { $0.title == String(localized: "Ungroup") })?.handler()
            precondition(service.folder(withID: folderID) == nil)
            precondition(service.allReferencedBundleIDs == ["A", "B", "C", "D"])
        }
        static func checkLaunchpadKeyboard() {
            let controller = NativeLaunchpadController()
            _ = controller.view
            controller.setItems((0..<18).map { NativeBrowserItem(id: String($0), title: String($0), activate: {}) })
            guard let grid = controller.collection.collectionViewLayout as? NativeLaunchpadGridLayout else {
                preconditionFailure("Launchpad grid required")
            }
            grid.columns = 3
            grid.rows = 2
            controller.selectionID = "1"
            let editor = NSTextView()
            func send(_ selector: Selector) {
                precondition(controller.control(controller.search, textView: editor, doCommandBy: selector))
            }
            send(#selector(NSResponder.moveDown(_:)))
            precondition(controller.selectionID == "4")
            send(#selector(NSResponder.moveLeft(_:)))
            precondition(controller.selectionID == "3")
            send(#selector(NSResponder.pageDown(_:)))
            precondition(controller.selectionID == "9")
            send(#selector(NSResponder.moveToEndOfDocument(_:)))
            precondition(controller.selectionID == "17")
            send(#selector(NSResponder.moveToBeginningOfDocument(_:)))
            precondition(controller.selectionID == "0")
        }
        static func checkFolderLifecycle() {
            let url = FileManager.default.temporaryDirectory
            let folder = FolderTile(url: url, displayName: "Test", displayMode: .folder, sortMode: .name)
            let controller = NativeFolderController(folder: folder, appFolder: nil, tileID: "test.folder")
            _ = controller.view
            controller.viewDidAppear()
            precondition(controller.watchedURL == url)
            controller.viewWillDisappear()
            controller.refresh() // Simulate an already-queued callback after dismissal.
            precondition(!controller.presentationActive && controller.watchedURL == nil)
            let item = controller.fileItem(url.appendingPathComponent("test.txt"))
            let titles = item.actionsProvider?([]).map(\.title) ?? []
            for title in ["Open With", "Copy", "Move to Trash", "Quick Look"] {
                precondition(titles.contains(NSLocalizedString(title, comment: "")))
            }
            controller.cancelPreviewLoading()
        }
        static func checkWidgetDetails() {
            let now = Calendar.autoupdatingCurrent.startOfDay(for: Date()).addingTimeInterval(3600)
            let tomorrow = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: now) ?? now
            let event = CalendarEventSnapshot(
                title: "Tomorrow's Meeting", startDate: tomorrow, endDate: tomorrow.addingTimeInterval(3600),
                isAllDay: false, location: "", calendarTitle: "Test", color: .systemBlue, quickJoinURL: nil)
            let widget = NativeWidgetView(tile: WidgetCatalog.calendar.makeTile(), cornerRadius: 8, span: .three)
            widget.clear()
            widget.calendarEventsContent([event], now: now)
            let labels = widget.stack.arrangedSubviews.compactMap { ($0 as? NSTextField)?.stringValue }
            precondition(labels.first?.contains(String(localized: "Tomorrow")) == true)
            let expanded = NativeWidgetView(
                tile: WidgetCatalog.calendar.makeTile(), cornerRadius: 8, span: .three, expanded: true)
            expanded.clear()
            expanded.calendarEventsContent([event], now: now)
            let agenda = expanded.stack.arrangedSubviews.compactMap { ($0 as? NSTextField)?.stringValue }
            precondition(agenda.first == String(localized: "Tomorrow"))
            precondition(agenda.contains(where: { $0.contains(" – ") }), "Agenda includes end times")
            widget.clear()
            widget.permission("Calendar", for: .calendar, status: .denied) {
                preconditionFailure("Denied access cannot re-prompt")
            }
            precondition((widget.stack.arrangedSubviews.last as? NSButton)?.title == String(localized: "Open Settings"))
            checkWidgetReuse()
            precondition(NativeDockTileView.badgeDisplayText("1234") == "999+")
            precondition(NativeDockTileView.badgeDisplayText("Long Status") == "Long")
        }
        private static func checkWidgetReuse() {
            var tile = WidgetCatalog.genericNowPlaying.makeTile()
            tile = WidgetTile(identifier: tile.identifier, title: tile.title, kind: tile.kind,
                ownerBundleIdentifier: "test.concrete.media", span: tile.span)
            let widget = NativeWidgetView(tile: tile, cornerRadius: 8, span: .three)
            precondition(widget.mediaBundleIdentifier == "test.concrete.media")
            widget.tile.settings["nowPlaying.appBundleIdentifier"] = .string("")
            precondition(widget.mediaBundleIdentifier == "test.concrete.media")
            widget.tile.settings["nowPlaying.appBundleIdentifier"] = .string("test.selected.media")
            precondition(widget.mediaBundleIdentifier == "test.selected.media")
            let view = NativeDockTileView(tile: Tile(content: .widget(tile)))
            let retained = view.content
            retained?.layer?.cornerRadius = -1
            view.updateTileContent()
            precondition(view.content === retained, "Appearance updates retain widget controls")
            precondition(view.content?.layer?.cornerRadius == view.interaction.nonAppTileCornerRadius)
        }
        static func checkCachedSettings() async {
            let preferences = DockyPreferences.shared
            let previous = preferences.hiddenAppBundleIdentifiers
            defer { preferences.hiddenAppBundleIdentifiers = previous }
            let pane = NativeSettingsPaneController(id: "hiddenApps")
            _ = pane.view
            let identifier = "test.hidden.review." + UUID().uuidString
            preferences.hiddenAppBundleIdentifiers = previous + [identifier]
            await Task.yield()
            await Task.yield()
            func contains(_ view: NSView) -> Bool {
                if let label = view as? NSTextField, label.stringValue == identifier { return true }
                return view.subviews.contains(where: contains)
            }
            precondition(contains(pane.view), "Cached Hidden Apps pane observes external preference changes")
        }
    }
#endif
