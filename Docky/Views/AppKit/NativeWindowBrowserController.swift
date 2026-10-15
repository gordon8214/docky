import AppKit
import Combine

/// Grid or list of windows for the dock's hover previews (macOS themes) and
/// the debug window list. The window switcher uses `WindowSwitcherController`.
final class NativeWindowBrowserController: NativeBrowserController {
    enum Source { case preview, debug }
    private let source: Source
    init(source: Source) {
        self.source = source
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidAppear() {
        super.viewDidAppear()
        refresh()
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        header.isHidden = true
        onEscape = { WindowPreviewWindowController.shared.dismissCurrent() }
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
        onContextMenu = { presented in
            WindowPreviewService.shared.setContextMenuPresented(presented)
        }
        refresh()
    }
    private func refresh() {
        view.needsLayout = true
        message.stringValue = String(localized: "No windows available")
        let windows: [AppWindow]
        switch source {
        case .preview:
            windows = WindowPreviewService.shared.windows
            usesList = WindowPreviewService.shared.resolvedLayout == .list
        case .debug: windows = WindowRegistry.shared.windows
        }
        gridSize = CGSize(width: 220, height: 170)
        setItems(
            windows.map { window in
                let image = WindowPreviewService.shared.windowPreview(for: window)
                return NativeBrowserItem(
                    id: window.windowIdentifier, title: window.windowTitle, detail: window.appDisplayName,
                    image: image ?? IconCacheService.shared.icon(forBundleIdentifier: window.bundleIdentifier),
                    actions: windowCardContextActions(
                        for: window,
                        onClosed: {
                            WindowPreviewService.shared.removeWindow(withIdentifier: window.windowIdentifier)
                        },
                        dismiss: { WindowPreviewWindowController.shared.dismissCurrent() }
                    )
                ) {
                    _ = WorkspaceService.shared.focus(window: window)
                    WindowPreviewWindowController.shared.dismissCurrent()
                }
            })
    }
}
