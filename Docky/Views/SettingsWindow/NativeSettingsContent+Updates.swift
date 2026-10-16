import AppKit
import Combine

extension NativeSettingsContent {
    static func updateSections() -> [NativeSettingsSection] {
        let service = AppUpdateService.shared
        let checks = NativePreferenceField.toggle(
            String(localized: "Automatically Check for Updates"),
            get: { service.automaticallyChecksForUpdates }, set: { service.automaticallyChecksForUpdates = $0 })
        let downloads = NativePreferenceField.toggle(
            String(localized: "Automatically Download Updates"),
            get: { service.automaticallyDownloadsUpdates }, set: { service.automaticallyDownloadsUpdates = $0 })
        let interval = checkIntervalRow()
        let checkNow = NativeActionButton(String(localized: "Check for Updates…")) { service.checkForUpdates() }
        // `AppUpdateService` publishes through Combine, which `observe` doesn't track.
        checks.observe(service.objectWillChange) { [weak checks, weak downloads, weak interval, weak checkNow] in
            (checks?.control as? NSSwitch)?.state = service.automaticallyChecksForUpdates ? .on : .off
            (downloads?.control as? NSSwitch)?.state = service.automaticallyDownloadsUpdates ? .on : .off
            downloads?.isEnabled = service.automaticallyChecksForUpdates
            interval?.isEnabled = service.automaticallyChecksForUpdates
            checkNow?.isEnabled = service.canCheckForUpdates
        }
        return [
            NativeSettingsSection(
                footer: String(localized: "Docky checks getdocky.com for new signed releases."),
                rows: [checks, downloads, interval], actions: [checkNow])
        ]
    }

    private static func checkIntervalRow() -> NativeFormRow {
        let service = AppUpdateService.shared
        let intervals: [TimeInterval] = [3600, 86_400, 604_800, 2_629_800]
        let titles = [
            String(localized: "Hourly"), String(localized: "Daily"), String(localized: "Weekly"),
            String(localized: "Monthly")
        ]
        let popup = NSPopUpButton()
        popup.addItems(withTitles: titles)
        let row = NativeFormRow(title: String(localized: "Check Interval"), control: popup)
        row.bind(popup) {
            if intervals.indices.contains(popup.indexOfSelectedItem) {
                service.updateCheckInterval = intervals[popup.indexOfSelectedItem]
            }
        }
        row.observe(service.objectWillChange) { [weak popup] in
            guard let popup else { return }
            // Keep showing an interval set some other way, such as with `defaults`,
            // as one extra item after the standard ones.
            if let index = intervals.firstIndex(of: service.updateCheckInterval) {
                if popup.numberOfItems > intervals.count { popup.removeItem(at: intervals.count) }
                popup.selectItem(at: index)
            } else {
                let hours = Int((service.updateCheckInterval / 3600).rounded())
                let custom = String(localized: "Every \(hours) Hours")
                if popup.numberOfItems > intervals.count {
                    popup.item(at: intervals.count)?.title = custom
                } else {
                    popup.addItem(withTitle: custom)
                }
                popup.selectItem(at: intervals.count)
            }
        }
        return row
    }
}
