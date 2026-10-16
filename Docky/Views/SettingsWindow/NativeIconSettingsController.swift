import AppKit
import Combine

/// App Icons: a searchable list of everything whose icon can be replaced, and
/// the selected item's icon settings beside it. The table creates cells only
/// for visible rows, since it lists every app Docky knows about.
final class NativeIconSettingsController: NSViewController, NSTableViewDataSource, NSTableViewDelegate,
    NSSearchFieldDelegate {
    enum IconTarget: Equatable {
        case app(String)
        case folder(String)
        case trash(TrashIconState)
    }
    struct Item: Equatable {
        let title: String
        let target: IconTarget
    }
    enum Row: Equatable {
        case group(String)
        case item(Item)
    }

    let table = NSTableView()
    let detail = NativeSettingsScrollView(style: .compact)
    lazy var sheets = NativeSheetPresenter(owner: self)
    private var items: [Item] = []
    private var rows: [Row] = []
    private let search = NSSearchField()
    private let tableScroll = NSScrollView()
    private var subscriptions = Set<AnyCancellable>()
    /// The item the editor was built for, so it isn't rebuilt (ending a slider
    /// drag) when the list reloads with the same selection.
    private var editorTarget: IconTarget?
    private var hasEditor = false
    /// Set when the items changed while the pane was hidden.
    private var needsReload = false
    private static let cellIdentifier = NSUserInterfaceItemIdentifier("AppIconCell")

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nil, bundle: nil)
        title = SettingsPane.appIcons.title
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView(frame: CGRect(x: 0, y: 0, width: 600, height: 480))
        search.placeholderString = String(localized: "Search")
        search.delegate = self
        search.translatesAutoresizingMaskIntoConstraints = false
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("icon")))
        table.headerView = nil
        table.style = .inset
        table.rowHeight = 28
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel(String(localized: "Icons"))
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true
        tableScroll.borderType = .noBorder
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        let list = NativeFormGroupBox()
        list.addSubview(tableScroll)
        detail.automaticallyAdjustsContentInsets = false
        for subview in [search, list, detail] { view.addSubview(subview) }
        let margin: CGFloat = 20
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: margin),
            search.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            search.widthAnchor.constraint(equalToConstant: 200),
            list.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 10),
            list.leadingAnchor.constraint(equalTo: search.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: search.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -margin),
            tableScroll.topAnchor.constraint(equalTo: list.topAnchor),
            tableScroll.leadingAnchor.constraint(equalTo: list.leadingAnchor),
            tableScroll.trailingAnchor.constraint(equalTo: list.trailingAnchor),
            tableScroll.bottomAnchor.constraint(equalTo: list.bottomAnchor),
            detail.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            detail.leadingAnchor.constraint(equalTo: list.trailingAnchor),
            detail.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            detail.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        for publisher in [
            WorkspaceService.shared.objectWillChange.eraseToAnyPublisher(),
            TileStore.shared.objectWillChange.eraseToAnyPublisher(),
            LaunchpadOverlayService.shared.objectWillChange.eraseToAnyPublisher()
        ] {
            // Coalesced, since these publish often, such as for every window thumbnail.
            publisher.debounce(for: .zero, scheduler: DispatchQueue.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.reloadItems() } }
                .store(in: &subscriptions)
        }
        // Only which items exist matters here; padding edits rewrite the overrides
        // without adding or removing any, so they don't reload the table.
        observeChanges(of: {
            let preferences = DockyPreferences.shared
            return [
                preferences.appIconOverrides.map(\.bundleIdentifier),
                preferences.pinnedItems.compactMap(\.bundleIdentifier) + preferences.pinnedItems.flatMap(\.folderBundleIdentifiers),
                preferences.widgetPlacements.map(\.ownerBundleIdentifier)
            ]
        }) { [weak self] _ in self?.reloadItems() }.store(in: &subscriptions)
    }

    private var selectedItem: Item? {
        guard rows.indices.contains(table.selectedRow), case .item(let item) = rows[table.selectedRow] else { return nil }
        return item
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        if needsReload { reloadItems() }
    }

    func reloadItems() {
        // A hidden pane catches up when it next appears.
        guard view.window != nil || rows.isEmpty else {
            needsReload = true
            return
        }
        needsReload = false
        let newItems = Self.currentItems()
        guard newItems != items || rows.isEmpty else { return }
        items = newItems
        reloadRows()
    }

    private func reloadRows() {
        let selected = selectedItem?.target
        let query = search.stringValue.trimmingCharacters(in: .whitespaces)
        let visible = query.isEmpty ? items : items.filter { $0.title.localizedStandardContains(query) }
        var newRows: [Row] = []
        let groups: [(String, (IconTarget) -> Bool)] = [
            (String(localized: "Trash"), { if case .trash = $0 { true } else { false } }),
            (String(localized: "Folders"), { if case .folder = $0 { true } else { false } }),
            (String(localized: "Apps"), { if case .app = $0 { true } else { false } })
        ]
        for (title, belongs) in groups {
            let members = visible.filter { belongs($0.target) }
            guard !members.isEmpty else { continue }
            newRows.append(.group(title))
            newRows += members.map(Row.item)
        }
        rows = newRows
        table.reloadData()
        let selection =
            rows.firstIndex { if case .item(let item) = $0 { item.target == selected } else { false } }
            ?? rows.firstIndex { if case .item = $0 { true } else { false } }
        if let selection {
            table.selectRowIndexes(IndexSet(integer: selection), byExtendingSelection: false)
        }
        showEditor()
    }

    private static func currentItems() -> [Item] {
        var items = [
            Item(title: String(localized: "Trash (Empty)"), target: .trash(.empty)),
            Item(title: String(localized: "Trash (Full)"), target: .trash(.full))
        ]
        items += TileStore.shared.tiles.compactMap { tile in
            guard case .folder(let folder) = tile.content else { return nil }
            return Item(title: folder.displayName, target: .folder(folder.url.path))
        }
        var apps = LaunchpadOverlayService.shared.entries.flatMap { entry -> [AppTile] in
            switch entry {
            case .app(let app): [app]
            case .folder(let folder): folder.apps
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
        return items
    }

    func controlTextDidChange(_ notification: Notification) { reloadRows() }

    /// The search field's clear button ends the search without a text change.
    func searchFieldDidEndSearching(_ sender: NSSearchField) { reloadRows() }

    /// Redraws `target`'s row, whose icon shows its custom image.
    func refreshIcon(for target: IconTarget) {
        guard let index = rows.firstIndex(where: { if case .item(let item) = $0 { item.target == target } else { false } })
        else { return }
        table.reloadData(forRowIndexes: IndexSet(integer: index), columnIndexes: IndexSet(integer: 0))
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .group = rows[row] { true } else { false }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .item = rows[row] { true } else { false }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .group(let title):
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            label.textColor = .secondaryLabelColor
            return label
        case .item(let item):
            let cell = tableView.makeView(withIdentifier: Self.cellIdentifier, owner: self) as? NSTableCellView
                ?? makeCell()
            cell.textField?.stringValue = item.title
            cell.imageView?.image = icon(for: item.target, size: 18)
            return cell
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) { showEditor() }

    private func makeCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = Self.cellIdentifier
        let image = NSImageView()
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail
        for view in [image, text] {
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(view)
        }
        cell.imageView = image
        cell.textField = text
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 18),
            image.heightAnchor.constraint(equalToConstant: 18),
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    private func showEditor() {
        let target = selectedItem?.target
        guard !hasEditor || target != editorTarget else { return }
        hasEditor = true
        editorTarget = target
        detail.form.setSections(selectedItem.map { editorSections(for: $0) } ?? [])
    }
}
