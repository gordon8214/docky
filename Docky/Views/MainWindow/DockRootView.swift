import AppKit
import Combine
import QuartzCore

private struct HiddenDragImageSnapshot {
    let item: NSDraggingItem
    let originalProvider: (() -> [NSDraggingImageComponent])?
}

/// Native Dock chrome and canvas; also owns the external drag destination.
final class DockRootView: NSView {
    private let chrome = DockChromeView()
    let canvas = DockCanvasView()
    private var subscriptions = Set<AnyCancellable>()
    private var hiddenDragImageOriginals: [HiddenDragImageSnapshot] = []
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        WindowsTaskbarMenu.install()
        addSubview(chrome)
        addSubview(canvas)
        registerForDraggedTypes([.fileURL, .string])
        DockLayoutService.shared.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.needsLayout = true }
        }.store(in: &subscriptions)
        DockChromeMetricsService.shared.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.needsLayout = true }
        }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
        )
        .sink { [weak self] _ in self?.chrome.refresh() }.store(in: &subscriptions)
        observeChanges { [weak self] in
            guard let self else { return }
            _ = DockyPreferences.shared.effectiveWindowTintColor
            _ = DockyPreferences.shared.effectiveWindowTintOpacity
            _ = DockyPreferences.shared.effectiveWindowCornerRadiusTopLeading
            _ = DockyPreferences.shared.effectiveWindowCornerRadiusTopTrailing
            _ = DockyPreferences.shared.effectiveWindowCornerRadiusBottomLeading
            _ = DockyPreferences.shared.effectiveWindowCornerRadiusBottomTrailing
            _ = DockyPreferences.shared.effectiveWindowBorderWidth
            _ = DockyPreferences.shared.effectiveWindowBackgroundImageMode
            _ = DockyPreferences.shared.effectiveWindowCornerRadius
            _ = DockyPreferences.shared.effectiveWindowBackgroundImageURL
            _ = DockyPreferences.shared.effectiveWindowBorderColor
            _ = DockyPreferences.shared.effectiveDisablesGlassLook
            _ = DockyPreferences.shared.windowPosition
            self.chrome.refresh()
            self.needsLayout = true
        }.store(in: &subscriptions)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        var size = DockLayoutService.shared.chromeSize
        let prefs = DockyPreferences.shared
        let position = prefs.effectiveWindowPosition.resolved(systemOrientation: DockSettingsService.shared.orientation)
        let growth = DockChromeMetricsService.shared.alongAxisGrowth
        if prefs.effectiveWindowAxisSizing != .fullAxis {
            if position.isVertical { size.height += growth } else { size.width += growth }
        }
        if size.width <= 0 || size.height <= 0 { size = bounds.size }
        let origin: CGPoint
        switch position {
        case .bottom: origin = CGPoint(x: (bounds.width - size.width) / 2, y: bounds.height - size.height)
        case .top: origin = CGPoint(x: (bounds.width - size.width) / 2, y: 0)
        case .left: origin = CGPoint(x: 0, y: (bounds.height - size.height) / 2)
        case .right: origin = CGPoint(x: bounds.width - size.width, y: (bounds.height - size.height) / 2)
        }
        chrome.frame = CGRect(origin: origin, size: size)
        chrome.refresh()
        canvas.frame = bounds
        canvas.needsLayout = true
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
    override func rightMouseDown(with event: NSEvent) {
        if WindowsTaskbarStyle.isActive {
            chrome.rightMouseDown(with: event)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let location = convert(sender.draggingLocation, from: nil)
        let urls = readURLs(from: sender)
        let pasteboardTypes = sender.draggingPasteboard.types?.map(\.rawValue) ?? []
        if let kind = DockDragService.resolvePreview(from: urls) {
            NSLog(
                "[Docky] drag entered: kind=%@ urls=%@ pasteboardTypes=%@",
                Self.describe(kind: kind),
                urls.map(\.path).joined(separator: ", "),
                pasteboardTypes.joined(separator: ", ")
            )
            DockDragService.shared.begin(kind: kind, at: location)
            canvas.updateDropLocation(location)
            updateSystemDragImageVisibility(in: sender)
            return .copy
        }
        if DockEditModeService.shared.paletteDrag != nil {
            NSLog(
                "[Docky] drag entered: kind=palette urls=%@ pasteboardTypes=%@",
                urls.map(\.path).joined(separator: ", "),
                pasteboardTypes.joined(separator: ", ")
            )
            DockDragService.shared.cursorLocation = location
            canvas.updateDropLocation(location)
            updateSystemDragImageVisibility(in: sender)
            return .copy
        }
        NSLog(
            "[Docky] drag entered: kind=rejected urls=%@ pasteboardTypes=%@",
            urls.map(\.path).joined(separator: ", "),
            pasteboardTypes.joined(separator: ", ")
        )
        return []
    }

    /// One-line description of a `DockDragService.Kind` for logging.
    private static func describe(kind: DockDragService.Kind) -> String {
        switch kind {
        case .app(let url, let tile):
            return "app(bundle=\(tile.bundleIdentifier), path=\(url.path))"
        case .folder(let url, _):
            return "folder(path=\(url.path))"
        case .document(let urls):
            return "document(paths=[\(urls.map(\.path).joined(separator: ", "))])"
        }
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let location = convert(sender.draggingLocation, from: nil)
        if DockDragService.shared.kind != nil {
            DockDragService.shared.updateCursor(location)
            canvas.updateDropLocation(location)
            updateSystemDragImageVisibility(in: sender)
            return .copy
        }
        if DockEditModeService.shared.paletteDrag != nil {
            DockDragService.shared.cursorLocation = location
            canvas.updateDropLocation(location)
            updateSystemDragImageVisibility(in: sender)
            return .copy
        }
        return []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        // Cursor left the dock window, but the drag may still be live — the
        // user might be moving into a spring-loaded popover. Drop the
        // location-derived state so previews disappear, but keep `kind`
        // alive so popover-side drop handlers can resolve the source. The
        // drag service is fully cleared in `draggingEnded(_:)` once AppKit
        // tells us the drag is truly over.
        DockDragService.shared.cursorLocation = nil
        DockDragService.shared.destinationIndex = nil
        DockDragService.shared.destinationSection = nil
        DockDragService.shared.documentTargetTileID = nil
        // Keep paletteDrag alive so re-entry works — the AppKit-initiated
        // drag is still in flight outside the window, and the palette item can't be
        // recovered from the pasteboard (which only carries the variant ID).
        DockEditModeService.shared.paletteDropDestination = nil
        restoreSystemDragImage()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        restoreSystemDragImage()
        DockDragService.shared.clear()
    }

    /// Hide the system drag preview when our own insertion preview is active, so the
    /// user sees one drop indication instead of two competing ones. Restore originals
    /// when the active region is exited so the preview returns outside the dock.
    /// Drag-onto-tile (open-with) intentionally keeps the system preview because
    /// there's no insertion indicator competing for attention.
    private func updateSystemDragImageVisibility(in sender: any NSDraggingInfo) {
        let shouldHide =
            DockDragService.shared.destinationIndex != nil
            || DockEditModeService.shared.paletteDropDestination != nil
        if shouldHide {
            guard hiddenDragImageOriginals.isEmpty else { return }
            sender.enumerateDraggingItems(
                options: [],
                for: self,
                classes: [NSPasteboardItem.self],
                searchOptions: [:]
            ) { item, _, _ in
                self.hiddenDragImageOriginals.append(
                    HiddenDragImageSnapshot(item: item, originalProvider: item.imageComponentsProvider)
                )
                item.imageComponentsProvider = { [] }
            }
        } else {
            restoreSystemDragImage()
        }
    }

    private func restoreSystemDragImage() {
        for snapshot in hiddenDragImageOriginals {
            snapshot.item.imageComponentsProvider = snapshot.originalProvider
        }
        hiddenDragImageOriginals.removeAll()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        canvas.updateDropLocation(convert(sender.draggingLocation, from: nil))
        defer { restoreSystemDragImage() }
        if let kind = DockDragService.shared.kind {
            defer { DockDragService.shared.clear() }
            switch kind {
            case .app(_, let tile): return commitAppDrop(tile)
            case .folder(let url, let tile): return commitFolderDrop(url, tile: tile)
            case .document(let urls): return commitDocumentDrop(urls)
            }
        }
        return commitPaletteDrop()
    }

    func readURLs(from sender: any NSDraggingInfo) -> [URL] {
        let pasteboard = sender.draggingPasteboard
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
    }
}
