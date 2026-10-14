#if DEBUG
import AppKit
import ObjectiveC

/// An independent AppKit window using the same native actions as Window's
/// Fill, Left Half, and Bottom Right Quarter commands. No AX resizing occurs.
@MainActor
enum NativeWindowProbe {
    static func run(reservationSignal: URL? = nil) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: CGRect(x: 100, y: 150, width: 400, height: 300),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Docky Independent Window Regression"
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 100, height: 100)
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let reservationSignal {
                let initial = String(describing: window.screen?.visibleFrame)
                try? Data(initial.utf8).write(to: reservationSignal.appendingPathExtension("ready"), options: .atomic)
                print("Already-running AppKit fixture ready: \(initial)")
                fflush(stdout)
                Task { await waitForReservation(reservationSignal, window: window) }
            } else {
                perform(["_zoomFill:", "_zoomLeft:", "_zoomBottomRight:"], window: window)
            }
        }
        app.run()
        exit(1)
    }

    private static func waitForReservation(_ signal: URL, window: NSWindow) async {
        let deadline = ContinuousClock.now + .seconds(8)
        while !FileManager.default.fileExists(atPath: signal.path) {
            guard ContinuousClock.now < deadline else { window.close(); exit(1) }
            try? await Task.sleep(for: .milliseconds(50))
        }
        perform(["_zoomFill:", "_zoomLeft:", "_zoomBottomRight:"], window: window)
    }

    private static func matchesNativeAction(_ action: String, frame: CGRect, visible: CGRect) -> Bool {
        guard visible.insetBy(dx: -1, dy: -1).contains(frame) else { return false }
        let expected: CGRect
        switch action {
        case "_zoomLeft:":
            expected = CGRect(x: visible.minX, y: visible.minY, width: visible.width / 2, height: visible.height)
        case "_zoomBottomRight:":
            expected = CGRect(x: visible.midX, y: visible.minY, width: visible.width / 2, height: visible.height / 2)
        default: expected = visible
        }
        // Allow the native tiling margin and its inter-window gap, but never
        // accept a full-sized window for a half/quarter action.
        let tolerance: CGFloat = min(32, min(expected.width, expected.height) * 0.1)
        return abs(frame.minX - expected.minX) <= tolerance && abs(frame.minY - expected.minY) <= tolerance
            && abs(frame.width - expected.width) <= tolerance && abs(frame.height - expected.height) <= tolerance
    }

    private static func perform(_ actions: [String], window: NSWindow) {
        guard let name = actions.first else {
            window.close()
            exit(0)
        }
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(NSWindow.self, selector),
              method_getNumberOfArguments(method) == 3,
              let encoding = method_getTypeEncoding(method), encoding.pointee == CChar(118) else {
            fputs("Native window action is unavailable\n", stderr)
            exit(1)
        }
        let invoke = unsafeBitCast(method_getImplementation(method),
                                  to: (@convention(c) (AnyObject, Selector, AnyObject?) -> Void).self)
        invoke(window, selector, nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard let screen = window.screen else { exit(1) }
            print("\(name) frame=\(window.frame) visible=\(screen.visibleFrame)")
            fflush(stdout)
            guard matchesNativeAction(name, frame: window.frame, visible: screen.visibleFrame) else {
                fputs("Native tiling ignored the requested action or overlapped the reserved edge\n", stderr)
                window.close()
                exit(1)
            }
            perform(Array(actions.dropFirst()), window: window)
        }
    }
}
#endif
