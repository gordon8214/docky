import AppKit
import Combine

final class NativeProfileSwitcherController: NSViewController {
    var onActiveChange: ((Bool) -> Void)?
    private let stack = NSStackView()
    private let scroll = NSScrollView()
    private var position: ResolvedDockWindowPosition = .bottom
    private var availableLength: CGFloat = 400
    private var subscriptions = Set<AnyCancellable>()
    override func loadView() {
        let material = NativeHoverMaterialView()
        material.onHover = { [weak self] in self?.onActiveChange?($0) }
        material.material = .popover
        material.blendingMode = .behindWindow
        material.wantsLayer = true
        material.layer?.cornerRadius = 12
        material.layer?.masksToBounds = true
        view = material
        scroll.drawsBackground = false
        scroll.documentView = stack
        view.addSubview(scroll)
        observeChanges { [weak self] in
            _ = ProfileService.shared.profiles
            _ = ProfileService.shared.activeProfileID
            self?.refresh()
        }.store(in: &subscriptions)
    }
    func configure(position: ResolvedDockWindowPosition, availableLength: CGFloat) {
        self.position = position
        self.availableLength = availableLength
        _ = view
        refresh()
    }
    private func refresh() {
        for child in stack.arrangedSubviews {
            stack.removeArrangedSubview(child)
            child.removeFromSuperview()
        }
        stack.orientation = position.isVertical ? .vertical : .horizontal
        stack.spacing = 6
        for profile in ProfileService.shared.profiles {
            let button = NativeActionButton(profile.name, symbol: profile.symbolName) {
                ProfileService.shared.setActiveProfile(id: profile.id)
            }
            button.state = ProfileService.shared.activeProfileID == profile.id ? .on : .off
            button.setAccessibilityValue(button.state == .on ? String(localized: "Selected") : "")
            stack.addArrangedSubview(button)
        }
        let natural = stack.fittingSize
        let size =
            position.isVertical
            ? CGSize(width: max(100, natural.width + 12), height: min(availableLength, natural.height + 12))
            : CGSize(width: min(availableLength, natural.width + 12), height: max(32, natural.height + 12))
        preferredContentSize = size
        view.setFrameSize(size)
        scroll.frame = view.bounds.insetBy(dx: 6, dy: 6)
        stack.setFrameSize(natural)
    }
}

final class NativeDockHintController: NSViewController {
    var onDismiss: (() -> Void)?
    override func loadView() {
        let stack = nativeStack(
            [
                NativeActionButton(String(localized: "Edit Taskbar"), symbol: "slider.horizontal.3") {
                    DockEditModeService.shared.enter()
                },
                NativeActionButton("", symbol: "xmark") { [weak self] in self?.onDismiss?() }
            ], orientation: .horizontal)
        stack.edgeInsets = NSEdgeInsets(top: 9, left: 14, bottom: 9, right: 14)
        view = stack
    }
}

final class NativeProgressChipController: NSViewController {
    private var subscriptions = Set<AnyCancellable>()
    override func loadView() {
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        let label = nativeLabel(SmartOrganizeProgressService.shared.message, size: 12, weight: .medium)
        let stack = nativeStack([spinner, label], orientation: .horizontal)
        stack.edgeInsets = NSEdgeInsets(top: 9, left: 14, bottom: 9, right: 14)
        view = stack
        SmartOrganizeProgressService.shared.$message.sink { [weak label] in label?.stringValue = $0 }.store(
            in: &subscriptions)
    }
}

private final class NativeDockEditorBrowserController: NativeBrowserController {
    private var palette: [String: (DockEditPaletteItem, TileSpan?)] = [:]
    override func viewDidLoad() {
        super.viewDidLoad()
        gridSize = CGSize(width: 160, height: 120)
        header.addArrangedSubview(NativeActionButton(String(localized: "Done")) { DockEditModeService.shared.exit() })
        onEscape = { DockEditModeService.shared.exit() }
        var result: [NativeBrowserItem] = []
        func append(_ item: DockEditPaletteItem, title: String, symbol: String, span: TileSpan? = nil) {
            let id = item.id + ":\(span?.rawValue ?? 0)"
            palette[id] = (item, span)
            result.append(
                NativeBrowserItem(
                    id: id, title: title, detail: span.map { "\($0.rawValue) Tiles" } ?? "",
                    image: NSImage(systemSymbolName: symbol, accessibilityDescription: title)
                ) {
                    if let pinned = DockTileGeometry.makePinnedItem(from: item, widgetSpan: span) {
                        TileStore.shared.insertPinnedItem(pinned, at: DockyPreferences.shared.pinnedItems.count)
                    }
                })
        }
        append(.launchpad, title: String(localized: "Launchpad"), symbol: "square.grid.3x3")
        append(.startMenu, title: String(localized: "Start Menu"), symbol: "square.grid.2x2")
        append(.smartStack, title: String(localized: "Smart Stack"), symbol: "square.stack")
        for registration in WidgetCatalog.paletteRegistrations {
            for span in registration.kind.supportedSpans.filter({ $0 != .four }) {
                append(
                    .widget(ownerBundleIdentifier: registration.ownerBundleIdentifier, kind: registration.kind),
                    title: registration.kind.title, symbol: "puzzlepiece.extension", span: span)
            }
        }
        setItems(result)
    }
    override func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath)
        -> NSPasteboardWriting? {
        guard displayed.indices.contains(indexPath.item), let entry = palette[displayed[indexPath.item].id] else {
            return nil
        }
        DockEditModeService.shared.beginPaletteDrag(item: entry.0, widgetSpan: entry.1)
        let writer = NSPasteboardItem()
        writer.setString(displayed[indexPath.item].id, forType: .string)
        return writer
    }
    func collectionView(
        _ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint,
        dragOperation operation: NSDragOperation
    ) { DockEditModeService.shared.endPaletteDrag() }
}

final class NativeDockEditorController: NSViewController {
    var dockFrame: CGRect = .zero { didSet { if isViewLoaded { view.needsLayout = true } } }
    private let browser = NativeDockEditorBrowserController()
    override func loadView() {
        let background = NativeEditorBackgroundView()
        background.onDismiss = { DockEditModeService.shared.exit() }
        view = background
        addChild(browser)
        view.addSubview(browser.view)
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        let width = min(1000, max(320, view.bounds.width - 48))
        let height = min(480, max(240, view.bounds.height - 120))
        let position = DockyPreferences.shared.effectiveWindowPosition.resolved(
            systemOrientation: DockSettingsService.shared.orientation)
        let origin: CGPoint
        switch position {
        case .bottom:
            origin = CGPoint(
                x: (view.bounds.width - width) / 2, y: min(view.bounds.height - height - 24, dockFrame.height + 24))
        case .top:
            origin = CGPoint(
                x: (view.bounds.width - width) / 2, y: max(24, view.bounds.height - height - dockFrame.height - 24))
        case .left:
            origin = CGPoint(
                x: min(view.bounds.width - width - 24, dockFrame.width + 24), y: (view.bounds.height - height) / 2)
        case .right:
            origin = CGPoint(
                x: max(24, view.bounds.width - width - dockFrame.width - 24), y: (view.bounds.height - height) / 2)
        }
        browser.view.frame = CGRect(origin: origin, size: CGSize(width: width, height: height))
    }
}
private final class NativeEditorBackgroundView: NSView {
    var onDismiss: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onDismiss?() }
}
