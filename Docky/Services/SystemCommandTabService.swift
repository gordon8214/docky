//
//  SystemCommandTabService.swift
//  Docky
//
//  Turns the macOS ⌘Tab app switcher off while Docky's window switcher owns
//  ⌘Tab, and back on when it stops. The system setting outlives Docky, so the
//  state is recorded for the watchdog and every normal exit path restores it.
//

import CoreGraphics
import Darwin

@MainActor
final class SystemCommandTabService {
    static let shared = SystemCommandTabService()

    private(set) var isOverridden = false

    /// Debug regressions run beside the user's own Docky. They must never take
    /// ⌘Tab from it, or hand ⌘Tab back to macOS when they exit, so they turn
    /// this off unless a check needs the real override.
    var permitsOverride = true {
        didSet {
            if !permitsOverride { setOverridden(false) }
        }
    }

    // Read from the `atexit` handler, which can't hop to the main actor. Only
    // written on the main actor, and Docky only calls `exit` from the main thread.
    nonisolated(unsafe) private static var restoresAtExit = false

    private init() {}

    /// Disables or re-enables the system ⌘Tab and ⇧⌘Tab hotkeys. Callers pass
    /// `true` only once Docky's own ⌘Tab hotkey is registered, so the user is
    /// never left without a working ⌘Tab.
    func setOverridden(_ requested: Bool) {
        let overridden = requested && permitsOverride
        guard overridden != isOverridden else { return }
        isOverridden = overridden
        Self.restoresAtExit = overridden
        if overridden {
            Self.installExitHandlerIfNeeded()
        }

        for hotKey in SystemSymbolicHotKey.allCases {
            CGSSetSymbolicHotKeyEnabled(hotKey.rawValue, !overridden)
        }
        SystemDockVisibilityService.shared.setCommandTabOverride(active: overridden)
    }

    func restore() {
        setOverridden(false)
    }

    private static var hasInstalledExitHandler = false

    private static func installExitHandlerIfNeeded() {
        guard !hasInstalledExitHandler else { return }
        hasInstalledExitHandler = true
        atexit {
            guard SystemCommandTabService.restoresAtExit else { return }
            for hotKey in SystemSymbolicHotKey.allCases {
                CGSSetSymbolicHotKeyEnabled(hotKey.rawValue, true)
            }
        }
    }
}
