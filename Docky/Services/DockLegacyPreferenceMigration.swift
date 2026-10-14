import Foundation

enum DockLegacyPreferenceMigration {
    static func discardOverlapSettings(in defaults: UserDefaults) {
        for key in ["docky.maximizedWindowBehavior", "docky.hidesDuringFullscreen", "docky.hidesSystemDock"] {
            defaults.removeObject(forKey: key)
        }
    }
}
