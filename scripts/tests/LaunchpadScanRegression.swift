import AppKit
import Combine
import Foundation
import Observation

// Minimal dependencies keep the real service's queues, work items, filesystem
// watchers, and scan code under test without touching persisted app settings.
struct AppTile: Equatable {
    let bundleIdentifier: String
    let displayName: String
}

struct AppFolderTile {
    enum DisplayMode { case grid }
    let identifier: String
    let displayName: String
    let apps: [AppTile]
    let displayMode: DisplayMode
    let contentViewMode: DisplayMode
}

@MainActor
final class DockyPreferences {
    static let shared = DockyPreferences()
    let enablesLaunchpadOverlay = true
}

final class IconCacheService: Sendable {
    static let shared = IconCacheService()

    func icon(forBundleIdentifier _: String) -> NSImage {
        dispatchPrecondition(condition: .notOnQueue(.main))
        return NSImage()
    }
}

@MainActor
@Observable
final class LaunchpadLayoutService {
    static let shared = LaunchpadLayoutService()
    var layout = LaunchpadLayout.empty

    func seedIfEmpty(_ items: [LaunchpadLayoutItem]) {
        if layout.items.isEmpty { layout.items = items }
    }

    func pruneMissingApps(installedBundleIDs: Set<String>) {
        layout.items.removeAll { $0.bundleIDs.allSatisfy { !installedBundleIDs.contains($0) } }
    }

    func appendNewApps(_ bundleIDs: [String]) {
        let existing = Set(layout.items.flatMap(\.bundleIDs))
        layout.items.append(contentsOf: bundleIDs.filter { !existing.contains($0) }.map {
            .app(bundleID: $0)
        })
    }
}

@main
private enum LaunchpadScanRegression {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("docky-scan-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try makeApp(in: root, name: "First", bundleID: "example.first")
        let service = LaunchpadOverlayService(applicationDirectories: [root])
        let subscription = service.$entries.sink { _ in
            MainActor.preconditionIsolated()
        }
        defer { subscription.cancel() }

        // Exercise the real DispatchWorkItem scheduled during initialization.
        await waitUntil {
            service.entries.map(\.matchableBundleIdentifier) == ["example.first"]
        }

        // A filesystem event schedules the delayed/coalesced background path.
        try makeApp(in: root, name: "Second", bundleID: "example.second")
        await waitUntil {
            Set(service.entries.map(\.matchableBundleIdentifier)) == ["example.first", "example.second"]
        }

        try FileManager.default.removeItem(at: root.appendingPathComponent("First.app"))
        await waitUntil {
            service.entries.map(\.matchableBundleIdentifier) == ["example.second"]
        }
        print("Launchpad startup and filesystem rescan regression checks passed")
    }

    private static func makeApp(in root: URL, name: String, bundleID: String) throws {
        let contents = root.appendingPathComponent("\(name).app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": bundleID, "CFBundleName": name],
            format: .xml,
            options: 0
        )
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
    }

    @MainActor
    private static func waitUntil(_ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() {
            precondition(ContinuousClock.now < deadline, "Launchpad scan exceeded its three-second budget")
            await Task.yield()
        }
    }
}
