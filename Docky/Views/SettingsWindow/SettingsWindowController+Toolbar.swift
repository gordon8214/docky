import AppKit

extension NSToolbarItem.Identifier {
    static let settingsBack = Self("DockySettingsBack")
    static let settingsForward = Self("DockySettingsForward")
}

/// Back and Forward lead the pane's side of the toolbar, before the title, and
/// match View ▸ Back (⌘[) and View ▸ Forward (⌘]).
extension SettingsWindowController: NSToolbarDelegate, NSToolbarItemValidation, NSMenuItemValidation {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // The tracking separator lines the items and title up with the pane, past the sidebar.
        [.sidebarTrackingSeparator, .settingsBack, .settingsForward]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .settingsBack:
            navigationItem(itemIdentifier, label: String(localized: "Back"), symbol: "chevron.backward", action: #selector(goBack(_:)))
        case .settingsForward:
            navigationItem(
                itemIdentifier, label: String(localized: "Forward"), symbol: "chevron.forward",
                action: #selector(goForward(_:)))
        default:
            nil
        }
    }

    @objc func goBack(_ sender: Any?) { settings.goBack() }
    @objc func goForward(_ sender: Any?) { settings.goForward() }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool { canPerform(item.action) }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { canPerform(menuItem.action) }

    private func canPerform(_ action: Selector?) -> Bool {
        guard window?.attachedSheet == nil else { return false }
        switch action {
        case #selector(goBack(_:)): return settings.canGoBack
        case #selector(goForward(_:)): return settings.canGoForward
        default: return true
        }
    }

    private func navigationItem(
        _ identifier: NSToolbarItem.Identifier, label: String, symbol: String, action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.isBordered = true
        item.isNavigational = true
        item.target = self
        item.action = action
        return item
    }
}
