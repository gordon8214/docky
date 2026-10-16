import AppKit

/// Settings' split view: the list of panes in a sidebar, with the selected
/// pane beside it. The window takes its title from the selected pane.
final class NativeSettingsController: NSSplitViewController {
    /// Remembers the last pane between openings. It isn't a `DockyPreferences`
    /// key, so profiles don't mirror it.
    static let selectedPaneKey = "DockySettingsSelectedPane"
    var onNavigationChange: (() -> Void)?
    private(set) var selectedPane: SettingsPane
    private let defaults: UserDefaults
    private let sidebar = NativeSettingsSidebarController()
    private let detail = NativeSettingsDetailController()
    private var history = SettingsNavigationHistory()
    private var cache: [SettingsPane: NSViewController] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedPane = defaults.string(forKey: Self.selectedPaneKey).flatMap(SettingsPane.init(rawValue:)) ?? .general
        super.init(nibName: nil, bundle: nil)
        title = selectedPane.title
    }

    required init?(coder: NSCoder) { nil }

    var canGoBack: Bool { history.canMoveBack }
    var canGoForward: Bool { history.canMoveForward }

    override func viewDidLoad() {
        super.viewDidLoad()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 260
        sidebarItem.canCollapse = false
        addSplitViewItem(sidebarItem)
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 460
        addSplitViewItem(detailItem)
        sidebar.onSelect = { [weak self] in self?.showPane($0) }
        showPane(selectedPane)
    }

    func showPane(_ pane: SettingsPane, recordsHistory: Bool = true) {
        guard endPaneEditing() else {
            sidebar.select(selectedPane)
            return
        }
        if recordsHistory { history.push(pane.rawValue) }
        selectedPane = pane
        defaults.set(pane.rawValue, forKey: Self.selectedPaneKey)
        detail.show(controller(for: pane))
        title = pane.title
        sidebar.select(pane)
        onNavigationChange?()
    }

    func goBack() { navigate(-1) }
    func goForward() { navigate(1) }

    private func navigate(_ delta: Int) {
        guard endPaneEditing(), let identifier = history.move(delta), let pane = SettingsPane(rawValue: identifier)
        else { return }
        showPane(pane, recordsHistory: false)
    }

    /// Moves focus out of the pane, which ends an edit in progress so a typed
    /// number saves. Returns false, with a beep, when the field won't give up
    /// focus because its text isn't a number.
    private func endPaneEditing() -> Bool {
        guard let window = view.window, let responder = window.firstResponder as? NSView,
            responder.isDescendant(of: detail.view)
        else { return true }
        if window.makeFirstResponder(sidebar.tableView) { return true }
        NSSound.beep()
        return false
    }

    /// Panes are kept once built, so each keeps its scroll position.
    private func controller(for pane: SettingsPane) -> NSViewController {
        if let cached = cache[pane] { return cached }
        let controller: NSViewController =
            pane == .appIcons ? NativeIconSettingsController() : NativeSettingsPaneController(pane: pane)
        cache[pane] = controller
        return controller
    }
}

/// Holds the selected pane, so the split view keeps the same two items.
private final class NativeSettingsDetailController: NSViewController {
    override func loadView() {
        view = NSView(frame: CGRect(x: 0, y: 0, width: 600, height: 500))
    }

    func show(_ controller: NSViewController) {
        for child in children where child !== controller {
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        guard controller.parent !== self else { return }
        addChild(controller)
        let pane = controller.view
        pane.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.topAnchor.constraint(equalTo: view.topAnchor),
            pane.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pane.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
