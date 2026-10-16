import AppKit

/// Builds each settings pane's sections. Each pane lives in its own
/// `NativeSettingsContent+<Pane>.swift` file.
@MainActor
enum NativeSettingsContent {
    static func sections(for pane: SettingsPane, context: NativeSettingsContext) -> [NativeSettingsSection] {
        switch pane {
        case .general: generalSections(context)
        case .profiles: profileSections(context)
        case .taskbar: taskbarSections(context)
        case .appIcons: []
        case .hiddenApps: hiddenAppSections(context)
        case .widgets: widgetSections()
        case .launchpad: launchpadSections(context)
        case .startMenu: startMenuSections()
        case .windowManagement: windowManagementSections()
        case .menuExtras: menuExtrasSections()
        case .actions: actionSections()
        case .permissions: permissionSections(context)
        case .updates: updateSections()
        }
    }
}
