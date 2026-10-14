import AppKit
import Combine

final class NativeWindowBrowserController: NativeBrowserController {
    enum Source { case switcher, preview, debug }
    private let source: Source
    private let focusedImage = NSImageView()
    override func loadView() {
        super.loadView()
        guard source == .switcher else { return }
        let root = NSView()
        root.addSubview(focusedImage)
        root.addSubview(view)
        view = root
        focusedImage.imageScaling = .scaleProportionallyUpOrDown
    }
    override func viewDidAppear() {
        super.viewDidAppear()
        refresh()
    }
    override func viewDidLayout() {
        if source == .switcher {
            let width = min(920, max(300, view.bounds.width - 80))
            let height = min(500, max(200, view.bounds.height - 100))
            browserContentView.frame = CGRect(
                x: (view.bounds.width - width) / 2,
                y: (view.bounds.height - height) / 2, width: width, height: height)
            browserContentView.wantsLayer = true
            browserContentView.layer?.cornerRadius = 18
            browserContentView.layer?.masksToBounds = true
            if let preview = WindowSwitcherService.shared.focusedPreview, let window = view.window {
                let screenRect = window.convertFromScreen(preview.screenBounds)
                focusedImage.frame = view.convert(screenRect, from: nil)
                focusedImage.image = preview.image
                focusedImage.isHidden = false
            } else {
                focusedImage.isHidden = true
            }
        }
        super.viewDidLayout()
    }
    init(source: Source) {
        self.source = source
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidLoad() {
        super.viewDidLoad()
        header.isHidden = true
        onEscape = { [weak self] in
            if self?.source == .switcher {
                WindowSwitcherService.shared.dismiss()
            } else {
                WindowPreviewWindowController.shared.dismissCurrent()
            }
        }
        if source == .switcher {
            let observedPublisher1 = WindowSwitcherService.shared.objectWillChange
            observations.add { [weak self] in
                observedPublisher1.sink { [weak self] in
                    DispatchQueue.main.async { self?.refresh() }
                }
            }
            onSelection = { WindowSwitcherService.shared.selectWindow(withIdentifier: $0) }
        } else {
            let observedPublisher2 = WindowPreviewService.shared.objectWillChange
            observations.add { [weak self] in
                observedPublisher2.sink { [weak self] in
                    DispatchQueue.main.async { self?.refresh() }
                }
            }
            let observedPublisher3 = WindowRegistry.shared.objectWillChange
            observations.add { [weak self] in
                observedPublisher3.sink { [weak self] in DispatchQueue.main.async { self?.refresh() } }

            }
        }
        onContextMenu = { [weak self] presented in
            if self?.source == .switcher {
                WindowSwitcherService.shared.setContextMenuPresented(presented)
            } else {
                WindowPreviewService.shared.setContextMenuPresented(presented)
            }
        }
        refresh()
    }
    private func completeWindowActions(_ window: AppWindow) -> [ContextAction] {
        let workspace = WorkspaceService.shared
        let dismiss = {
            WindowSwitcherService.shared.dismiss()
            WindowPreviewWindowController.shared.dismissCurrent()
        }
        return [
            .action(String(localized: "Focus Window")) {
                _ = workspace.focus(window: window)
                dismiss()
            },
            .action(String(localized: "Close Window"), isDestructive: true) { [weak self] in
                guard workspace.close(window: window) else { return }
                if self?.source == .switcher {
                    WindowSwitcherService.shared.removeWindow(withIdentifier: window.windowIdentifier)
                } else {
                    WindowPreviewService.shared.removeWindow(withIdentifier: window.windowIdentifier)
                }
            },
            .divider
        ] + windowMenuContextActions(for: window, dismiss: dismiss) + [
            .divider,
            .action(String(localized: "Focus App")) {
                workspace.activateOrOpen(bundleIdentifier: window.bundleIdentifier)
                dismiss()
            },
            .action(String(localized: "Hide App")) {
                workspace.hide(bundleIdentifier: window.bundleIdentifier)
                dismiss()
            },
            .action(String(localized: "Quit")) {
                workspace.quit(bundleIdentifier: window.bundleIdentifier)
                dismiss()
            }
        ]
    }
    private func refresh() {
        view.needsLayout = true
        message.stringValue = String(localized: "No windows available")
        let windows: [AppWindow]
        switch source {
        case .switcher:
            windows = WindowSwitcherService.shared.windows
            selectionID = WindowSwitcherService.shared.selectedWindowIdentifier
            usesList = WindowSwitcherService.shared.resolvedLayout == .list
        case .preview:
            windows = WindowPreviewService.shared.windows
            usesList = WindowPreviewService.shared.resolvedLayout == .list
        case .debug: windows = WindowRegistry.shared.windows
        }
        gridSize = CGSize(width: 220, height: 170)
        setItems(
            windows.map { window in
                let image =
                    source == .switcher
                    ? WindowSwitcherService.shared.windowPreview(for: window)
                    : WindowPreviewService.shared.windowPreview(for: window)
                return NativeBrowserItem(
                    id: window.windowIdentifier, title: window.windowTitle, detail: window.appDisplayName,
                    image: image ?? IconCacheService.shared.icon(forBundleIdentifier: window.bundleIdentifier),
                    actions: completeWindowActions(window)
                ) { [weak self] in
                    if self?.source == .switcher {
                        WindowSwitcherService.shared.selectWindow(withIdentifier: window.windowIdentifier)
                        WindowSwitcherService.shared.confirmSelection()
                    } else {
                        _ = WorkspaceService.shared.focus(window: window)
                        WindowPreviewWindowController.shared.dismissCurrent()
                    }
                }
            })
        if source == .switcher, let selectionID,
            let index = displayed.firstIndex(where: { $0.id == selectionID }) {
            if usesList {
                table.scrollRowToVisible(index)
            } else {
                collection.scrollToItems(
                    at: [IndexPath(item: index, section: 0)], scrollPosition: selectionScrollPosition)
            }
        }
    }
}
