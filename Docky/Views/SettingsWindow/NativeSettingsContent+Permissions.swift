import AppKit
import Combine

extension NativeSettingsContent {
    static func permissionSections(_ context: NativeSettingsContext) -> [NativeSettingsSection] {
        let service = PermissionsService.shared
        context.onAppear { service.refresh() }
        let checkAgain = NativeActionButton(String(localized: "Check Again")) { service.refresh() }
        return Permission.allCases.map(permissionSection) + [NativeSettingsSection(actions: [checkAgain])]
    }

    private static func permissionSection(_ permission: Permission) -> NativeSettingsSection {
        let service = PermissionsService.shared
        let status = nativeValueLabel()
        let request = NativeActionButton(String(localized: "Request Access")) {
            Task { _ = await service.requestPermission(for: permission) }
        }
        let open = NativeActionButton(String(localized: "Open System Settings")) {
            service.openSystemSettings(for: permission)
        }
        let title = NSLocalizedString(permission.title, comment: "")
        request.setAccessibilityLabel(String(localized: "Request \(title) Access"))
        open.setAccessibilityLabel(String(localized: "Open \(title) in System Settings"))
        let row = NativeFormRow(title: String(localized: "Status"), control: status, accessories: [request, open])
        status.setAccessibilityLabel(String(localized: "\(title) Status"))
        row.observe(service.objectWillChange) { [weak status, weak request] in
            switch service.status(for: permission) {
            case .granted:
                status?.stringValue = String(localized: "Granted")
                status?.textColor = .systemGreen
            case .denied:
                status?.stringValue = String(localized: "Denied")
                status?.textColor = .systemOrange
            case .notDetermined:
                status?.stringValue = String(localized: "Not Requested")
                status?.textColor = .secondaryLabelColor
            }
            // macOS asks only once, so after a denial the user decides in System
            // Settings. Accessibility prompts again; Full Disk Access never prompts.
            let status = service.status(for: permission)
            let canPrompt =
                permission == .accessibility ? status != .granted
                : permission != .userFolders && status == .notDetermined
            request?.isHidden = !canPrompt
        }
        var actions: [NSView] = []
        if permission == .finderAutomation || permission == .systemEventsAutomation {
            actions.append(
                NativeActionButton(String(localized: "Forget Status")) { service.clearAutomationStatus(for: permission) })
        }
        return NativeSettingsSection(
            title, footer: NSLocalizedString(permission.explanation, comment: ""), rows: [row], actions: actions)
    }
}
