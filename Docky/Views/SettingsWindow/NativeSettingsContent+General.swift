import AppKit

extension NativeSettingsContent {
    static func generalSections(_ context: NativeSettingsContext) -> [NativeSettingsSection] {
        [
            NativeSettingsSection(rows: [
                NativePreferenceField.toggle(
                    String(localized: "Open at Login"),
                    description: String(
                        localized: "Registers Docky as a login item so it starts automatically after you sign in."),
                    \.opensAtLogin),
                fileBrowserRow()
            ]),
            systemDockSection()
        ]
    }

    /// File browsers that aren't installed stay listed but can't be chosen. A saved choice that
    /// isn't installed stays selected, and `FileBrowserService` uses Finder until it is.
    static func fileBrowserRow() -> NativeFormRow {
        let browsers = FileBrowser.allCases
        let control = NSPopUpButton()
        control.autoenablesItems = false
        for browser in browsers {
            let isInstalled = FileBrowserService.shared.isInstalled(browser)
            control.addItem(
                withTitle: isInstalled
                    ? browser.displayName
                    : String(
                        localized: "\(browser.displayName) (Not Installed)",
                        comment: "A file browser app's name, followed by a note that it isn't installed"))
            control.lastItem?.isEnabled = isInstalled
        }
        let row = NativeFormRow(
            title: String(localized: "File Browser"),
            description: String(localized: "The app that opens folders and the Trash from the taskbar."),
            control: control)
        row.bind(control) {
            if browsers.indices.contains(control.indexOfSelectedItem) {
                DockyPreferences.shared.fileBrowser = browsers[control.indexOfSelectedItem]
            }
        }
        row.observe { [weak control] in
            control?.selectItem(at: browsers.firstIndex(of: DockyPreferences.shared.fileBrowser) ?? 0)
        }
        return row
    }

    private static func systemDockSection() -> NativeSettingsSection {
        let status = nativeValueLabel()
        let retry = NativeActionButton(String(localized: "Retry")) { WindowReservationService.shared.retryIntegration() }
        retry.setAccessibilityLabel(String(localized: "Retry system Dock integration"))
        let row = NativeFormRow(title: String(localized: "System Integration"), control: status, accessories: [retry])
        row.observe { [weak row, weak status, weak retry] in
            let service = WindowReservationService.shared
            let connected = service.backendStatus.contains("verified")
            let error = service.lastError
            if error != nil {
                status?.stringValue = String(localized: "Needs attention")
                status?.textColor = .systemOrange
            } else if connected {
                status?.stringValue = String(localized: "Connected")
                status?.textColor = .systemGreen
            } else {
                status?.stringValue = String(localized: "Connecting…")
                status?.textColor = .secondaryLabelColor
            }
            status?.toolTip = error ?? service.backendDetails
            row?.descriptionText = error
            retry?.isHidden = error == nil
        }
        return NativeSettingsSection(
            String(localized: "System Dock"),
            footer: String(
                localized:
                    "Docky replaces the system Dock while running. Your original Dock settings are restored when Docky quits."),
            rows: [row])
    }
}
