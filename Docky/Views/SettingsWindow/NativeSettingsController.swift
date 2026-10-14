import AppKit
import Combine
import UniformTypeIdentifiers

final class NativeSettingsController: NSSplitViewController {
    static let panes: [(id: String, title: String)] = [
        ("profiles", "Profiles"), ("appearanceThemes", "Themes"), ("appearanceGeneral", "Appearance — General"),
        ("appearanceIndicators", "Indicators"), ("appearanceTileLayout", "Tile Layout"),
        ("appearanceWindowShape", "Window Shape"),
        ("appearanceWindowBackground", "Window Background"), ("appearanceWidgets", "Widget Appearance"),
        ("appIcons", "App Icons"),
        ("behaviorGeneral", "Behavior — General"), ("behaviorPlacement", "Placement"),
        ("behaviorVisibility", "Visibility"),
        ("behaviorAppTileClick", "App Tile Click"), ("behaviorAppFolders", "App Folders"),
        ("behaviorWidgets", "Widget Behavior"),
        ("hiddenApps", "Hidden Apps"), ("launchpad", "Launchpad"), ("startMenu", "Start Menu"),
        ("windowManagement", "Window Management"), ("actions", "Actions"), ("behaviorLaunch", "Launch"),
        ("behaviorSystemDock", "System Dock"), ("permissions", "Permissions"), ("updates", "Updates"),
        ("feedback", "Feedback")
    ]
    private let sidebar = NativeSettingsSidebarController()
    private var detail: NSSplitViewItem?
    private var navigationHistory = SettingsNavigationHistory()
    private var cache: [String: NSViewController] = [:]
    private var subscriptions = Set<AnyCancellable>()
    override func viewDidLoad() {
        super.viewDidLoad()
        let item = NSSplitViewItem(sidebarWithViewController: sidebar)
        item.minimumThickness = 180
        item.maximumThickness = 260
        addSplitViewItem(item)
        sidebar.onSelect = { [weak self] in self?.showPane($0) }
        sidebar.onBack = { [weak self] in self?.navigate(-1) }
        sidebar.onForward = { [weak self] in self?.navigate(1) }
        showPane("profiles")
        observeChanges { [weak self] in
            if let id = SettingsNavigator.shared.pendingPaneID {
                SettingsNavigator.shared.pendingPaneID = nil
                self?.showPane(id)
            }
        }.store(in: &subscriptions)
    }
    func showPane(_ id: String, addHistory: Bool = true) {
        guard Self.panes.contains(where: { $0.id == id }) else { return }
        if addHistory { navigationHistory.push(id) }
        if let detail { removeSplitViewItem(detail) }
        let controller =
            cache[id]
            ?? (id == "appIcons"
                ? NativeIconSettingsController() : NativeSettingsPaneController(id: id))
        cache[id] = controller
        let item = NSSplitViewItem(viewController: controller)
        item.minimumThickness = 460
        addSplitViewItem(item)
        detail = item
        sidebar.select(id)
    }
    private func navigate(_ delta: Int) {
        guard let paneID = navigationHistory.move(delta) else { return }
        showPane(paneID, addHistory: false)
    }

}

private final class NativeSettingsSidebarController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private var selectingProgrammatically = false
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let navigation = NSStackView()
    var onSelect: ((String) -> Void)?
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    override func loadView() {
        view = NSView()
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pane")))
        table.headerView = nil
        table.rowHeight = 30
        table.style = .sourceList
        table.dataSource = self
        table.delegate = self
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        navigation.orientation = .horizontal
        navigation.addArrangedSubview(NativeActionButton("", symbol: "chevron.left") { [weak self] in self?.onBack?() })
        navigation.addArrangedSubview(
            NativeActionButton("", symbol: "chevron.right") { [weak self] in self?.onForward?() })
        view.addSubview(scroll)
        view.addSubview(navigation)
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        scroll.frame = CGRect(x: 0, y: 42, width: view.bounds.width, height: max(0, view.bounds.height - 42))
        navigation.frame = CGRect(x: 12, y: 6, width: max(0, view.bounds.width - 24), height: 30)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { NativeSettingsController.panes.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        nativeLabel(NativeSettingsController.panes[row].title)
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !selectingProgrammatically, NativeSettingsController.panes.indices.contains(table.selectedRow) else {
            return
        }
        onSelect?(NativeSettingsController.panes[table.selectedRow].id)
    }
    func select(_ id: String) {
        guard let index = NativeSettingsController.panes.firstIndex(where: { $0.id == id }), table.selectedRow != index
        else { return }
        selectingProgrammatically = true
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        selectingProgrammatically = false
    }
}
