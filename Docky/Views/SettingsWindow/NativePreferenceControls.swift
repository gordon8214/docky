import AppKit

/// Holds a closure as a control's target, since `NSControl.target` is weak.
@MainActor
final class NativeControlAction: NSObject {
    var handler: @MainActor () -> Void
    init(_ handler: @escaping @MainActor () -> Void) { self.handler = handler }
    @objc func invoke(_ sender: Any?) { handler() }
}

/// Rows bound to a preference: the control writes the value, and the row
/// follows changes made anywhere else.
@MainActor
enum NativePreferenceField {
    static func toggle(
        _ title: String, description: String? = nil, _ key: ReferenceWritableKeyPath<DockyPreferences, Bool>
    ) -> NativeFormRow {
        toggle(
            title, description: description, get: { DockyPreferences.shared[keyPath: key] },
            set: { DockyPreferences.shared[keyPath: key] = $0 })
    }

    static func toggle(
        _ title: String, description: String? = nil, get: @escaping @MainActor () -> Bool,
        set: @escaping @MainActor (Bool) -> Void
    ) -> NativeFormRow {
        let control = NSSwitch()
        control.controlSize = NativeSettingsMetrics.switchControlSize
        let row = NativeFormRow(title: title, description: description, control: control)
        row.bind(control) { set(control.state == .on) }
        row.observe { [weak control] in control?.state = get() ? .on : .off }
        return row
    }

    static func choice<Value: Equatable>(
        _ title: String, description: String? = nil, _ key: ReferenceWritableKeyPath<DockyPreferences, Value>,
        values: [Value], name: @escaping (Value) -> String
    ) -> NativeFormRow {
        choice(
            title, description: description, get: { DockyPreferences.shared[keyPath: key] },
            set: { DockyPreferences.shared[keyPath: key] = $0 }, values: values, name: name)
    }

    static func choice<Value: Equatable>(
        _ title: String, description: String? = nil, get: @escaping @MainActor () -> Value,
        set: @escaping @MainActor (Value) -> Void, values: [Value], name: @escaping (Value) -> String
    ) -> NativeFormRow {
        let control = NSPopUpButton()
        control.addItems(withTitles: values.map(name))
        let row = NativeFormRow(title: title, description: description, control: control)
        row.bind(control) {
            if values.indices.contains(control.indexOfSelectedItem) { set(values[control.indexOfSelectedItem]) }
        }
        row.observe { [weak control] in control?.selectItem(at: values.firstIndex(of: get()) ?? 0) }
        return row
    }
}
