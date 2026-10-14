import AppKit
import Combine
import UniformTypeIdentifiers

/// The table virtualizes installed apps; only the selected icon has editing controls.
final class NativeIconSettingsController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    enum IconTarget: Equatable {
        case app(String)
        case folder(String)
        case trash(TrashIconState)
    }
    struct Item {
        let title: String
        let target: IconTarget
    }
    private var items: [Item] = []
    private let common = NSStackView()
    private let editor = NSStackView()
    private let scroll = NSScrollView()
    private let table = NSTableView()
    private var subscriptions = Set<AnyCancellable>()
    override func loadView() {
        view = NSView()
        common.orientation = .vertical
        common.alignment = .leading
        common.spacing = 12
        common.addArrangedSubview(nativeLabel(String(localized: "App Icons"), size: 22, weight: .semibold))
        for row in NativeSettingsFields.rows(for: "appIcons") { common.addArrangedSubview(row) }
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("icon")))
        table.headerView = nil
        table.rowHeight = 28
        table.dataSource = self
        table.delegate = self
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        editor.orientation = .vertical
        editor.alignment = .leading
        editor.spacing = 12
        for child in [common, scroll, editor] { view.addSubview(child) }
        reloadItems()
        for publisher in [
            WorkspaceService.shared.objectWillChange.eraseToAnyPublisher(),
            TileStore.shared.objectWillChange.eraseToAnyPublisher(),
            LaunchpadOverlayService.shared.objectWillChange.eraseToAnyPublisher()
        ] {
            publisher.sink { [weak self] in DispatchQueue.main.async { self?.reloadItems() } }
                .store(in: &subscriptions)
        }
        observeChanges { [weak self] in
            _ = DockyPreferences.shared.appIconOverrides
            _ = DockyPreferences.shared.pinnedItems
            _ = DockyPreferences.shared.widgetPlacements
            self?.reloadItems()
        }.store(in: &subscriptions)
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        let width = max(0, view.bounds.width - 40)
        let commonHeight = common.fittingSize.height
        let editorHeight: CGFloat = 120
        common.frame = CGRect(x: 20, y: view.bounds.height - commonHeight - 20, width: width, height: commonHeight)
        editor.frame = CGRect(x: 20, y: 20, width: width, height: editorHeight)
        scroll.frame = CGRect(
            x: 20, y: editorHeight + 36, width: width,
            height: max(60, view.bounds.height - commonHeight - editorHeight - 72))
        table.frame.size.width = scroll.contentSize.width
    }
    private func reloadItems() {
        let selectedTarget = items.indices.contains(table.selectedRow) ? items[table.selectedRow].target : nil
        items = [
            Item(title: String(localized: "Empty Trash"), target: .trash(.empty)),
            Item(title: String(localized: "Full Trash"), target: .trash(.full))
        ]
        items += TileStore.shared.tiles.compactMap { tile in
            guard case .folder(let folder) = tile.content else { return nil }
            return Item(title: folder.displayName, target: .folder(folder.url.path))
        }
        var apps = LaunchpadOverlayService.shared.entries.flatMap { entry -> [AppTile] in
            switch entry {
            case .app(let app): return [app]
            case .folder(let folder): return folder.apps
            }
        }
        apps += WorkspaceService.shared.runningApps.map {
            AppTile(bundleIdentifier: $0.bundleIdentifier, displayName: $0.localizedName)
        }
        let preferences = DockyPreferences.shared
        var identifiers: Set<String> = ["com.apple.finder"]
        identifiers.formUnion(preferences.appIconOverrides.map(\.bundleIdentifier))
        identifiers.formUnion(preferences.widgetPlacements.map(\.ownerBundleIdentifier))
        for item in preferences.pinnedItems {
            if let identifier = item.bundleIdentifier { identifiers.insert(identifier) }
            identifiers.formUnion(item.folderBundleIdentifiers)
        }
        apps += identifiers.map { identifier in
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
            return AppTile(
                bundleIdentifier: identifier,
                displayName: url.map { FileManager.default.displayName(atPath: $0.path) } ?? identifier)
        }
        var seen = Set<String>()
        items += apps.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            .filter { seen.insert($0.bundleIdentifier).inserted }
            .map { Item(title: $0.displayName, target: .app($0.bundleIdentifier)) }
        table.reloadData()
        let selection = selectedTarget.flatMap { target in items.firstIndex { $0.target == target } } ?? 0
        table.selectRowIndexes(IndexSet(integer: selection), byExtendingSelection: false)
        updateEditor()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        nativeLabel(items[row].title)
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateEditor() }
    private func updateEditor() {
        for child in editor.arrangedSubviews {
            editor.removeArrangedSubview(child)
            child.removeFromSuperview()
        }
        guard items.indices.contains(table.selectedRow) else { return }
        let item = items[table.selectedRow]
        let target = item.target
        editor.addArrangedSubview(nativeLabel(item.title, weight: .semibold))
        editor.addArrangedSubview(iconButtons(for: target))
        editor.addArrangedSubview(paddingControl(for: target))
        view.needsLayout = true
    }
    private func iconButtons(for target: IconTarget) -> NSView {
        let preferences = DockyPreferences.shared
        return nativeStack(
            [
                NativeActionButton(String(localized: "Choose Image…")) {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.image]
                    guard panel.runModal() == .OK, let path = panel.url?.path else { return }
                    switch target {
                    case .app(let identifier):
                        preferences.setAppIconOverride(bundleIdentifier: identifier, iconPath: path)
                    case .folder(let pathKey):
                        preferences.setFolderIconOverride(folderPath: pathKey, iconPath: path)
                    case .trash(let state): preferences.setTrashIconOverride(state: state, iconPath: path)
                    }
                },
                NativeActionButton(String(localized: "Clear")) {
                    switch target {
                    case .app(let identifier): preferences.removeAppIconOverride(bundleIdentifier: identifier)
                    case .folder(let pathKey): preferences.removeFolderIconOverride(folderPath: pathKey)
                    case .trash(let state): preferences.removeTrashIconOverride(state: state)
                    }
                }
            ], orientation: .horizontal)
    }
    private func paddingControl(for target: IconTarget) -> NSView {
        let preferences = DockyPreferences.shared
        return NativePreferenceField.number(
            String(localized: "Padding"),
            get: {
                switch target {
                case .app(let identifier):
                    return Double(preferences.appIconOverridePadding(forBundleIdentifier: identifier))
                case .folder(let pathKey): return Double(preferences.folderIconOverridePadding(forPath: pathKey))
                case .trash(let state): return Double(preferences.trashIconOverridePadding(forState: state))
                }
            },
            set: { value in
                switch target {
                case .app(let identifier):
                    preferences.setAppIconPaddingFraction(
                        bundleIdentifier: identifier, paddingFraction: CGFloat(value))
                case .folder(let pathKey):
                    preferences.setFolderIconPaddingFraction(folderPath: pathKey, paddingFraction: CGFloat(value))
                case .trash(let state):
                    preferences.setTrashIconPaddingFraction(state: state, paddingFraction: CGFloat(value))
                }
            }, range: 0...0.5)
    }

}
