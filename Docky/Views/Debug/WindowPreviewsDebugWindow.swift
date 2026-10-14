import AppKit

final class WindowPreviewsDebugWindowController: NSWindowController {
    static let shared = WindowPreviewsDebugWindowController()
    private init() {
        let browser = NativeWindowDiagnosticsController()
        let window = NSWindow(contentViewController: browser)
        window.title = "Window Previews (Debug)"
        window.setContentSize(CGSize(width: 720, height: 560))
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { nil }
    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
