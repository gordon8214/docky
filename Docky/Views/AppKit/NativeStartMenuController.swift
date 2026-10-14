import AppKit
import Combine

final class NativeStartMenuController: NSViewController {
    private let main = NativeBrowserController()
    private let allApps = NativeBrowserController()
    private let observations = NativeObservationSession()
    override func loadView() {
        view = NSView()
        addChild(main)
        addChild(allApps)
        view.addSubview(main.view)
        view.addSubview(allApps.view)
        main.usesList = true
        allApps.usesList = true
        main.header.addArrangedSubview(
            NativeActionButton(String(localized: "All Apps")) { StartMenuService.shared.showsAllApps.toggle() })
        main.header.addArrangedSubview(
            NativeActionButton(String(localized: "Settings"), symbol: "gearshape") {
                StartMenuService.shared.dismiss()
                (NSApp.delegate as? AppDelegate)?.showSettingsWindow(nil)
            })
        main.header.addArrangedSubview(
            NativeActionButton("", symbol: "power") { [weak self] in
                guard let self else { return }
                ContextActionMenuPresenter.popUpMenu(
                    actions: [SystemAction.sleep, .restart, .shutDown, .logOut].map { action in
                        .action(action.title) { action.perform() }
                    }, from: self.main.header)
            })
        main.onEscape = { StartMenuService.shared.dismiss() }
        allApps.onEscape = { StartMenuService.shared.showsAllApps = false }
        configureSearch()
        for publisher in [
            RecentFilesService.shared.objectWillChange.eraseToAnyPublisher(),
            RecentAppsService.shared.objectWillChange.eraseToAnyPublisher(),
            LaunchpadOverlayService.shared.objectWillChange.eraseToAnyPublisher(),
            StartMenuService.shared.objectWillChange.eraseToAnyPublisher()
        ] {
            observations.add { [weak self] in
                publisher.sink { [weak self] in DispatchQueue.main.async { self?.refresh() } }
            }
        }
        let observedPublisher1 = StartMenuService.shared.$isPresented
        observations.add { [weak self] in
            observedPublisher1.sink { [weak self] presented in
                guard presented, let self else { return }
                for browser in [self.main, self.allApps] {
                    browser.query = ""
                    browser.search.stringValue = ""
                    browser.selectionID = nil
                }
                self.refresh()
                self.view.window?.makeFirstResponder(self.main.search)
            }
        }
        refresh()
    }
    private func configureSearch() {
        main.onSearch = { [weak self] _ in self?.refresh() }
        allApps.onSearch = { [weak self] query in
            self?.main.query = query
            self?.main.search.stringValue = query
            self?.refresh()
        }
    }
    override func viewDidAppear() {
        super.viewDidAppear()
        observations.start()
        refresh()
    }
    override func viewDidDisappear() {
        super.viewDidDisappear()
        observations.stop()
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        main.view.frame = CGRect(x: 0, y: 0, width: min(440, view.bounds.width), height: view.bounds.height)
        allApps.view.frame = CGRect(x: 448, y: 0, width: max(0, view.bounds.width - 448), height: view.bounds.height)
    }
    private func refresh() {
        let apps: [AppTile] = LaunchpadOverlayService.shared.entries.flatMap { entry in
            switch entry {
            case .app(let app): return [app]
            case .folder(let folder): return folder.apps
            }
        }
        func appItem(_ app: AppTile) -> NativeBrowserItem {
            NativeBrowserItem(
                id: app.bundleIdentifier, title: app.displayName, detail: String(localized: "App"),
                image: IconCacheService.shared.icon(forBundleIdentifier: app.bundleIdentifier)
            ) {
                WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
                StartMenuService.shared.dismiss()
            }
        }
        allApps.query = main.query
        allApps.search.stringValue = main.query
        allApps.setItems(
            apps.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }.map(appItem))
        let recentApps = RecentAppsService.shared.recentBundleIdentifiers.prefix(8).compactMap { id in
            apps.first(where: { $0.bundleIdentifier == id })
        }
        var items = (main.query.isEmpty ? recentApps : apps).map(appItem)
        items += RecentFilesService.shared.recentURLs.map { url in
            NativeBrowserItem(
                id: url.path, title: FileManager.default.displayName(atPath: url.path),
                detail: String(localized: "Recent File"), image: main.filePreview(for: url),
                url: url, actions: [.share(url)]
            ) {
                NSWorkspace.shared.open(url)
                StartMenuService.shared.dismiss()
            }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        for name in ["Home", "Documents", "Downloads", "Desktop", "Pictures", "Movies", "Music", "Applications"] {
            let url =
                name == "Home"
                ? home
                : name == "Applications" ? URL(fileURLWithPath: "/Applications") : home.appendingPathComponent(name)
            items.append(
                NativeBrowserItem(
                    id: "shortcut:\(name)", title: name, detail: String(localized: "Folder"),
                    image: IconCacheService.shared.icon(forFileURL: url), url: url
                ) {
                    NSWorkspace.shared.open(url)
                    StartMenuService.shared.dismiss()
                })
        }
        main.setItems(items)
        allApps.view.isHidden = !StartMenuService.shared.showsAllApps
    }
}
