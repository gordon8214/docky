import Foundation

enum PermissionStatus {
    case granted
    case denied
    case notDetermined
}

enum GrantMethod {
    case fullDiskAccess
    case automation
    case accessibility
    case screenCapture
    case location
}

enum Permission: String, CaseIterable, Identifiable {
    case userFolders
    case finderAutomation
    case accessibility
    case systemEventsAutomation
    case screenCapture
    case location
    case calendar
    case reminders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userFolders: return "Full Disk Access"
        case .finderAutomation: return "Automation (Finder)"
        case .accessibility: return "Accessibility"
        case .systemEventsAutomation: return "Automation (System Events)"
        case .screenCapture: return "Screen Recording"
        case .location: return "Location"
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        }
    }

    var explanation: String {
        switch self {
        case .userFolders:
            return "Grant Full Disk Access so Docky can preview recent items from folders pinned to the "
                + "Dock, including protected locations like Downloads, Documents, and Desktop. No data "
                + "leaves your Mac."
        case .finderAutomation:
            return "Docky uses Finder automation for reveal-in-Finder, open-folder, and Trash actions. "
                + "macOS grants this separately from Full Disk Access, and you can request it here "
                + "without waiting for the first Finder action to fail."
        case .accessibility:
            return "Accessibility access lets Docky click menu bar items for curated menuClick actions, "
                + "inspect app windows for Dock-like reopen behavior and window menus, and restore "
                + "minimized windows beside the Trash. These actions are slower and more fragile than "
                + "built-in actions, so Docky requests this only when needed."
        case .systemEventsAutomation:
            return "Docky uses System Events automation for curated menuClick actions. Requesting it here "
                + "lets Docky click supported app menus without waiting for the first action to trigger a "
                + "macOS prompt. Menu-click actions still require Accessibility too."
        case .screenCapture:
            return "Grant Screen Recording so Docky can show window previews. Nothing leaves your Mac. "
                + "macOS may require quitting and reopening Docky after you allow this."
        case .location:
            return "Grant location access so Docky can show local weather in the Weather widget. Your "
                + "location is used on-device to fetch the forecast and is not stored by Docky."
        case .calendar:
            return "Grant Calendar access so the Calendar widget can show your upcoming events. Events are "
                + "read on-device and never leave your Mac."
        case .reminders:
            return "Grant Reminders access so the Reminders widget can show your open tasks. Reminders are "
                + "read on-device and never leave your Mac."
        }
    }

    var systemSettingsURL: URL? {
        switch self {
        case .userFolders:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        case .finderAutomation:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        case .systemEventsAutomation:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .screenCapture:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case .location:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
        case .calendar:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        case .reminders:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")
        }
    }

    var isRequiredAtLaunch: Bool {
        switch self {
        case .userFolders:
            return true
        case .finderAutomation:
            return false
        case .systemEventsAutomation:
            return false
        case .accessibility:
            return true
        case .screenCapture:
            return false
        case .location:
            return false
        case .calendar:
            return false
        case .reminders:
            return false
        }
    }

    /// Whether this permission is surfaced during the initial onboarding
    /// flow. Widget-tied permissions (calendar, reminders, location) are
    /// requested lazily from the widget itself the first time it renders,
    /// so they never appear in onboarding; only app-feature permissions do.
    var appearsInOnboarding: Bool {
        switch self {
        case .userFolders, .finderAutomation, .accessibility, .systemEventsAutomation, .screenCapture:
            return true
        case .location, .calendar, .reminders:
            return false
        }
    }
}
