import AppKit
import UniformTypeIdentifiers

extension NativePreferenceField {
    /// A chosen image file, with Choose… and Clear. The description shows the
    /// file's name once one is chosen, and `description` until then.
    static func image(
        _ title: String, description: String? = nil, _ key: ReferenceWritableKeyPath<DockyPreferences, String?>,
        sheets: NativeSheetPresenter
    ) -> NativeFormRow {
        let choose = NativeActionButton(String(localized: "Choose…")) {
            Task {
                guard let url = await sheets.chooseFile([.image]) else { return }
                DockyPreferences.shared[keyPath: key] = url.path
            }
        }
        let clear = NativeActionButton(String(localized: "Clear")) { DockyPreferences.shared[keyPath: key] = nil }
        let row = NativeFormRow(title: title, description: description, control: choose, accessories: [clear])
        let update: @MainActor () -> Void = { [weak row, weak clear] in
            let path = DockyPreferences.shared[keyPath: key]
            row?.descriptionText = path.map { FileManager.default.displayName(atPath: $0) } ?? description
            clear?.isEnabled = (row?.effectiveEnabled ?? true) && path != nil
        }
        row.observe(update)
        row.onEnabledChange = { _ in update() }
        return row
    }

    /// A shortcut recorder and Clear. While `override` returns a shortcut, the
    /// row shows that one instead and can't be edited.
    static func shortcut(
        _ title: String, description: String? = nil,
        _ key: ReferenceWritableKeyPath<DockyPreferences, KeyboardShortcut>,
        overriddenBy override: (@MainActor () -> KeyboardShortcut?)? = nil
    ) -> NativeFormRow {
        let button = NativeShortcutRecorderButton(key: key, overriddenBy: override)
        let clear = NativeActionButton(String(localized: "Clear")) { DockyPreferences.shared[keyPath: key] = .empty }
        let row = NativeFormRow(title: title, description: description, control: button, accessories: [clear])
        let update: @MainActor () -> Void = { [weak row, weak clear] in
            clear?.isEnabled =
                (row?.effectiveEnabled ?? true) && override?() == nil && DockyPreferences.shared[keyPath: key] != .empty
        }
        row.observe(update)
        row.onEnabledChange = { _ in update() }
        return row
    }

    /// A recorder for a single key, such as the switcher's close-window key.
    static func key(
        _ title: String, description: String? = nil, _ key: ReferenceWritableKeyPath<DockyPreferences, UInt16>
    ) -> NativeFormRow {
        NativeFormRow(title: title, description: description, control: NativeKeyRecorderButton(key: key))
    }
}
