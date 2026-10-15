import AppKit
import Combine
import QuickLookUI

final class NativeFolderController: NativeBrowserController {
    private var folder: FolderTile?
    private var appFolder: AppFolderTile?
    private var draggedAppIdentifier: String?
    private var springLoadURL: URL?
    private var springLoadTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private(set) var presentationActive = false
    private let accessButton = NativeActionButton(String(localized: "Grant Folder Access")) {
        Task { _ = await PermissionsService.shared.requestPermission(for: .userFolders) }
    }
    private let tileID: String
    private(set) var watchedURL: URL?
    private let watcherID = "native-folder:" + UUID().uuidString
    private var history: [URL] = []
    var onClose: (() -> Void)?
    init(folder: FolderTile?, appFolder: AppFolderTile?, tileID: String) {
        self.folder = folder
        self.appFolder = appFolder
        self.tileID = tileID
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }
    isolated deinit {
        refreshTask?.cancel()
        springLoadTask?.cancel()
        if let watchedURL { FolderAccessService.shared.endWatching(watchedURL, ownerID: watcherID) }
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 540, height: 420)
        header.insertArrangedSubview(
            NativeActionButton("", symbol: "chevron.left") { [weak self] in self?.back() }, at: 0)
        let openFolderButton = NativeActionButton("", symbol: "folder") { [weak self] in
            guard let url = self?.folder?.url else { return }
            Task { await FileBrowserService.shared.openFolder(url) }
        }
        let openFolderTitle = FileBrowserService.shared.current.openInTitle
        openFolderButton.setAccessibilityLabel(openFolderTitle)
        openFolderButton.image?.accessibilityDescription = openFolderTitle
        openFolderButton.toolTip = openFolderTitle
        // App folders have no folder on disk to open.
        openFolderButton.isHidden = folder == nil
        header.addArrangedSubview(openFolderButton)
        header.addArrangedSubview(accessButton)
        accessButton.isHidden = true
        if let folder { usesList = folder.contentViewMode == .list }
        onDragExit = { [weak self] in self?.scheduleSpringLoading(nil) }
        onEscape = { [weak self] in self?.onClose?() }
        onQuickLook = { if let url = $0.url { NativeQuickLookController.shared.preview(url) } }
        onDrop = { [weak self] urls, index, onItem in
            self?.drop(urls, at: self?.appFolder != nil || onItem ? index : nil, onItem: onItem) ?? false
        }
        let observedPublisher1 = FolderAccessService.shared.objectWillChange
        observations.add { [weak self] in
            observedPublisher1.sink { [weak self] in DispatchQueue.main.async { self?.refresh() } }

        }
        let observedPublisher2 = TileStore.shared.objectWillChange
        observations.add { [weak self] in
            observedPublisher2.sink { [weak self] in DispatchQueue.main.async { self?.refresh() } }

        }
        refresh()
    }
    override func viewDidAppear() {
        super.viewDidAppear()
        presentationActive = true
        refresh()
        view.window?.makeFirstResponder(search)
    }
    private func back() {
        guard let url = history.popLast(), let old = folder else { return }
        query = ""
        search.stringValue = ""
        folder = FolderTile(
            url: url, displayName: FileManager.default.displayName(atPath: url.path), displayMode: old.displayMode,
            contentViewMode: old.contentViewMode, sortMode: old.sortMode)
        refresh()
    }
    override func viewWillDisappear() {
        super.viewWillDisappear()
        presentationActive = false
        observations.stop()
        refreshTask?.cancel()
        refreshTask = nil
        cancelPreviewLoading()
        if let watchedURL { FolderAccessService.shared.endWatching(watchedURL, ownerID: watcherID) }
        watchedURL = nil
        springLoadTask?.cancel()
        springLoadTask = nil
        springLoadURL = nil
    }
    func refresh() {
        guard presentationActive else { return }
        if let folder {
            if watchedURL != folder.url {
                if let watchedURL { FolderAccessService.shared.endWatching(watchedURL, ownerID: watcherID) }
                watchedURL = folder.url
                FolderAccessService.shared.beginWatching(folder.url, ownerID: watcherID)
            }
            refreshTask?.cancel()
            refreshTask = Task { [weak self] in
                let service = FolderAccessService.shared
                let snapshot = await service.refreshedSnapshot(of: folder.url)
                guard !Task.isCancelled, let self, self.presentationActive, self.folder == folder else { return }
                let urls = service.sortedItems(in: snapshot, sortMode: folder.sortMode)
                self.message.stringValue = snapshot == .unreadable
                    ? String(localized: "Folder access is unavailable") : String(localized: "Folder is empty")
                self.accessButton.isHidden = snapshot != .unreadable
                self.setItems(urls.map(self.fileItem))
            }
        } else if appFolder != nil {
            guard let tile = TileStore.shared.tiles.first(where: { $0.id == tileID }),
                case .appFolder(let appFolder) = tile.content
            else {
                setItems([])
                onClose?()
                return
            }
            self.appFolder = appFolder
            setItems(appFolder.apps.map(applicationItem))
        }
    }

    func fileItem(_ url: URL) -> NativeBrowserItem {
        NativeBrowserItem(
            id: url.path, title: FileManager.default.displayName(atPath: url.path),
            image: filePreview(for: url), url: url,
            actionsProvider: { _ in
                fileContextActions(for: url) + [
                    .divider, .action(String(localized: "Quick Look")) { NativeQuickLookController.shared.preview(url) }
                ]
            }, activate: { [weak self] in self?.open(url) })
    }
    private func applicationItem(_ app: AppTile) -> NativeBrowserItem {
        NativeBrowserItem(
            id: app.bundleIdentifier, title: app.displayName,
            image: IconCacheService.shared.icon(forBundleIdentifier: app.bundleIdentifier),
            url: NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier),
            actionsProvider: { [tileID] modifiers in
                let base = MenuCatalogService.shared.contextActions(
                    for: Tile(content: .app(app)), modifierFlags: modifiers) ?? []
                let windows = WorkspaceService.shared.appWindows(bundleIdentifier: app.bundleIdentifier)
                var actions = injectingAppWindowActions(windows, into: base)
                if !actions.isEmpty { actions.append(.divider) }
                actions.append(.action(String(localized: "Remove from Folder")) {
                    TileStore.shared.removeAppFromFolder(
                        tileID: tileID, bundleIdentifier: app.bundleIdentifier)
                })
                return actions
            }, activate: { [weak self] in
                WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
                self?.onClose?()
            })
    }
    private func open(_ url: URL) {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        if values?.isDirectory == true, values?.isPackage != true, let old = folder {
            query = ""
            search.stringValue = ""
            history.append(old.url)
            folder = FolderTile(
                url: url, displayName: FileManager.default.displayName(atPath: url.path), displayMode: old.displayMode,
                contentViewMode: old.contentViewMode, sortMode: old.sortMode)
            refresh()
        } else {
            NSWorkspace.shared.open(url)
            onClose?()
        }
    }
    override func collectionView(
        _ collectionView: NSCollectionView, validateDrop draggingInfo: any NSDraggingInfo,
        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation {
        let index = proposedDropIndexPath.pointee.item
        let target =
            proposedDropOperation.pointee == .on && displayed.indices.contains(index) ? displayed[index].url : nil
        scheduleSpringLoading(target)
        return appFolder == nil ? .move : .copy
    }
    override func tableView(
        _ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        scheduleSpringLoading(dropOperation == .on && displayed.indices.contains(row) ? displayed[row].url : nil)
        return appFolder == nil ? .move : .copy
    }
    private func scheduleSpringLoading(_ url: URL?) {
        guard url != springLoadURL else { return }
        springLoadTask?.cancel()
        springLoadURL = url
        guard folder != nil, let url, let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
            values.isDirectory == true, values.isPackage != true
        else { return }
        springLoadTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            guard let self, !Task.isCancelled, self.springLoadURL == url, NSEvent.pressedMouseButtons & 1 != 0 else {
                return
            }
            self.open(url)
        }
    }

    private func drop(_ urls: [URL], at index: Int?, onItem: Bool) -> Bool {
        scheduleSpringLoading(nil)
        if let appFolder {
            if let draggedAppIdentifier, let index {
                guard query.isEmpty,
                    let source = appFolder.apps.firstIndex(where: { $0.bundleIdentifier == draggedAppIdentifier })
                else { return false }
                TileStore.shared.reorderAppsInFolder(
                    tileID: tileID, movingBundleIdentifier: draggedAppIdentifier,
                    toIndex: index - (!onItem && source < index ? 1 : 0))
                refresh()
                return true
            }
            if let index, displayed.indices.contains(index),
                let app = appFolder.apps.first(where: { $0.bundleIdentifier == displayed[index].id }),
                DockDragService.shared.sourceFolderTileID == nil, !urls.contains(where: { $0.pathExtension == "app" }) {
                WorkspaceService.shared.open(fileURLs: urls, withApplicationBundleIdentifier: app.bundleIdentifier)
                onClose?()
                return true
            }
            var added = false
            for url in urls {
                if let id = Bundle(url: url)?.bundleIdentifier {
                    _ = TileStore.shared.groupApps(bundleIdentifiers: [id], intoTileID: tileID)
                    added = true
                }
            }
            return added
        }
        guard let folder else { return false }
        var destination = folder.url
        if let index, displayed.indices.contains(index), let url = displayed[index].url,
            (try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])).map({
                $0.isDirectory == true && $0.isPackage != true
            }) == true {
            destination = url
        }
        var moved = false
        for url in urls {
            do {
                try FileManager.default.moveItem(at: url, to: destination.appendingPathComponent(url.lastPathComponent))
                moved = true
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
        refresh()
        return moved
    }
}

@MainActor
final class NativeQuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = NativeQuickLookController()
    private var url: URL?
    func preview(_ url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { url as NSURL? }
}

extension NativeFolderController {
    func collectionView(
        _ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>
    ) {
        guard appFolder != nil, let index = indexPaths.first?.item, displayed.indices.contains(index),
            let url = displayed[index].url
        else { return }
        draggedAppIdentifier = displayed[index].id
        DockDragService.shared.sourceFolderTileID = tileID
        DockDragService.shared.sourceFolderBundleIdentifier = draggedAppIdentifier
        if let kind = DockDragService.resolvePreview(from: [url]) {
            DockDragService.shared.begin(kind: kind, at: .zero)
        }
    }
    func collectionView(
        _ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
        endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation
    ) {
        draggedAppIdentifier = nil
        DockDragService.shared.clear()
    }
}
