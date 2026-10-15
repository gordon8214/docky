import AppKit
import OSLog
import QuickLookThumbnailing

@MainActor
func folderNavigationContextActions(for folderURL: URL) -> [ContextAction] {
    let snapshot = FolderAccessService.shared.snapshot(of: folderURL)
    guard case .loaded(let items) = snapshot else {
        return [.action(String(localized: "Can't read folder")) {}]
    }

    let sortedItems = FolderAccessService.shared.sortedItems(in: items, sortMode: .name)

    var actions: [ContextAction] = sortedItems.map { url in
        let resources = try? url.resourceValues(forKeys: [
            .localizedNameKey,
            .isDirectoryKey,
            .isPackageKey
        ])
        let displayName = resources?.localizedName ?? url.lastPathComponent
        let isNavigableFolder = (resources?.isDirectory == true) && (resources?.isPackage != true)
        let icon = IconCacheService.shared.icon(forFileURL: url)

        if isNavigableFolder {
            return .lazySubmenu(displayName, image: icon) {
                folderNavigationContextActions(for: url)
            }
        }

        return .lazySubmenu(displayName, image: icon) {
            fileContextActions(for: url)
        }
    }

    if !actions.isEmpty {
        actions.append(.divider)
    }
    actions.append(
        .action(FileBrowserService.shared.current.openInTitle, image: contextMenuSymbol("folder")) {
            Task { await FileBrowserService.shared.openFolder(folderURL) }
        })

    return actions
}

@MainActor
func fileContextActions(for url: URL) -> [ContextAction] {
    [
        .customView(FilePreviewMenuItemView(url: url)),
        .divider,
        .action(String(localized: "Open"), image: contextMenuSymbol("arrow.up.forward.app")) {
            NSWorkspace.shared.open(url)
        },
        .lazySubmenu(String(localized: "Open With"), image: contextMenuSymbol("app.badge")) {
            openWithApplicationActions(for: url)
        },
        .action(FileBrowserService.shared.current.revealInTitle, image: contextMenuSymbol("folder")) {
            FileBrowserService.shared.reveal(url)
        },
        .divider,
        .action(String(localized: "Copy"), image: contextMenuSymbol("doc.on.doc")) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([url as NSURL])
        },
        .share(url),
        .divider,
        .action(
            "Move to Trash",
            image: contextMenuSymbol("trash"),
            isDestructive: true
        ) {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    ]
}

@MainActor
func recentFilesContextActions() -> [ContextAction] {
    let urls = RecentFilesService.shared.recentURLs
    Logger(subsystem: "gt.quintero.Docky", category: "RecentFiles")
        .info("menu requested urls.count=\(urls.count, privacy: .public)")
    guard !urls.isEmpty else { return [] }

    let visibleLimit = 10
    let visible = urls.prefix(visibleLimit)
    let overflow = Array(urls.dropFirst(visibleLimit))

    var actions: [ContextAction] = visible.map(recentFileContextAction)

    if !overflow.isEmpty {
        actions.append(
            .lazySubmenu(String(localized: "More"), image: contextMenuSymbol("ellipsis")) {
                overflow.map(recentFileContextAction)
            })
    }

    return actions
}

@MainActor
private func recentFileContextAction(for url: URL) -> ContextAction {
    let displayName =
        (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName)
        ?? url.lastPathComponent
    let icon = IconCacheService.shared.icon(forFileURL: url)
    return .lazySubmenu(displayName, image: icon) {
        fileContextActions(for: url)
    }
}

@MainActor
func contextMenuSymbol(_ name: String) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)
}

/// Inserts a "running windows" section into a catalog-driven app menu.
/// Each window becomes a top-level action that focuses the window when
/// chosen. Inserted before any "Options" submenu, falling back to the end
/// when none is present. Called from both the dock tile path and the app
/// folder grid path so menus stay in sync.
@MainActor
func injectingAppWindowActions(
    _ windows: [AppWindow],
    into actions: [ContextAction]
) -> [ContextAction] {
    guard !windows.isEmpty else { return actions }

    let windowActions = windows.map { window in
        ContextAction.action(appWindowMenuTitle(for: window)) {
            _ = WorkspaceService.shared.focus(window: window)
        }
    }

    var result = windowActions
    if !actions.isEmpty {
        result.append(.divider)
        result.append(contentsOf: actions)
    }

    while result.first?.kind == .divider {
        result.removeFirst()
    }

    while result.last?.kind == .divider {
        result.removeLast()
    }

    return result.enumerated().compactMap { index, action in
        if action.kind == .divider,
            index > 0,
            result[index - 1].kind == .divider {
            return nil
        }

        return action
    }
}

@MainActor
func appWindowMenuTitle(for window: AppWindow) -> String {
    guard window.isMinimized else {
        return window.windowTitle
    }

    return "\(window.windowTitle) (Minimized)"
}

@MainActor
private func openWithApplicationActions(for url: URL) -> [ContextAction] {
    let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: url)
    guard !appURLs.isEmpty else {
        return [.action(String(localized: "No Applications Available")) {}]
    }

    return appURLs.map { appURL in
        let appName =
            (try? appURL.resourceValues(forKeys: [.localizedNameKey]).localizedName)
            ?? appURL.deletingPathExtension().lastPathComponent
        let icon = IconCacheService.shared.icon(forFileURL: appURL)
        return .action(appName, image: icon) {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: appURL,
                configuration: configuration,
                completionHandler: nil
            )
        }
    }
}

final class FilePreviewMenuItemView: NSView, NSDraggingSource {
    private static let viewSize = CGSize(width: 240, height: 160)
    private static let dragThresholdSquared: CGFloat = 16

    private let imageView: NSImageView
    private let url: URL
    private var mouseDownLocation: NSPoint?

    init(url: URL) {
        self.url = url
        let frame = NSRect(origin: .zero, size: Self.viewSize)
        let inset = NSRect(
            x: 12,
            y: 8,
            width: frame.width - 24,
            height: frame.height - 16
        )

        let imageView = NSImageView(frame: inset)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.image = IconCacheService.shared.previewIcon(forFileURL: url)
        imageView.autoresizingMask = [.width, .height]
        self.imageView = imageView

        super.init(frame: frame)
        addSubview(imageView)
        loadPreview(for: url)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downLocation = mouseDownLocation else { return }
        let horizontalInset = event.locationInWindow.x - downLocation.x
        let verticalInset = event.locationInWindow.y - downLocation.y
        guard (horizontalInset * horizontalInset + verticalInset * verticalInset) >= Self.dragThresholdSquared else {
            return
        }
        mouseDownLocation = nil

        let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
        let dragImage = imageView.image ?? IconCacheService.shared.icon(forFileURL: url)
        draggingItem.setDraggingFrame(imageView.frame, contents: dragImage)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
        enclosingMenuItem?.menu?.cancelTracking()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        [.copy, .link, .generic]
    }

    private func loadPreview(for url: URL) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: Self.viewSize,
            scale: scale,
            representationTypes: .all
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, _ in
            guard let nsImage = thumbnail?.nsImage else { return }
            DispatchQueue.main.async {
                self?.imageView.image = nsImage
            }
        }
    }
}
