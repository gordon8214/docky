import Foundation

@main
struct AppKitCompatibilityRegression {
    @MainActor
    static func main() throws {
        var history = SettingsNavigationHistory()
        precondition(!history.canMoveBack && !history.canMoveForward, "An empty history can't move")
        history.push("profiles")
        precondition(!history.canMoveBack && !history.canMoveForward, "The first pane has nowhere to go")
        history.push("appearance")
        history.push("launchpad")
        precondition(history.canMoveBack && !history.canMoveForward)
        precondition(history.move(-1) == "appearance")
        precondition(history.canMoveBack && history.canMoveForward)
        history.push("appearance")
        precondition(history.entries == ["profiles", "appearance", "launchpad"], "Sidebar selection must not destroy forward history")
        precondition(history.move(1) == "launchpad")
        precondition(history.move(-2) == "profiles")
        precondition(!history.canMoveBack && history.canMoveForward)
        history.push("permissions")
        precondition(history.entries == ["profiles", "permissions"])
        precondition(history.move(1) == nil)
        precondition(history.move(-2) == nil)

        let legacy = Data(#""external:com.example.LegacyWidget""#.utf8)
        let kind = try JSONDecoder().decode(WidgetKind.self, from: legacy)
        precondition(kind == .external("com.example.LegacyWidget"))
        let encodedKind = try JSONEncoder().encode(kind)
        precondition(encodedKind == legacy)
        precondition(!kind.isExpandable, "Removed community widgets must not expand or execute")
        precondition(kind.supportedSpans == TileSpan.allCases, "Persisted spans must remain intact")
        let settings: WidgetSettings = [
            "title": .string("Saved title"), "count": .number(3.5), "enabled": .bool(true),
            "calendars": .stringList(["one", "two"])
        ]
        let restored = try JSONDecoder().decode(WidgetSettings.self, from: JSONEncoder().encode(settings))
        precondition(restored == settings, "Opaque legacy settings must survive encoding")
        print("AppKit compatibility regressions passed")
    }
}
