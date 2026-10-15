//
//  WindowServerWindowRules.swift
//  Docky
//
//  Pure interpretation of SkyLight window data: which windows are user
//  windows, which are minimized, and which notification packets name a
//  window. No SkyLight calls live here, so the standalone browser test can
//  compile it. The values were verified on macOS 27.0.1 (26A434); see
//  docs/window-system-integration.md.
//

import CoreGraphics

/// WindowServer connection notifications that change Docky's window list.
/// Window-specific events arrive only for windows passed to
/// `SLSRequestNotificationsForWindows`. Space membership events arrive for
/// every window, which is how new windows are discovered.
nonisolated enum WindowServerEvent: UInt32, CaseIterable, Sendable {
    /// Payload: the destroyed window's 32-bit ID.
    case windowDestroyed = 804
    /// Payload: the window's 32-bit ID. Fires repeatedly during a drag.
    case windowMoved = 806
    /// Payload: the window's 32-bit ID.
    case windowResized = 807
    /// Payload: the window's 32-bit ID. Fires with `windowHidden` when a
    /// window is minimized or restored.
    case windowShown = 815
    /// Payload: the window's 32-bit ID.
    case windowHidden = 816
    /// Payload: the 64-bit Space ID, then the 32-bit window ID. Fires for new
    /// windows of every app, so no per-window request is needed.
    case windowAddedToSpace = 1325
    /// Payload: the 64-bit Space ID, then the 32-bit window ID.
    case windowRemovedFromSpace = 1326

    /// Reads the window ID from a notification packet, or nil when the packet
    /// is shorter than this event's layout.
    func windowID(in packet: UnsafeRawBufferPointer) -> CGWindowID? {
        // Exhaustive, so a new event must state its own packet layout.
        let offset: Int
        switch self {
        case .windowAddedToSpace, .windowRemovedFromSpace:
            offset = MemoryLayout<UInt64>.size
        case .windowDestroyed, .windowMoved, .windowResized, .windowShown, .windowHidden:
            offset = 0
        }
        guard packet.count >= offset + MemoryLayout<UInt32>.size else { return nil }
        let windowID = packet.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        return windowID == 0 ? nil : windowID
    }
}

/// One window as SkyLight reports it, before Docky decides whether to list it.
nonisolated struct WindowServerWindowInfo: Equatable, Sendable {
    let id: CGWindowID
    let processIdentifier: pid_t
    let bounds: CGRect
    let tags: UInt64
    let attributes: UInt64
    let isOrderedIn: Bool
    let spaceIDs: Set<UInt64>

    var isMinimized: Bool { WindowServerWindowRules.isMinimized(tags: tags) }

    /// Ordered-in windows are on screen on some Space, including inactive
    /// Spaces. Minimized windows are ordered out but still belong to a Space.
    /// Other ordered-out windows on a Space are windows their app closed but
    /// kept, which neither AX nor Mission Control shows.
    var isListed: Bool { isOrderedIn || isMinimized }
}

nonisolated enum WindowServerWindowRules {
    // Bit names follow yabai's tests and are guesses: an ordinary visible
    // window carries both "offscreen" bits and lacks the "visible" bit. Only
    // the combinations in `isUserWindow` were checked against real windows.
    private static let documentTag: UInt64 = 0x1
    private static let panelTag: UInt64 = 0x2
    private static let panelDocumentTag: UInt64 = 0x8000_0000
    private static let visibleTag: UInt64 = 0x0400_0000_0000_0000
    private static let offscreenTags: UInt64 = 0x0300_0000_0000_0000
    private static let minimizedTag: UInt64 = 0x1000_0000_0000_0000
    private static let orderedInAttribute: UInt64 = 0x2

    /// Whether a top-level, normal-level window is a user window rather than a
    /// utility, overlay, or helper surface. Adapted from yabai's
    /// `space_window_list_for_connection`. Native window tabs that aren't
    /// selected are ordered out of every Space, so this never sees them, which
    /// matches Mission Control.
    static func isUserWindow(tags: UInt64, attributes: UInt64) -> Bool {
        let isDocument = tags & documentTag != 0
            || (tags & panelTag != 0 && tags & panelDocumentTag != 0)
        guard isDocument else { return false }
        if attributes & orderedInAttribute != 0 || tags & visibleTag != 0 {
            return true
        }
        return attributes <= 0x1 && (tags & minimizedTag != 0 || tags & offscreenTags != 0)
    }

    static func isMinimized(tags: UInt64) -> Bool {
        tags & minimizedTag != 0
    }

    /// Matched `SLSWindowIsOrderedIn` for every user window tested; used only
    /// when that function is unavailable.
    static func hasOrderedInAttribute(_ attributes: UInt64) -> Bool {
        attributes & orderedInAttribute != 0
    }
}

nonisolated extension CGRect {
    /// Same origin and size within 2 points; AX and WindowServer round
    /// fractional frames differently.
    func isApproximately(_ other: CGRect) -> Bool {
        abs(minX - other.minX) < 2 && abs(minY - other.minY) < 2
            && abs(width - other.width) < 2 && abs(height - other.height) < 2
    }
}
