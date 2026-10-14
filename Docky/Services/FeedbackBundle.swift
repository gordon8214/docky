import AppKit
import Foundation

extension Bundle {
    fileprivate var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }
}

/// Standalone helper so the build step is testable on its own and
/// nothing in the view code needs to know about plist serialization,
/// zipping, etc.
@MainActor
enum FeedbackBundle {
    static func build(feedbackText: String, attachmentURL: URL?) throws -> URL {
        let fileManager = FileManager.default
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let stagingRoot = fileManager.temporaryDirectory
            .appending(path: "docky-feedback-\(timestamp)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

        // 1. docky-defaults.plist, filtered to our namespace so we
        //    don't leak unrelated UserDefaults from other domains.
        let allDefaults = UserDefaults.standard.dictionaryRepresentation()
        let dockyDefaults = allDefaults.filter { $0.key.hasPrefix("docky.") }
        try writePlist(dockyDefaults, to: stagingRoot.appending(path: "docky-defaults.plist"))

        // 2. com.apple.dock plist, exact snapshot of system dock prefs.
        if let dockPlist = DockPlistReader.read() {
            try writePlist(dockPlist, to: stagingRoot.appending(path: "com.apple.dock.plist"))
        }

        // 3. system.json, Mac specs (kept minimal: no usernames or
        //    paths). Enough to tell apart "M1 Air on macOS 14" vs
        //    "Mac Pro on macOS 26".
        let system = systemSnapshot()
        try writeJSON(system, to: stagingRoot.appending(path: "system.json"))

        // 4. feedback.txt, verbatim user message.
        try feedbackText
            .write(to: stagingRoot.appending(path: "feedback.txt"), atomically: true, encoding: .utf8)

        // 5. Optional asset, copied alongside (preserves original name).
        if let attachmentURL {
            let dest = stagingRoot.appending(path: attachmentURL.lastPathComponent)
            try fileManager.copyItem(at: attachmentURL, to: dest)
        }

        // Zip the staging directory in place so the share sheet has
        // one cohesive attachment rather than a directory tree.
        let zipURL = stagingRoot.deletingLastPathComponent()
            .appending(path: stagingRoot.lastPathComponent + ".zip")
        try fileManager.removeItemIfExists(at: zipURL)
        try ditto(source: stagingRoot, destination: zipURL)
        return zipURL
    }

    private static func writePlist(_ value: Any, to url: URL) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: value,
            format: .xml,
            options: 0
        )
        try data.write(to: url)
    }

    private static func writeJSON(_ value: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private static func systemSnapshot() -> [String: Any] {
        let processInfo = ProcessInfo.processInfo
        let osVersion = processInfo.operatingSystemVersion
        var screens: [[String: Any]] = []
        for screen in NSScreen.screens {
            screens.append([
                "frame": NSStringFromRect(screen.frame),
                "visibleFrame": NSStringFromRect(screen.visibleFrame),
                "backingScaleFactor": screen.backingScaleFactor,
                "localizedName": screen.localizedName
            ])
        }
        return [
            "dockyVersion": Bundle.main.shortVersion,
            "dockyBuild": (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?",
            "macosVersion": "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)",
            "macosVersionString": processInfo.operatingSystemVersionString,
            "processorCount": processInfo.processorCount,
            "physicalMemoryBytes": processInfo.physicalMemory,
            "locale": Locale.current.identifier,
            "screens": screens
        ]
    }

    /// Use `/usr/bin/ditto` for archiving, it produces a real macOS
    /// zip (preserves resource forks / extended attrs, deterministic,
    /// no third-party deps).
    private static func ditto(source: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "FeedbackBundle", code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: "ditto exited with status \(process.terminationStatus)"
                ])
        }
    }
}

extension FileManager {
    fileprivate func removeItemIfExists(at url: URL) throws {
        if fileExists(atPath: url.path) {
            try removeItem(at: url)
        }
    }
}
