import AppKit
import Combine

struct NativeBrowserItem {
    let id: String
    let title: String
    var detail: String = ""
    var image: NSImage?
    var url: URL?
    var actions: [ContextAction] = []
    var actionsProvider: ((NSEvent.ModifierFlags) -> [ContextAction])?
    let activate: () -> Void
}

/// Shared native grid/list presentation for launchers, folders, and previews.
class NativeBrowserController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate,
    NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private(set) var browserContentView: NSView!
    let search = NSSearchField()
    let header = NSStackView()
    let scroll = NSScrollView()
    var onDragExit: (() -> Void)?
    let collection = NativeBrowserCollectionView()
    let table = NativeBrowserTableView()
    let message = nativeLabel("")
    var items: [NativeBrowserItem] = []
    var displayed: [NativeBrowserItem] = []
    let observations = NativeObservationSession()
    var onSearch: ((String) -> Void)?
    var onEscape: (() -> Void)?
    var onSelection: ((String) -> Void)?
    var onQuickLook: ((NativeBrowserItem) -> Void)?
    var onDrop: (([URL], Int?, Bool) -> Bool)?
    var onContextMenu: ((Bool) -> Void)?
    var desiredIconSize: CGFloat?
    var selectionScrollPosition: NSCollectionView.ScrollPosition = .nearestVerticalEdge
    var gridSize = CGSize(width: 116, height: 120) { didSet { if oldValue != gridSize { updateLayout() } } }
    var usesList = false { didSet { if oldValue != usesList, isViewLoaded { updateLayout() } } }
    var query = ""
    var selectionID: String?
    var previewTasks: [URL: Task<Void, Never>] = [:]
    private let layout = NSCollectionViewFlowLayout()
    override func loadView() {
        let material = NativeHoverMaterialView()
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        view = material
        browserContentView = material
        header.orientation = .horizontal
        header.spacing = 8
        header.alignment = .centerY
        search.placeholderString = String(localized: "Search")
        search.delegate = self
        header.addArrangedSubview(search)
        view.addSubview(header)
        view.addSubview(scroll)
        view.addSubview(message)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        collection.collectionViewLayout = layout
        collection.dataSource = self
        collection.delegate = self
        collection.isSelectable = true
        collection.backgroundColors = [.clear]
        collection.register(
            NativeBrowserCollectionItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("item"))
        collection.controller = self
        collection.registerForDraggedTypes([.fileURL, .string])
        collection.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
        table.headerView = nil
        table.rowHeight = 52
        table.dataSource = self
        table.delegate = self
        table.controller = self
        table.target = self
        table.doubleAction = #selector(activateTableSelection)
        table.registerForDraggedTypes([.fileURL, .string])
        message.textColor = .secondaryLabelColor
        updateLayout()
    }
    override func viewDidAppear() {
        super.viewDidAppear()
        observations.start()
    }
    override func viewDidDisappear() {
        super.viewDidDisappear()
        observations.stop()
        cancelPreviewLoading()
    }
    func cancelPreviewLoading() {
        for task in previewTasks.values { task.cancel() }
        previewTasks.removeAll()
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        header.frame = CGRect(
            x: 16, y: browserContentView.bounds.height - 52, width: max(0, browserContentView.bounds.width - 32),
            height: 36)
        scroll.frame = CGRect(
            x: 12, y: 12, width: max(0, browserContentView.bounds.width - 24),
            height: max(0, browserContentView.bounds.height - (header.isHidden ? 24 : 76)))
        message.frame = CGRect(
            x: 24, y: browserContentView.bounds.midY, width: max(0, browserContentView.bounds.width - 48), height: 40)
        if usesList { table.frame.size.width = scroll.contentSize.width }
    }
    func updateLayout() {
        guard isViewLoaded else { return }
        layout.itemSize = gridSize
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        scroll.documentView = usesList ? table : collection
        reload()
    }
    func setItems(_ items: [NativeBrowserItem]) {
        self.items = items
        if isViewLoaded { reload() }
    }
    func filteredItems() -> [NativeBrowserItem] {
        items.filter {
            query.isEmpty || $0.title.localizedStandardContains(query) || $0.detail.localizedStandardContains(query)
        }
    }
    func reload() {
        displayed = filteredItems()
        collection.reloadData()
        table.reloadData()
        scroll.isHidden = displayed.isEmpty
        message.isHidden = !displayed.isEmpty
        if message.stringValue.isEmpty { message.stringValue = String(localized: "No items available") }
        if let selectionID, let index = displayed.firstIndex(where: { $0.id == selectionID }) {
            collection.selectionIndexPaths = [IndexPath(item: index, section: 0)]
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else {
            selectionID = nil
            collection.selectionIndexPaths = []
            table.deselectAll(nil)
        }
    }
    func controlTextDidChange(_ notification: Notification) {
        query = search.stringValue
        onSearch?(query)
        reload()
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            activateSelected()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onEscape?()
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(-1)
            return true
        default: return false
        }
    }
    func moveSelection(_ delta: Int) {
        guard !displayed.isEmpty else { return }
        let current =
            selectionID.flatMap { id in displayed.firstIndex(where: { $0.id == id }) }
            ?? (delta > 0 ? -1 : displayed.count)
        selectItem(at: current + delta)
    }
    func selectItem(at proposedIndex: Int) {
        guard !displayed.isEmpty else { return }
        let index = min(displayed.count - 1, max(0, proposedIndex))
        let identifier = displayed[index].id
        if selectionID != identifier {
            selectionID = identifier
            onSelection?(identifier)
        }
        collection.selectionIndexPaths = [IndexPath(item: index, section: 0)]
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        if usesList {
            table.scrollRowToVisible(index)
        } else {
            collection.scrollToItems(at: collection.selectionIndexPaths, scrollPosition: selectionScrollPosition)
        }
    }
    @objc private func activateTableSelection() { activateSelected() }
    func activateSelected() {
        if let selectionID, let item = displayed.first(where: { $0.id == selectionID }) {
            item.activate()
        } else {
            displayed.first?.activate()
        }
    }
    func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53:
            onEscape?()
            return true
        case 36:
            activateSelected()
            return true
        case 49:
            if let selectionID, let item = displayed.first(where: { $0.id == selectionID }), let onQuickLook {
                onQuickLook(item)
                return true
            }
            return false
        default: return false
        }
    }
    func menu(for index: Int, from view: NSView) {
        guard displayed.indices.contains(index) else { return }
        ContextActionMenuPresenter.popUpMenu(
            actions: displayed[index].actionsProvider?(NSEvent.modifierFlags) ?? displayed[index].actions, from: view,
            onPresentationChanged: { [weak self] in self?.onContextMenu?($0) })
    }
    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath)
        -> NSPasteboardWriting? {
        guard displayed.indices.contains(indexPath.item) else { return nil }
        return displayed[indexPath.item].url as NSURL?
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        displayed[row].url as NSURL?
    }
    func collectionView(
        _ collectionView: NSCollectionView, validateDrop draggingInfo: any NSDraggingInfo,
        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation { onDrop == nil ? [] : .copy }
    func collectionView(
        _ collectionView: NSCollectionView, acceptDrop draggingInfo: any NSDraggingInfo, indexPath: IndexPath,
        dropOperation: NSCollectionView.DropOperation
    ) -> Bool {
        let urls = (draggingInfo.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        return onDrop?(urls, indexPath.item, dropOperation == .on) ?? false
    }
    func tableView(
        _ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation { onDrop == nil ? [] : .copy }
    func tableView(
        _ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        let urls = (info.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        return onDrop?(urls, row, dropOperation == .on) ?? false
    }
}

final class NativeBrowserCollectionView: NSCollectionView {
    weak var controller: NativeBrowserController?
    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        controller?.onDragExit?()
        super.draggingExited(sender)
    }
    override func keyDown(with event: NSEvent) {
        if controller?.handleKey(event) != true { super.keyDown(with: event) }
    }
    override func rightMouseDown(with event: NSEvent) {
        if let index = indexPathForItem(at: convert(event.locationInWindow, from: nil))?.item {
            controller?.menu(for: index, from: self)
        }
    }
}
final class NativeBrowserTableView: NSTableView {
    weak var controller: NativeBrowserController?
    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        controller?.onDragExit?()
        super.draggingExited(sender)
    }
    override func keyDown(with event: NSEvent) {
        if controller?.handleKey(event) != true { super.keyDown(with: event) }
    }
    override func rightMouseDown(with event: NSEvent) {
        controller?.menu(for: row(at: convert(event.locationInWindow, from: nil)), from: self)
    }
}
final class NativeBrowserCollectionItem: NSCollectionViewItem {
    private let titleLabel = nativeLabel("")
    private let detailLabel = nativeLabel("", size: 11, color: .secondaryLabelColor)
    private let icon = NSImageView()
    private var action: (() -> Void)?
    private var desiredIconSize: CGFloat?
    override func loadView() {
        let itemView = NativeCollectionItemView()
        let gesture = NSClickGestureRecognizer(target: self, action: #selector(activateItem))
        gesture.delaysPrimaryMouseButtonEvents = false
        itemView.addGestureRecognizer(gesture)
        itemView.onPress = { [weak self] in self?.action?() }
        itemView.setAccessibilityRole(.button)
        icon.setAccessibilityElement(false)
        view = itemView
        icon.imageScaling = .scaleProportionallyUpOrDown
        view.addSubview(icon)
        view.addSubview(titleLabel)
        view.addSubview(detailLabel)
        titleLabel.alignment = .center
        detailLabel.alignment = .center
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        let width = min(desiredIconSize ?? view.bounds.width, max(0, view.bounds.width - 16))
        let labelHeight: CGFloat = detailLabel.isHidden ? 32 : 52
        let height = min(desiredIconSize ?? view.bounds.height, max(0, view.bounds.height - labelHeight))
        icon.frame = CGRect(x: (view.bounds.width - width) / 2, y: labelHeight - 8, width: width, height: height)
        titleLabel.frame = CGRect(
            x: 4, y: detailLabel.isHidden ? 4 : 22, width: max(0, view.bounds.width - 8), height: 20)
        detailLabel.frame = CGRect(x: 4, y: 2, width: max(0, view.bounds.width - 8), height: 18)
    }
    func configure(_ item: NativeBrowserItem, controller: NativeBrowserController) {
        _ = view
        titleLabel.stringValue = item.title
        detailLabel.stringValue = item.detail
        detailLabel.isHidden = item.detail.isEmpty
        icon.image = item.image
        desiredIconSize = controller.desiredIconSize
        action = item.activate
        view.setAccessibilityLabel(item.title)
        view.setAccessibilityIdentifier(item.id)
    }
    @objc private func activateItem(_ gesture: NSClickGestureRecognizer) {
        guard gesture.state == .ended, NSEvent.modifierFlags.isDisjoint(with: [.command, .shift]) else { return }
        action?()
    }
    override var isSelected: Bool {
        didSet {
            view.wantsLayer = true
            view.layer?.backgroundColor =
                isSelected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25).cgColor : nil
            view.layer?.cornerRadius = 10
        }
    }
}

private final class NativeCollectionItemView: NSView {
    var onPress: (() -> Void)?
    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(convert(point, from: superview)) ? self : nil }
}
