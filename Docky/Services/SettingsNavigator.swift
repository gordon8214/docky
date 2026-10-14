import AppKit
import Observation

@MainActor
@Observable
final class SettingsNavigator {
    static let shared = SettingsNavigator()
    private init() {}

    /// String form of `SettingsPane.rawValue`. Untyped here so callers
    /// don't need to import the private enum.
    var pendingPaneID: String?

    func requestPane(id: String) {
        pendingPaneID = id
        (NSApp.delegate as? AppDelegate)?.showSettingsWindow(nil)
    }
}
