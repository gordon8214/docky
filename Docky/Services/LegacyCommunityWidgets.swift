import Foundation

/// Saved identifiers are authoritative; bundle metadata cannot identify a plugin's widgets.
@MainActor
enum LegacyCommunityWidgets {
    static var registrations: [WidgetRegistration] {
        let preferences = DockyPreferences.shared
        var registrations: [String: WidgetRegistration] = [:]
        func remember(_ kind: WidgetKind?, owner: String?) {
            guard let kind, case .external(let identifier) = kind else { return }
            let owner = owner ?? identifier
            let registration = WidgetRegistration(
                kind: kind, ownerBundleIdentifier: owner, defaultSpan: .three,
                includesInPalette: false, includesInSmartStack: true)
            registrations[registration.id] = registration
        }
        for item in preferences.pinnedItems { remember(item.widgetKind, owner: item.widgetOwnerBundleIdentifier) }
        for item in preferences.trailingItems { remember(item.widgetKind, owner: item.widgetOwnerBundleIdentifier) }
        for item in preferences.widgetPlacements { remember(item.kind, owner: item.ownerBundleIdentifier) }
        for item in preferences.appWidgetDisplays { remember(item.kind, owner: item.bundleIdentifier) }
        return registrations.values.sorted { $0.id < $1.id }
    }
}
