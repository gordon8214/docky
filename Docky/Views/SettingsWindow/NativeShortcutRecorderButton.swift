import AppKit
import Combine

final class NativeShortcutRecorderButton: NSButton {
    private let key: ReferenceWritableKeyPath<DockyPreferences, KeyboardShortcut>
    private let overriddenBy: (@MainActor () -> KeyboardShortcut?)?
    private var recording = false
    private var keyMonitor: Any?
    private var resignKeyObserver: NSObjectProtocol?
    private var subscriptions = Set<AnyCancellable>()
    /// What the row asked for. The recorder also stays disabled while overridden.
    private var requestedEnabled = true
    override var acceptsFirstResponder: Bool { super.isEnabled }
    override var isEnabled: Bool {
        get { super.isEnabled }
        set {
            requestedEnabled = newValue
            applyEnabled()
        }
    }
    init(
        key: ReferenceWritableKeyPath<DockyPreferences, KeyboardShortcut>,
        overriddenBy: (@MainActor () -> KeyboardShortcut?)? = nil
    ) {
        self.key = key
        self.overriddenBy = overriddenBy
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(record)
        observeChanges { [weak self] in
            guard let self else { return }
            let overridden = self.overriddenBy?()
            self.applyEnabled()
            if overridden != nil { self.stopRecording() }
            if !self.recording { self.showShortcut() }
        }.store(in: &subscriptions)
    }
    required init?(coder: NSCoder) { nil }
    private func applyEnabled() {
        super.isEnabled = requestedEnabled && overriddenBy?() == nil
    }

    /// Shows the shortcut in effect: the override while there is one, otherwise the saved shortcut.
    private func showShortcut() {
        title = (overriddenBy?() ?? DockyPreferences.shared[keyPath: key]).displayString
    }

    @objc private func record() {
        stopRecording()
        recording = true
        title = String(localized: "Type Shortcut")
        window?.makeFirstResponder(self)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.recording, self.window?.isKeyWindow == true, self.window?.firstResponder === self
            else { return event }
            self.keyDown(with: event)
            return nil
        }
        // Another Docky window, such as Launchpad, taking the keyboard ends recording,
        // so its keystrokes aren't recorded here.
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopRecording()
                self?.showShortcut()
            }
        }
    }
    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode != 53, let shortcut = KeyboardShortcut.from(event: event) {
            DockyPreferences.shared[keyPath: key] = shortcut
        }
        stopRecording()
        showShortcut()
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
        showShortcut()
        return super.resignFirstResponder()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopRecording() }
    }

}
