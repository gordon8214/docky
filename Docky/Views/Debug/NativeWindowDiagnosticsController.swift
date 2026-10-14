import AppKit
import Combine

final class NativeWindowDiagnosticsController: NativeBrowserController {
    let workspace = WorkspaceService.shared
    private let diagnostics = NSTextView()
    private let diagnosticsScroll = NSScrollView()
    override func viewDidLoad() {
        super.viewDidLoad()
        usesList = true
        diagnostics.isEditable = false
        diagnostics.isRichText = false
        diagnostics.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        diagnosticsScroll.documentView = diagnostics
        diagnosticsScroll.hasVerticalScroller = true
        view.addSubview(diagnosticsScroll)
        header.addArrangedSubview(
            NativeActionButton(String(localized: "Force Refresh")) { [weak self] in
                self?.workspace.forceRefreshWindowPreviews()
            })
        onSelection = { [weak self] identifier in self?.showDiagnostics(identifier) }
        onQuickLook = { [weak self] item in self?.showFullPreview(item.id) }
        for publisher in [
            WindowRegistry.shared.objectWillChange.eraseToAnyPublisher(),
            workspace.objectWillChange.eraseToAnyPublisher()
        ] {
            observations.add { [weak self] in
                publisher.sink { [weak self] in DispatchQueue.main.async { self?.refreshWindows() } }

            }
        }
        refreshWindows()
    }
    override func viewDidAppear() {
        super.viewDidAppear()
        refreshWindows()
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        diagnosticsScroll.frame = CGRect(x: 16, y: 12, width: max(0, view.bounds.width - 32), height: 190)
        scroll.frame.origin.y = 212
        scroll.frame.size.height = max(0, view.bounds.height - 276)
        diagnostics.frame.size.width = diagnosticsScroll.contentSize.width
    }
    private func refreshWindows() {
        setItems(
            WindowRegistry.shared.windows.map { window in
                NativeBrowserItem(
                    id: window.windowIdentifier, title: window.windowTitle,
                    detail: window.appDisplayName + " — "
                        + (thumbnailImage(for: window) == nil
                            ? noPreviewReason(for: window) : cachedPreviewKindLabel(for: window)),
                    image: thumbnailImage(for: window),
                    actions: [
                        .action(String(localized: "Copy Diagnostics")) { [weak self] in
                            self?.copyDebugDescription(for: window)
                        },
                        .action(String(localized: "Full-Size Preview")) { [weak self] in
                            self?.showFullPreview(window.windowIdentifier)
                        }
                    ]
                ) { [weak self] in self?.showFullPreview(window.windowIdentifier) }
            })
        if let selectionID { showDiagnostics(selectionID) }
    }
    private func showDiagnostics(_ identifier: String) {
        guard let window = WindowRegistry.shared.windows.first(where: { $0.windowIdentifier == identifier }) else {
            return
        }
        diagnostics.string = debugDescription(for: window)
    }
    private func showFullPreview(_ identifier: String) {
        guard let window = WindowRegistry.shared.windows.first(where: { $0.windowIdentifier == identifier }),
            let image = thumbnailImage(for: window)
        else { return }
        NativeImagePreviewWindowController.shared.show(image, title: window.windowTitle)
    }
}

final class NativeImagePreviewWindowController: NSWindowController, NSWindowDelegate {
    static let shared = NativeImagePreviewWindowController()
    private let imageView = NSImageView()
    private var keyMonitor: Any?
    private init() {
        let window = NSWindow(
            contentRect: .zero, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentView = imageView
        super.init(window: window)
        window.delegate = self
        imageView.imageScaling = .scaleProportionallyUpOrDown
    }
    required init?(coder: NSCoder) { nil }
    func show(_ image: NSImage, title: String) {
        imageView.image = image
        window?.title = title
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 800)
        window?.setContentSize(
            CGSize(
                width: min(screen.width * 0.85, image.size.width), height: min(screen.height * 0.85, image.size.height))
        )
        window?.center()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 && event.type == .keyDown {
                self.close()
                return nil
            }
            if event.type == .leftMouseDown, event.window !== self.window { self.close() }
            return event
        }
        showWindow(nil)
    }
    func windowWillClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        imageView.image = nil
    }
}
