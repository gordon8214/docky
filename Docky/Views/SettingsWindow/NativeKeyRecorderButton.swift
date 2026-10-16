import AppKit
import Combine

final class NativeKeyRecorderButton: NSButton {
    private let key: ReferenceWritableKeyPath<DockyPreferences, UInt16>
    private var recording = false
    private var keyMonitor: Any?
    private var resignKeyObserver: NSObjectProtocol?
    private var subscription: AnyCancellable?
    override var acceptsFirstResponder: Bool { isEnabled }
    init(key: ReferenceWritableKeyPath<DockyPreferences, UInt16>) {
        self.key = key
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(record)
        subscription = observeChanges { [weak self] in
            guard let self else { return }
            if !self.recording {
                self.title = KeyboardShortcut.keyDisplayString(for: DockyPreferences.shared[keyPath: self.key])
            }
        }
    }
    required init?(coder: NSCoder) { nil }
    @objc private func record() {
        stopRecording()
        recording = true
        title = String(localized: "Type Key")
        window?.makeFirstResponder(self)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.recording, self.window?.isKeyWindow == true, self.window?.firstResponder === self
            else { return event }
            self.keyDown(with: event)
            return nil
        }
        // Another Docky window taking the keyboard ends recording, so its keystrokes aren't recorded here.
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.stopRecording()
                self.title = KeyboardShortcut.keyDisplayString(for: DockyPreferences.shared[keyPath: self.key])
            }
        }
    }
    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode != 53 { DockyPreferences.shared[keyPath: key] = event.keyCode }
        stopRecording()
        title = KeyboardShortcut.keyDisplayString(for: DockyPreferences.shared[keyPath: key])
        window?.makeFirstResponder(nil)
    }
    private func stopRecording() {
        recording = false
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let resignKeyObserver { NotificationCenter.default.removeObserver(resignKeyObserver) }
        resignKeyObserver = nil
    }
    override func resignFirstResponder() -> Bool {
        stopRecording()
        title = KeyboardShortcut.keyDisplayString(for: DockyPreferences.shared[keyPath: key])
        return super.resignFirstResponder()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopRecording() }
    }

}
