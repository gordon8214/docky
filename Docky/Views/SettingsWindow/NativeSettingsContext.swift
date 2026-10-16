import AppKit

/// What a settings pane's builders need to know about where the pane is shown.
@MainActor
final class NativeSettingsContext {
    /// The Launchpad inspector shows only the Launchpad settings that change the grid's look.
    enum Placement {
        case settingsWindow
        case launchpadInspector
    }

    let placement: Placement
    let sheets: NativeSheetPresenter
    private(set) var appearHandlers: [@MainActor () -> Void] = []

    init(placement: Placement, owner: NSViewController?) {
        self.placement = placement
        sheets = NativeSheetPresenter(owner: owner)
    }

    var style: NativeSettingsMetrics.Style { placement == .settingsWindow ? .regular : .compact }

    /// Runs `handler` each time the pane appears, such as to refresh a status.
    func onAppear(_ handler: @escaping @MainActor () -> Void) { appearHandlers.append(handler) }
}
