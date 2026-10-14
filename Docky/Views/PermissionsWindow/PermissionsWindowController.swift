import AppKit

final class PermissionsWindowController: NSWindowController {
    var onComplete: (() -> Void)?
    convenience init(steps: [Permission]) {
        let controller = NativePermissionsController(steps: steps)
        let window = NSWindow(contentViewController: controller)
        window.title = String(localized: "Welcome to Docky")
        window.setContentSize(CGSize(width: 760, height: 580))
        window.styleMask = [.titled]
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        controller.onComplete = { [weak self] in
            self?.close()
            self?.onComplete?()
        }
    }
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        if let controller = window?.contentViewController as? NativePermissionsController, controller.steps.isEmpty {
            close()
            onComplete?()
        }
    }
}
