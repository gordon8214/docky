import AppKit

extension NativeSettingsFields {
    static func menuExtrasRows() -> [NSView] {
        let bridge = MenuExtrasNativeBridge.shared
        let checkbox = NSButton(checkboxWithTitle: "Show Menu Extras", target: nil, action: nil)
        checkbox.identifier = NSUserInterfaceItemIdentifier("nativeMenuExtras")
        let row = NativeFormRow(title: "", control: checkbox)
        row.bind(checkbox) { bridge.enabled = checkbox.state == .on }
        row.observe { [weak checkbox] in checkbox?.state = bridge.enabled ? .on : .off }
        let status = NSTextField(wrappingLabelWithString: "")
        status.preferredMaxLayoutWidth = 300
        let statusRow = NativeFormRow(title: "Status", control: status)
        statusRow.observe { [weak status] in status?.stringValue = bridge.message }
        return [
            row,
            NSTextField(wrappingLabelWithString:
                "Show native macOS menu extras, including Battery, Volume, and Wi-Fi, in the Windows taskbar. "
                    + "Turn this off to remove these icons. "
                    + "Native hosting is experimental."),
            statusRow
        ]
    }
}
