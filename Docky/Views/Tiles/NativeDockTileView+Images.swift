import AppKit

extension NativeDockTileView {
    func updateImageContent() {
        let tile = interaction.tile
        let prefs = interaction.preferences
        switch tile.content {
        case .app(let app): loadAppIcon(app)
        case .minimizedWindow(let value):
            imageView.image =
                WorkspaceService.shared.minimizedWindowPreview(for: value)
                ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: value.windowTitle)
            let override = prefs.effectiveAppIconOverrideURL(forBundleIdentifier: value.bundleIdentifier)
            minimizedAppIcon.image =
                override.flatMap { IconCacheService.shared.image(forImageFileURL: $0) }
                ?? IconCacheService.shared.icon(forBundleIdentifier: value.bundleIdentifier)
            minimizedAppIcon.isHidden = false
        case .folder(let folder): loadFolderIcon(folder)
        case .appFolder(let folder): loadAppFolderIcon(folder)
        case .launchpad:
            imageView.image =
                prefs.effectiveLaunchpadIconOverrideURL.flatMap {
                    IconCacheService.shared.image(forImageFileURL: $0)
                } ?? IconCacheService.shared.icon(forBundleIdentifier: LaunchpadTile.spotlightBundleIdentifier)
        case .startMenu: imageView.image = WindowsTaskbarStyle.startImage()
        case .trash:
            let state: TrashIconState = TrashService.shared.isEmpty ? .empty : .full
            imageView.image =
                prefs.effectiveTrashIconOverrideURL(forState: state).flatMap {
                    IconCacheService.shared.image(forImageFileURL: $0)
                } ?? NSImage(named: state.systemImageName)
        case .divider, .spacer, .flexibleSpacer: imageView.image = nil
        case .widget, .smartStack: break
        }
    }
    func loadAppIcon(_ app: AppTile) {
        let prefs = interaction.preferences
        let override = prefs.effectiveAppIconOverrideURL(forBundleIdentifier: app.bundleIdentifier)
        imageView.image =
            override.flatMap { IconCacheService.shared.image(forImageFileURL: $0) }
            ?? IconCacheService.shared.icon(forBundleIdentifier: app.bundleIdentifier)
    }

    func loadFolderIcon(_ folder: FolderTile) {
        let prefs = interaction.preferences
        let override = prefs.effectiveFolderIconOverrideURL(forPath: folder.url.path)
        imageView.image =
            override.flatMap { IconCacheService.shared.image(forImageFileURL: $0) }
            ?? IconCacheService.shared.previewIcon(forFileURL: folder.url)
        if interaction.folderDisplayMode != .folder {
            refreshFolderPreview(folder)
            if !folderPreviewURLs.isEmpty { imageView.image = Self.fileStackImage(folderPreviewURLs) }
        }
    }
    func refreshFolderPreview(_ folder: FolderTile) {
        let sort = interaction.folderSortMode
        if folderPreviewURL != folder.url || folderPreviewSort != sort {
            folderPreviewTask?.cancel()
            folderPreviewTask = nil
            folderPreviewURL = folder.url
            folderPreviewSort = sort
            folderPreviewURLs = []
            folderPreviewNeedsRefresh = true
        }
        guard folderPreviewNeedsRefresh, folderPreviewTask == nil, window != nil else { return }
        folderPreviewNeedsRefresh = false
        folderPreviewTask = Task { [weak self] in
            let contents = await FolderAccessService.shared.refreshedSortedContents(of: folder.url, sortMode: sort)
            let urls = Array(contents.prefix(3))
            guard !Task.isCancelled else { return }
            for url in urls {
                _ = await IconCacheService.shared.loadPreviewThumbnailAsync(
                    forFileURL: url, maxPixelSize: IconCacheService.tileThumbnailPixelExtent)
                guard !Task.isCancelled else { return }
            }
            guard let self, self.window != nil, self.folderPreviewURL == folder.url, self.folderPreviewSort == sort
            else { return }
            self.folderPreviewTask = nil
            self.folderPreviewURLs = urls
            self.refresh()
        }
    }

    func loadAppFolderIcon(_ folder: AppFolderTile) {
        let prefs = interaction.preferences
        let key =
            interaction.appFolderDisplayMode.rawValue + String(prefs.showsAppBadges) + prefs.folderBadgeMode.rawValue
            + prefs.folderBadgePreviewStyle.rawValue
            + folder.apps.map {
                $0.bundleIdentifier
                    + (prefs.effectiveAppIconOverrideURL(forBundleIdentifier: $0.bundleIdentifier)?.path ?? "")
                    + (DockBadgeService.shared.badge(forBundleIdentifier: $0.bundleIdentifier) ?? "")
            }.joined(separator: "|")
        if key != folderIconKey {
            folderIconKey = key
            folderIconImage = Self.folderImage(folder.apps, stack: interaction.appFolderDisplayMode == .stack)
        }
        imageView.image = folderIconImage
    }
    static func fileStackImage(_ urls: [URL]) -> NSImage {
        let icons = urls.map {
            IconCacheService.shared.cachedPreviewThumbnail(
                forFileURL: $0, maxPixelSize: IconCacheService.tileThumbnailPixelExtent)
                ?? IconCacheService.shared.icon(forFileURL: $0)
        }
        return NSImage(size: CGSize(width: 64, height: 64), flipped: false) { _ in
            for (index, icon) in icons.reversed().enumerated() {
                icon.draw(in: CGRect(x: 6 + index * 2, y: 6 + index * 3, width: 50, height: 50))
            }
            return true
        }
    }
    static func folderImage(_ apps: [AppTile], stack: Bool) -> NSImage {
        let preferences = DockyPreferences.shared
        let images = apps.prefix(stack ? 3 : 4).map { app -> (NSImage, String?) in
            let override = preferences.effectiveAppIconOverrideURL(forBundleIdentifier: app.bundleIdentifier)
            let icon =
                override.flatMap { IconCacheService.shared.image(forImageFileURL: $0) }
                ?? IconCacheService.shared.icon(forBundleIdentifier: app.bundleIdentifier)
            let badge =
                preferences.showsAppBadges && preferences.folderBadgeMode == .perApp && !stack
                ? DockBadgeService.shared.badge(forBundleIdentifier: app.bundleIdentifier) : nil
            return (icon, badge)
        }
        let numbered = preferences.folderBadgePreviewStyle == .number
        return NSImage(size: CGSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.secondarySystemFill.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 3), xRadius: 12, yRadius: 12).fill()
            for index in images.indices.reversed() {
                let frame =
                    stack
                    ? CGRect(x: 5 + index * 3, y: 5 + index * 4, width: 48, height: 48)
                    : CGRect(x: 8 + (index % 2) * 26, y: 34 - (index / 2) * 26, width: 24, height: 24)
                images[index].0.draw(in: frame)
                if let badge = images[index].1 { drawFolderBadge(badge, at: frame, numbered: numbered) }
            }
            return true
        }
    }
    static func drawFolderBadge(_ text: String, at icon: CGRect, numbered: Bool) {
        let diameter: CGFloat = numbered ? 13 : 7
        let badge = CGRect(
            x: icon.maxX - diameter * 0.65, y: icon.maxY - diameter * 0.65, width: diameter, height: diameter)
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: badge).fill()
        guard numbered else { return }
        let string = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: 7, weight: .semibold), .foregroundColor: NSColor.white])
        let size = string.size()
        string.draw(at: CGPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2))
    }
}
