import AppKit

/// The Settings sidebar: a source list of panes, with Docky's version below it.
final class NativeSettingsSidebarController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    let tableView = NSTableView()
    var onSelect: ((SettingsPane) -> Void)?
    private let scrollView = NSScrollView()
    private var selectingProgrammatically = false
    private static let cellIdentifier = NSUserInterfaceItemIdentifier("SettingsPaneCell")

    override func loadView() {
        view = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 500))
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pane")))
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.rowSizeStyle = .default
        tableView.allowsEmptySelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityLabel(String(localized: "Settings Sections"))
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        let version = NSTextField(labelWithString: Self.versionText)
        version.font = .preferredFont(forTextStyle: .footnote)
        version.textColor = .secondaryLabelColor
        version.alignment = .center
        version.isSelectable = true
        version.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        view.addSubview(version)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: version.topAnchor, constant: -8),
            version.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            version.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            version.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10)
        ])
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return String(localized: "Version \(version) (\(build))", comment: "Docky's version and build number")
    }

    func numberOfRows(in tableView: NSTableView) -> Int { SettingsPane.allCases.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: Self.cellIdentifier, owner: self) as? NSTableCellView ?? makeCell()
        let pane = SettingsPane.allCases[row]
        cell.textField?.stringValue = pane.title
        cell.imageView?.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: nil)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !selectingProgrammatically, SettingsPane.allCases.indices.contains(tableView.selectedRow) else { return }
        onSelect?(SettingsPane.allCases[tableView.selectedRow])
    }

    func select(_ pane: SettingsPane) {
        guard let index = SettingsPane.allCases.firstIndex(of: pane), tableView.selectedRow != index else { return }
        selectingProgrammatically = true
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
        selectingProgrammatically = false
    }

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
            image.widthAnchor.constraint(equalToConstant: 20),
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }
}
