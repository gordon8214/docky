import Foundation

/// The panes in the Settings sidebar, in order.
enum SettingsPane: String, CaseIterable, Sendable {
    case general
    case profiles
    case taskbar
    case appIcons
    case hiddenApps
    case widgets
    case launchpad
    case startMenu
    case windowManagement
    case menuExtras
    case actions
    case permissions
    case updates

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .profiles: String(localized: "Profiles")
        case .taskbar: String(localized: "Taskbar")
        case .appIcons: String(localized: "App Icons")
        case .hiddenApps: String(localized: "Hidden Apps")
        case .widgets: String(localized: "Widgets")
        case .launchpad: String(localized: "Launchpad")
        case .startMenu: String(localized: "Start Menu")
        case .windowManagement: String(localized: "Window Management")
        case .menuExtras: String(localized: "Menu Extras")
        case .actions: String(localized: "Actions")
        case .permissions: String(localized: "Permissions")
        case .updates: String(localized: "Updates")
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .profiles: "person.crop.rectangle.stack"
        case .taskbar: "menubar.dock.rectangle"
        case .appIcons: "app.badge"
        case .hiddenApps: "eye.slash"
        case .widgets: "puzzlepiece.extension"
        case .launchpad: "square.grid.3x3.fill"
        case .startMenu: "square.grid.2x2"
        case .windowManagement: "rectangle.on.rectangle"
        case .menuExtras: "menubar.rectangle"
        case .actions: "list.bullet.rectangle"
        case .permissions: "lock.shield"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }
}
