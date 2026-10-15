import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class NativeControlAction: NSObject {
    var handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func invoke(_ sender: Any?) { handler() }
}

final class NativeFormRow: NSStackView {
    var targets: [NativeControlAction] = []
    var subscriptions = Set<AnyCancellable>()
    init(title: String, control: NSView, accessories: [NSView] = []) {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 12
        let label = nativeLabel(title)
        label.widthAnchor.constraint(equalToConstant: 220).isActive = true
        addArrangedSubview(label)
        if !title.isEmpty { control.setAccessibilityLabel(NSLocalizedString(title, comment: "")) }
        addArrangedSubview(control)
        for accessory in accessories { addArrangedSubview(accessory) }
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { nil }
    func bind(_ control: NSControl, action: @escaping () -> Void) {
        let target = NativeControlAction(action)
        targets.append(target)
        control.target = target
        control.action = #selector(NativeControlAction.invoke(_:))
    }
    func observe(_ update: @escaping @MainActor () -> Void) { observeChanges(update).store(in: &subscriptions) }
}

@MainActor
enum NativePreferenceField {
    static func boolean(_ title: String, _ key: ReferenceWritableKeyPath<DockyPreferences, Bool>) -> NSView {
        let control = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        let row = NativeFormRow(title: title, control: control)
        row.bind(control) { DockyPreferences.shared[keyPath: key] = control.state == .on }
        row.observe { [weak control] in control?.state = DockyPreferences.shared[keyPath: key] ? .on : .off }
        return row
    }
    static func choice<Value: Equatable>(
        _ title: String, _ key: ReferenceWritableKeyPath<DockyPreferences, Value>, values: [Value],
        name: @escaping (Value) -> String
    ) -> NSView {
        let control = NSPopUpButton()
        control.addItems(withTitles: values.map(name))
        let row = NativeFormRow(title: title, control: control)
        row.bind(control) {
            if values.indices.contains(control.indexOfSelectedItem) {
                DockyPreferences.shared[keyPath: key] = values[control.indexOfSelectedItem]
            }
        }
        row.observe { [weak control] in
            control?.selectItem(at: values.firstIndex(of: DockyPreferences.shared[keyPath: key]) ?? 0)
        }
        return row
    }
    static func number<Value: BinaryFloatingPoint & Sendable>(
        _ title: String, _ key: ReferenceWritableKeyPath<DockyPreferences, Value>,
        range: ClosedRange<Double> = 0...10000
    ) -> NSView {
        number(
            title, get: { Double(DockyPreferences.shared[keyPath: key]) },
            set: { DockyPreferences.shared[keyPath: key] = Value($0) }, range: range)
    }
    static func integer<Value: BinaryInteger & Sendable>(
        _ title: String, _ key: ReferenceWritableKeyPath<DockyPreferences, Value>,
        range: ClosedRange<Double> = 0...10000
    ) -> NSView {
        number(
            title, get: { Double(DockyPreferences.shared[keyPath: key]) },
            set: { DockyPreferences.shared[keyPath: key] = Value($0.rounded()) }, range: range)
    }
    static func number(
        _ title: String, get: @escaping () -> Double, set: @escaping (Double) -> Void, range: ClosedRange<Double>
    ) -> NSView {
        let field = NSTextField()
        let formatter = NumberFormatter()
        formatter.minimum = NSNumber(value: range.lowerBound)
        formatter.maximum = NSNumber(value: range.upperBound)
        formatter.maximumFractionDigits = 3
        field.formatter = formatter
        field.widthAnchor.constraint(equalToConstant: 100).isActive = true
        let row = NativeFormRow(title: title, control: field)
        row.bind(field) { set(min(range.upperBound, max(range.lowerBound, field.doubleValue))) }
        row.observe { [weak field] in field?.doubleValue = get() }
        return row
    }
    static func optionalNumber<Value: BinaryFloatingPoint & Sendable>(
        _ title: String, _ key: ReferenceWritableKeyPath<DockyPreferences, Value?>, range: ClosedRange<Double>
    ) -> NSView {
        let field = NSTextField()
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 3
        formatter.minimum = NSNumber(value: range.lowerBound)
        formatter.maximum = NSNumber(value: range.upperBound)
        field.formatter = formatter
        field.widthAnchor.constraint(equalToConstant: 100).isActive = true
        let enable = NSButton(checkboxWithTitle: String(localized: "Override"), target: nil, action: nil)
        let row = NativeFormRow(title: title, control: field, accessories: [enable])
        row.bind(field) {
            DockyPreferences.shared[keyPath: key] = Value(
                min(range.upperBound, max(range.lowerBound, field.doubleValue)))
        }
        row.bind(enable) {
            DockyPreferences.shared[keyPath: key] =
                enable.state == .on ? Value(min(range.upperBound, max(range.lowerBound, field.doubleValue))) : nil
        }
        row.observe { [weak field, weak enable] in
            let value = DockyPreferences.shared[keyPath: key]
            field?.doubleValue = value.map { Double($0) } ?? 0
            field?.isEnabled = value != nil
            enable?.state = value == nil ? .off : .on
        }
        return row
    }
    static func image(_ title: String, _ key: ReferenceWritableKeyPath<DockyPreferences, String?>) -> NSView {
        let button = NativeActionButton(String(localized: "Choose Image…")) {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK { DockyPreferences.shared[keyPath: key] = panel.url?.path }
        }
        let clear = NativeActionButton(String(localized: "Clear")) { DockyPreferences.shared[keyPath: key] = nil }
        return NativeFormRow(title: title, control: button, accessories: [clear])
    }
    /// A shortcut recorder. While `override` returns a shortcut, the row shows
    /// that one instead and can't be edited.
    static func shortcut(
        _ title: String,
        _ key: ReferenceWritableKeyPath<DockyPreferences, KeyboardShortcut>,
        overriddenBy override: (@MainActor () -> KeyboardShortcut?)? = nil
    ) -> NSView {
        let button = NativeShortcutRecorderButton(key: key, overriddenBy: override)
        let clear = NativeActionButton(String(localized: "Clear")) { DockyPreferences.shared[keyPath: key] = .empty }
        let row = NativeFormRow(title: title, control: button, accessories: [clear])
        if let override {
            row.observe { [weak clear] in clear?.isEnabled = override() == nil }
        }
        return row
    }
}

final class NativeShortcutRecorderButton: NSButton {
    private let key: ReferenceWritableKeyPath<DockyPreferences, KeyboardShortcut>
    private let overriddenBy: (@MainActor () -> KeyboardShortcut?)?
    private var recording = false
    private var keyMonitor: Any?
    private var subscriptions = Set<AnyCancellable>()
    override var acceptsFirstResponder: Bool { true }
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
            let value = DockyPreferences.shared[keyPath: self.key]
            let overridden = self.overriddenBy?()
            self.isEnabled = overridden == nil
            if overridden != nil { self.stopRecording() }
            if !self.recording { self.title = (overridden ?? value).displayString }
        }.store(in: &subscriptions)
    }
    required init?(coder: NSCoder) { nil }
    @objc private func record() {
        recording = true
        title = String(localized: "Type Shortcut")
        window?.makeFirstResponder(self)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.recording, self.window?.firstResponder === self else { return event }
            self.keyDown(with: event)
            return nil
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
        title = DockyPreferences.shared[keyPath: key].displayString
        window?.makeFirstResponder(nil)
    }
    private func stopRecording() {
        recording = false
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
    override func resignFirstResponder() -> Bool {
        stopRecording()
        title = DockyPreferences.shared[keyPath: key].displayString
        return super.resignFirstResponder()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopRecording() }
    }

}
