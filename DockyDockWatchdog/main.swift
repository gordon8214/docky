import AppKit
import CoreFoundation
import Darwin
import Foundation

private let dockDomain = "com.apple.dock" as CFString
private let snapshotKey = "docky.systemDockVisibilitySnapshot" as CFString
private let snapshotNullMarker = "__docky_null__"
private let managedKeys = [
    "orientation",
    "autohide",
    "autohide-delay",
    "autohide-time-modifier",
    "no-bouncing",
    "launchanim"
]

private struct WatchdogState {
    let active: Bool
    let ownerPID: pid_t
    let sessionID: String
    let snapshot: [String: Any]
}

let arguments = CommandLine.arguments
#if DEBUG
if arguments.contains("--window-behavior-probe") {
    var signal: URL?
    if let index = arguments.firstIndex(of: "--reservation-signal"), index + 1 < arguments.count {
        signal = URL(fileURLWithPath: arguments[index + 1])
    }
    NativeWindowProbe.run(reservationSignal: signal)
}
#endif
if arguments.contains("--visible-frame-probe") {
    _ = NSApplication.shared
    var frames: [String: String] = [:]
    for screen in NSScreen.screens {
        if let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            frames[display.stringValue] = NSStringFromRect(screen.visibleFrame)
        }
    }
    if let data = try? JSONSerialization.data(withJSONObject: frames) {
        FileHandle.standardOutput.write(data)
        exit(0)
    }
    exit(1)
}
guard arguments.count >= 5 else {
    exit(64)
}

let stateFileURL = URL(fileURLWithPath: arguments[1])
let ownerPID = pid_t(Int32(arguments[2]) ?? 0)
let sessionID = arguments[3]
let dockyBundleIdentifier = arguments[4]

while stateMatches() {
    if isProcessRunning(ownerPID) {
        Thread.sleep(forTimeInterval: 0.5)
    } else {
        break
    }
}

guard stateMatches(), let state = readState() else {
    exit(0)
}

restoreSnapshot(state.snapshot)
clearDockySnapshot()
restartDock()
try? FileManager.default.removeItem(at: stateFileURL)

private func stateMatches() -> Bool {
    guard let state = readState() else {
        return false
    }

    return state.active && state.ownerPID == ownerPID && state.sessionID == sessionID
}

private func readState() -> WatchdogState? {
    guard let data = try? Data(contentsOf: stateFileURL),
          let plist = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
          ) as? [String: Any],
          let snapshot = plist["snapshot"] as? [String: Any] else {
        return nil
    }

    return WatchdogState(
        active: boolValue(plist["active"]) ?? false,
        ownerPID: pid_t(intValue(plist["ownerPID"]) ?? 0),
        sessionID: plist["sessionID"] as? String ?? "",
        snapshot: snapshot
    )
}

@MainActor
private func restoreSnapshot(_ snapshot: [String: Any]) {
    for key in managedKeys {
        restoreKey(key, from: snapshot[key] as? [String: Any])
    }

    CFPreferencesAppSynchronize(dockDomain)
}

@MainActor
private func restoreKey(_ key: String, from entry: [String: Any]?) {
    guard let entry, let type = entry["type"] as? String else {
        CFPreferencesSetAppValue(key as CFString, nil, dockDomain)
        return
    }

    switch type {
    case "bool":
        CFPreferencesSetAppValue(key as CFString, NSNumber(value: boolValue(entry["value"]) ?? false), dockDomain)
    case "number":
        CFPreferencesSetAppValue(key as CFString, NSNumber(value: doubleValue(entry["value"]) ?? 0), dockDomain)
    case "string":
        CFPreferencesSetAppValue(key as CFString, (entry["value"] as? String ?? "") as CFString, dockDomain)
    default:
        CFPreferencesSetAppValue(key as CFString, nil, dockDomain)
    }
}

@MainActor
private func clearDockySnapshot() {
    let domain = dockyBundleIdentifier as CFString
    CFPreferencesSetAppValue(snapshotKey, nil, domain)
    CFPreferencesAppSynchronize(domain)
}

private func restartDock() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    process.arguments = ["Dock"]
    try? process.run()
}

private func isProcessRunning(_ pid: pid_t) -> Bool {
    guard pid > 0 else {
        return false
    }

    return kill(pid, 0) == 0 || errno == EPERM
}

private func boolValue(_ value: Any?) -> Bool? {
    if let value = value as? Bool {
        return value
    }

    if let value = value as? NSNumber {
        return value.boolValue
    }

    if let value = value as? String {
        switch value.lowercased() {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return nil
        }
    }

    return nil
}

private func intValue(_ value: Any?) -> Int? {
    if let value = value as? Int {
        return value
    }

    if let value = value as? NSNumber {
        return value.intValue
    }

    if let value = value as? String {
        return Int(value)
    }

    return nil
}

private func doubleValue(_ value: Any?) -> Double? {
    if let value = value as? Double {
        return value
    }

    if let value = value as? NSNumber {
        return value.doubleValue
    }

    if let value = value as? String {
        return Double(value)
    }

    return nil
}
