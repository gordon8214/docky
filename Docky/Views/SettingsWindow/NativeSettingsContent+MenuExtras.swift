import AppKit

extension NativeSettingsContent {
    static func menuExtrasSections() -> [NativeSettingsSection] {
        let bridge = MenuExtrasNativeBridge.shared
        let toggle = NativePreferenceField.toggle(
            String(localized: "Show Menu Extras"), get: { bridge.enabled }, set: { bridge.enabled = $0 })
        toggle.control.identifier = NSUserInterfaceItemIdentifier("nativeMenuExtras")
        let status = NativeFormTextRow("", secondary: true)
        status.observe { [weak status] in status?.text = bridge.message }
        return [
            NativeSettingsSection(
                footer: String(
                    localized:
                        "Shows native macOS menu extras, including Battery, Volume, and Wi-Fi, in the taskbar. Native hosting is experimental."),
                rows: [toggle, status])
        ]
    }
}
