import AppKit
import Combine

final class NativeLaunchpadController: NativeBrowserController {
    private let grid = NativeLaunchpadGridLayout()
    private let pagination = NSStackView()
    private let pageLabel = nativeLabel("", size: 12, color: .secondaryLabelColor)
    private var pageCount: Int { max(1, Int(ceil(Double(displayed.count) / Double(max(1, grid.columns * grid.rows))))) }
    private let wallpaper = NSImageView()
    private let wallpaperBlur = NSVisualEffectView()
    private var wallpaperURL: URL?
    var folder: AppFolderTile?
    let overlay = LaunchpadOverlayService.shared
    let preferences = DockyPreferences.shared
    let layoutService: LaunchpadLayoutService
    init(layoutService: LaunchpadLayoutService = .shared) {
        self.layoutService = layoutService
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidLoad() {
        super.viewDidLoad()
        wallpaper.imageScaling = .scaleAxesIndependently
        wallpaperBlur.blendingMode = .withinWindow
        wallpaperBlur.material = .hudWindow
        view.addSubview(wallpaper, positioned: .below, relativeTo: header)
        view.addSubview(wallpaperBlur, positioned: .above, relativeTo: wallpaper)
        collection.collectionViewLayout = grid
        collection.setDraggingSourceOperationMask(.move, forLocal: true)
        pagination.orientation = .horizontal
        pagination.spacing = 16
        pagination.addArrangedSubview(
            NativeActionButton("", symbol: "chevron.left") { [weak self] in self?.changePage(-1) })
        pagination.addArrangedSubview(pageLabel)
        pagination.addArrangedSubview(
            NativeActionButton("", symbol: "chevron.right") { [weak self] in self?.changePage(1) })
        view.addSubview(pagination)
        header.insertArrangedSubview(
            NativeActionButton(String(localized: "Back"), symbol: "chevron.left") { [weak self] in
                self?.folder = nil
                self?.refresh()
            }, at: 0)
        header.addArrangedSubview(
            NativeActionButton("", symbol: "slider.horizontal.3") { LaunchpadInspectorService.shared.toggle() })
        onEscape = { [weak self] in
            guard let self else { return }
            if self.folder != nil {
                self.folder = nil
                self.refresh()
            } else {
                self.overlay.dismiss()
            }
        }
        configureObservers()
        refresh()
    }
    override func viewDidAppear() {
        super.viewDidAppear()
        refresh()
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        wallpaper.frame = view.bounds
        wallpaperBlur.frame = view.bounds
        if grid.horizontal {
            scroll.frame.origin.y += 36
            scroll.frame.size.height = max(0, scroll.frame.height - 36)
        }
        pagination.frame = CGRect(x: (view.bounds.width - 200) / 2, y: 12, width: 200, height: 28)
        configureGrid()
    }
    private func configureGrid() {
        guard isViewLoaded else { return }
        grid.viewport = scroll.contentSize
        let scale = max(0.5, min(1, view.bounds.height / 1440))
        grid.iconSize = preferences.launchpadBaseIconSize * scale
        grid.spacing = preferences.launchpadColumnSpacing * scale
        grid.rowSpacing = 16 * scale
        let maximumColumns = max(
            1, Int((grid.viewport.width - 32 + grid.spacing) / max(1, grid.iconSize + 44 + grid.spacing)))
        let maximumRows = max(
            1, Int((grid.viewport.height - 32 + grid.rowSpacing) / max(1, grid.iconSize + 44 + grid.rowSpacing)))
        grid.columns = min(maximumColumns, preferences.launchpadGridColumnCount)
        grid.rows = min(maximumRows, preferences.launchpadGridRowCount)
        grid.horizontal = preferences.launchpadLayoutAxis == .horizontal
        pagination.isHidden = !grid.horizontal
        updatePageLabel()
        desiredIconSize = grid.iconSize
        selectionScrollPosition = grid.horizontal ? .nearestHorizontalEdge : .nearestVerticalEdge
        scroll.hasHorizontalScroller = grid.horizontal
        scroll.hasVerticalScroller = !grid.horizontal
        grid.invalidateLayout()
        let configuredURL = preferences.launchpadBackgroundImagePath.map { URL(fileURLWithPath: $0) }
        let url = configuredURL ?? overlay.wallpaperURL
        if url != wallpaperURL {
            wallpaperURL = url
            wallpaper.image = url.flatMap { IconCacheService.shared.image(forImageFileURL: $0) }
        }
        wallpaperBlur.isHidden = !preferences.launchpadBackgroundBlursImage
        wallpaper.alphaValue = 1 - preferences.launchpadOverlayTransparency
    }

    func updatePageLabel() {
        let width = max(1, scroll.contentSize.width)
        let page = min(pageCount, max(1, Int((scroll.contentView.bounds.minX / width).rounded()) + 1))
        pageLabel.stringValue = String(localized: "Page \(page) of \(pageCount)")
    }
    private func changePage(_ direction: Int) {
        let current = Int((scroll.contentView.bounds.minX / max(1, scroll.contentSize.width)).rounded())
        goToPage(current + direction)
    }
    func snapToPage() {
        guard grid.horizontal else { return }
        goToPage(Int((scroll.contentView.bounds.minX / max(1, scroll.contentSize.width)).rounded()))
    }
    private func goToPage(_ index: Int) {
        let origin = CGPoint(x: CGFloat(min(pageCount - 1, max(0, index))) * scroll.contentSize.width, y: 0)
        scroll.contentView.scroll(to: origin)
        scroll.reflectScrolledClipView(scroll.contentView)
        updatePageLabel()
    }
    override func filteredItems() -> [NativeBrowserItem] { launcherFilteredItems() }
    override func reload() {
        super.reload()
        grid.invalidateLayout()
        updatePageLabel()
    }
    private func appItem(_ app: AppTile) -> NativeBrowserItem {
        var actions: [ContextAction] = [.action(String(localized: "Open")) { [weak self] in self?.launch(app) }]
        if folder != nil {
            actions.append(
                .action(String(localized: "Remove from Folder")) { [layoutService] in
                    layoutService.removeFromFolder(bundleID: app.bundleIdentifier)
                })
        }
        return NativeBrowserItem(
            id: "app:\(app.bundleIdentifier)", title: app.displayName,
            image: IconCacheService.shared.icon(forBundleIdentifier: app.bundleIdentifier),
            url: NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier), actions: actions
        ) { [weak self] in self?.launch(app) }
    }
    private func launch(_ app: AppTile) {
        WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
        overlay.dismiss()
    }
    func refresh() {
        guard isViewLoaded else { return }
        configureGrid()
        if let current = folder {
            folder =
                overlay.entries.compactMap {
                    if case .folder(let value) = $0, value.identifier == current.identifier { return value }
                    return nil
                }.first
            if folder == nil {
                query = ""
                search.stringValue = ""
                refresh()
                return
            }
            setItems((folder?.apps ?? []).map(appItem))
        } else {
            setItems(
                sortedEntries(overlay.entries).map { entry in
                    switch entry {
                    case .app(let app): return appItem(app)
                    case .folder(let folder): return folderItem(folder)
                    }
                })
        }
    }
    func rename(_ folder: AppFolderTile) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Rename Folder")
        let field = NSTextField(string: folder.displayName)
        field.frame = CGRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Rename"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            layoutService.renameFolder(id: layoutFolderID(folder), to: field.stringValue)
        }
    }
    override func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath)
        -> NSPasteboardWriting? {
        guard displayed.indices.contains(indexPath.item) else { return nil }
        let writer = NSPasteboardItem()
        writer.setString(displayed[indexPath.item].id, forType: .string)
        return writer
    }
    override func collectionView(
        _ collectionView: NSCollectionView, validateDrop draggingInfo: any NSDraggingInfo,
        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation { query.isEmpty && preferences.launchpadSortMode == .manual ? .move : [] }
    override func collectionView(
        _ collectionView: NSCollectionView, acceptDrop draggingInfo: any NSDraggingInfo, indexPath: IndexPath,
        dropOperation: NSCollectionView.DropOperation
    ) -> Bool {
        guard query.isEmpty, preferences.launchpadSortMode == .manual,
            let id = draggingInfo.draggingPasteboard.string(forType: .string) else { return false }
        let accepted = applyDrop(id: id, at: indexPath.item, operation: dropOperation)
        if accepted { refresh() }
        return accepted
    }
    override func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if control === search, navigate(using: selector) { return true }
        return super.control(control, textView: textView, doCommandBy: selector)
    }
    override func handleKey(_ event: NSEvent) -> Bool {
        let selectors: [UInt16: Selector] = [
            123: #selector(NSResponder.moveLeft(_:)), 124: #selector(NSResponder.moveRight(_:)),
            125: #selector(NSResponder.moveDown(_:)), 126: #selector(NSResponder.moveUp(_:)),
            116: #selector(NSResponder.pageUp(_:)), 121: #selector(NSResponder.pageDown(_:)),
            115: #selector(NSResponder.moveToBeginningOfDocument(_:)),
            119: #selector(NSResponder.moveToEndOfDocument(_:))
        ]
        if let selector = selectors[event.keyCode], navigate(using: selector) { return true }
        return super.handleKey(event)
    }
    private func navigate(using selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveLeft(_:)): moveSelection(-1)
        case #selector(NSResponder.moveRight(_:)): moveSelection(1)
        case #selector(NSResponder.moveDown(_:)): moveSelection(grid.columns)
        case #selector(NSResponder.moveUp(_:)): moveSelection(-grid.columns)
        case #selector(NSResponder.pageUp(_:)): moveSelection(-grid.columns * grid.rows)
        case #selector(NSResponder.pageDown(_:)): moveSelection(grid.columns * grid.rows)
        case #selector(NSResponder.moveToBeginningOfDocument(_:)): selectItem(at: 0)
        case #selector(NSResponder.moveToEndOfDocument(_:)): selectItem(at: displayed.count - 1)
        default: return false
        }
        return true
    }
}
