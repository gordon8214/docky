import AppKit
import Combine
import UniformTypeIdentifiers

extension NativeSettingsPaneController {
    func permissionRows() {
        let service = PermissionsService.shared
        add(NativeActionButton(String(localized: "Re-check Permissions")) { service.refresh() })
        for permission in Permission.allCases {
            let status = nativeLabel("", size: 12, color: .secondaryLabelColor)
            let row = NativeFormRow(title: permission.title, control: status)
            let updateStatus = { [weak status] in
                switch service.status(for: permission) {
                case .granted: status?.stringValue = String(localized: "Granted")
                case .denied: status?.stringValue = String(localized: "Denied")
                case .notDetermined: status?.stringValue = String(localized: "Not Requested")
                }
            }
            updateStatus()
            service.objectWillChange.sink { _ in
                DispatchQueue.main.async { updateStatus() }
            }.store(in: &row.subscriptions)
            add(row)
            add(nativeLabel(permission.explanation, size: 12, color: .secondaryLabelColor))
            add(
                nativeStack(
                    [
                        NativeActionButton(String(localized: "Grant Access")) {
                            Task { _ = await service.requestPermission(for: permission) }
                        },
                        NativeActionButton(String(localized: "Open Settings")) {
                            service.openSystemSettings(for: permission)
                        }
                    ], orientation: .horizontal))
            if permission == .finderAutomation || permission == .systemEventsAutomation {
                add(
                    NativeActionButton(String(localized: "Forget Status")) {
                        service.clearAutomationStatus(for: permission)
                    })
            }
        }
    }
    func updateRows() {
        let service = AppUpdateService.shared
        let checks = NSButton(
            checkboxWithTitle: String(localized: "Automatically Check for Updates"), target: nil, action: nil)
        checks.state = service.automaticallyChecksForUpdates ? .on : .off
        let checkRow = NativeFormRow(title: "", control: checks)
        checkRow.bind(checks) { service.automaticallyChecksForUpdates = checks.state == .on }
        add(checkRow)
        let downloads = NSButton(
            checkboxWithTitle: String(localized: "Automatically Download Updates"), target: nil, action: nil)
        downloads.state = service.automaticallyDownloadsUpdates ? .on : .off
        let downloadRow = NativeFormRow(title: "", control: downloads)
        downloadRow.bind(downloads) { service.automaticallyDownloadsUpdates = downloads.state == .on }
        add(downloadRow)
        add(
            NativePreferenceField.number(
                String(localized: "Check Interval (Hours)"), get: { service.updateCheckInterval / 3600 },
                set: { service.updateCheckInterval = $0 * 3600 }, range: 1...168))
        add(NativeActionButton(String(localized: "Check for Updates")) { service.checkForUpdates() })
    }
}
