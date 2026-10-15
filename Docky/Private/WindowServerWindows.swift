//
//  WindowServerWindows.swift
//  Docky
//
//  SkyLight and HIServices SPI for listing, observing, and capturing other
//  apps' windows. Every call here works with SIP enabled; none needs the Dock
//  bridge. Verified on macOS 27.0.1 (26A434).
//
//  Why each call is needed, and what breaks without it:
//  - `SLSCopyManagedDisplaySpaces`, `SLSCopyWindowsWithOptionsAndTags` and the
//    `SLSWindowQueryWindows` iterator list windows on every Space, with their
//    owner, level, tags and bounds. Accessibility's window list only covers
//    the active Space, so without them the switcher and hover previews miss
//    windows on other desktops and in fullscreen Spaces. These are required;
//    every other symbol below is optional and disables only its own feature.
//  - `SLSGetWindowBounds` reads one window's bounds when it moves or resizes,
//    without a full window-list query.
//  - `SLSGetWindowOwner` and `SLSConnectionGetPID` name the app behind a
//    Space-membership notification, so menus and tooltips don't each trigger
//    a full window-list refresh.
//  - `SLSWindowIsOrderedIn` separates live windows from windows an app closed
//    but kept. Without it those reappear as phantom switcher entries.
//  - `SLSHWCaptureWindowList` captures one window's backing store, including
//    windows on inactive Spaces, minimized windows and windows of hidden apps.
//    ScreenCaptureKit returns no image for many of those, and must enumerate
//    every shareable window before each capture.
//  - `SLSRegisterConnectionNotifyProc` and `SLSRequestNotificationsForWindows`
//    deliver window creation, destruction, movement and minimization from
//    WindowServer, including for apps whose Accessibility server is hung.
//  - `_AXUIElementCreateWithRemoteToken` rebuilds an Accessibility element for
//    a window on another Space, which `kAXWindowsAttribute` omits. Without it,
//    close, minimize and resize can't reach those windows.
//

import AppKit
import ApplicationServices
import CoreGraphics
import os

private let logger = Logger(subsystem: "gt.quintero.Docky", category: "WindowServer")

/// An Accessibility element handed between the main actor and the background
/// lookup, with the attributes read alongside it. AX elements are immutable
/// IPC handles and are safe on any thread.
nonisolated struct AccessibilityWindowElement: @unchecked Sendable {
    let element: AXUIElement
    /// Read only when the lookup asked for details.
    let title: String?
    let subrole: String?
}

nonisolated struct WindowServerSnapshot: Sendable {
    let windows: [WindowServerWindowInfo]
    /// The visible Space on each display.
    let activeSpaceIDs: Set<UInt64>
}

nonisolated enum WindowServerWindows {
    typealias NotificationCallback = @convention(c) (
        UInt32, UnsafeMutableRawPointer?, UInt32, UnsafeMutableRawPointer?, Int32
    ) -> Void

    /// `SLSRequestNotificationsForWindows` rejects longer lists outright.
    static let maximumNotificationWindows = 1024

    /// Whether windows can be listed. Capture, notifications and lookups each
    /// check their own symbols.
    static var isAvailable: Bool { symbols != nil }

    /// Every normal-level user window on every Space, grouped by Space in
    /// Mission Control order. Ordered-in state, which costs an IPC per window,
    /// is read only for windows owned by `processIdentifiers`; other windows
    /// report `isOrderedIn == false`.
    static func snapshot(checkingOrderFor processIdentifiers: Set<pid_t>) -> WindowServerSnapshot? {
        guard let symbols else { return nil }
        let connection = symbols.mainConnection()
        guard let displays = symbols.copyManagedDisplaySpaces(connection)?.takeRetainedValue()
                as? [[String: Any]] else { return nil }

        var allSpaceIDs: [UInt64] = []
        var activeSpaceIDs = Set<UInt64>()
        for display in displays {
            if let current = (display["Current Space"] as? [String: Any])?["id64"] as? NSNumber {
                activeSpaceIDs.insert(current.uint64Value)
            }
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                if let id = space["id64"] as? NSNumber { allSpaceIDs.append(id.uint64Value) }
            }
        }

        // Query each Space on its own so every window knows its Spaces.
        var spacesByWindow: [CGWindowID: Set<UInt64>] = [:]
        var orderedWindowIDs: [CGWindowID] = []
        for spaceID in allSpaceIDs {
            for windowID in symbols.windowIDs(connection: connection, spaces: [spaceID]) {
                if spacesByWindow[windowID] == nil { orderedWindowIDs.append(windowID) }
                spacesByWindow[windowID, default: []].insert(spaceID)
            }
        }
        guard !orderedWindowIDs.isEmpty else {
            return WindowServerSnapshot(windows: [], activeSpaceIDs: activeSpaceIDs)
        }

        let idArray = orderedWindowIDs.map { NSNumber(value: $0) } as CFArray
        // Keep the ID array alive until iteration ends, as yabai does.
        let windows: [WindowServerWindowInfo]? = withExtendedLifetime(idArray) {
            guard let query = symbols.queryWindows(connection, idArray, orderedWindowIDs.count)?
                    .takeRetainedValue(),
                  let iterator = symbols.queryResultCopyWindows(query)?.takeRetainedValue() else {
                return nil
            }
            var windows: [WindowServerWindowInfo] = []
            while symbols.iteratorAdvance(iterator) {
                guard symbols.iteratorParentID(iterator) == 0,
                      symbols.iteratorLevel(iterator) == Int32(CGWindowLevelForKey(.normalWindow)) else { continue }
                let tags = symbols.iteratorTags(iterator)
                let attributes = symbols.iteratorAttributes(iterator)
                guard WindowServerWindowRules.isUserWindow(tags: tags, attributes: attributes) else { continue }
                let windowID = symbols.iteratorWindowID(iterator)
                let pid = symbols.iteratorPID(iterator)
                windows.append(WindowServerWindowInfo(
                    id: windowID,
                    processIdentifier: pid,
                    bounds: symbols.iteratorBounds(iterator),
                    tags: tags,
                    attributes: attributes,
                    isOrderedIn: processIdentifiers.contains(pid)
                        && symbols.isOrderedIn(connection: connection, windowID: windowID, attributes: attributes),
                    spaceIDs: spacesByWindow[windowID] ?? []
                ))
            }
            return windows
        }
        guard let windows else { return nil }
        return WindowServerSnapshot(windows: windows, activeSpaceIDs: activeSpaceIDs)
    }

    /// Whether `windowID` is a top-level, normal-level window, the only kind
    /// the registry lists. Nil when WindowServer no longer knows the window.
    static func isTopLevelNormalWindow(_ windowID: CGWindowID) -> Bool? {
        guard let symbols else { return nil }
        let connection = symbols.mainConnection()
        let idArray = [NSNumber(value: windowID)] as CFArray
        return withExtendedLifetime(idArray) {
            guard let query = symbols.queryWindows(connection, idArray, 1)?.takeRetainedValue(),
                  let iterator = symbols.queryResultCopyWindows(query)?.takeRetainedValue(),
                  symbols.iteratorAdvance(iterator) else { return nil }
            return symbols.iteratorParentID(iterator) == 0
                && symbols.iteratorLevel(iterator) == Int32(CGWindowLevelForKey(.normalWindow))
        }
    }

    /// Window titles from WindowServer. Titles of other apps' windows need
    /// Screen Recording permission; without it this returns empty strings.
    static func titles(for windowIDs: [CGWindowID]) -> [CGWindowID: String] {
        guard !windowIDs.isEmpty else { return [:] }
        // The array holds raw window IDs, not CF objects.
        let pointers = windowIDs.map { UnsafeRawPointer(bitPattern: UInt($0)) }
        let array = pointers.withUnsafeBufferPointer { buffer in
            CFArrayCreate(nil, UnsafeMutablePointer(mutating: buffer.baseAddress), buffer.count, nil)
        }
        guard let array,
              let descriptions = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]] else {
            return [:]
        }
        var titles: [CGWindowID: String] = [:]
        for description in descriptions {
            guard let id = description[kCGWindowNumber as String] as? CGWindowID else { continue }
            titles[id] = description[kCGWindowName as String] as? String ?? ""
        }
        return titles
    }

    static func bounds(of windowID: CGWindowID) -> CGRect? {
        guard let getWindowBounds = symbols?.getWindowBounds, let symbols else { return nil }
        var bounds = CGRect.zero
        guard getWindowBounds(symbols.mainConnection(), windowID, &bounds) == 0 else { return nil }
        return bounds
    }

    /// The process that owns a window, or nil once the window is gone.
    static func ownerPID(of windowID: CGWindowID) -> pid_t? {
        guard let symbols,
              let getWindowOwner = symbols.getWindowOwner,
              let connectionGetPID = symbols.connectionGetPID else { return nil }
        var owner: Int32 = 0
        var pid: pid_t = 0
        guard getWindowOwner(symbols.mainConnection(), windowID, &owner) == 0,
              connectionGetPID(owner, &pid) == 0, pid > 0 else { return nil }
        return pid
    }

    /// Captures one window without its shadow. Synchronous, typically 30–50 ms;
    /// call it off the main actor. Callers check Screen Recording permission
    /// first. `bestResolution` returns backing pixels; otherwise the image is
    /// in points.
    static func captureImage(of windowID: CGWindowID, bestResolution: Bool) -> CGImage? {
        guard let symbols, let capture = symbols.hwCaptureWindowList else { return nil }
        let ignoreGlobalClipShape: UInt32 = 1 << 11
        let resolution: UInt32 = bestResolution ? 1 << 8 : 1 << 9
        var id = windowID
        guard let images = capture(symbols.mainConnection(), &id, 1, ignoreGlobalClipShape | resolution)?
                .takeRetainedValue() else { return nil }
        return withExtendedLifetime(images) {
            guard CFArrayGetCount(images) > 0, let raw = CFArrayGetValueAtIndex(images, 0) else { return nil }
            let image = Unmanaged<CGImage>.fromOpaque(raw).takeUnretainedValue()
            return image.width > 0 && image.height > 0 ? image : nil
        }
    }

    /// Registers `callback` for each event on Docky's main connection.
    /// WindowServer delivers them on the main thread while AppKit pumps events.
    /// Returns the events that failed to register.
    static func register(
        _ events: [WindowServerEvent],
        callback: NotificationCallback,
        context: UnsafeMutableRawPointer?
    ) -> [WindowServerEvent] {
        guard let symbols, let register = symbols.registerConnectionNotifyProc else { return events }
        let connection = symbols.mainConnection()
        return events.filter { register(connection, callback, $0.rawValue, context) != 0 }
    }

    /// Subscribes to the per-window events for `windowIDs`, replacing the
    /// previous set; an empty list clears it. WindowServer accepts at most
    /// `maximumNotificationWindows`, so order the list by priority.
    static func requestNotifications(for windowIDs: [CGWindowID]) {
        guard let symbols, let request = symbols.requestNotificationsForWindows else { return }
        var ids = Array(windowIDs.prefix(maximumNotificationWindows))
        let result = ids.withUnsafeMutableBufferPointer { buffer in
            request(symbols.mainConnection(), buffer.baseAddress, Int32(buffer.count))
        }
        if result != 0 {
            logger.error("Window notification request for \(ids.count) windows failed: \(result)")
        }
    }

    /// Accessibility elements for `wanted` windows of `pid`, matched by window
    /// ID, or by frame (within 2 points) for elements whose window ID AX won't
    /// report. Reads the app's window list first, then scans remote element
    /// tokens for windows on other Spaces until all are found or `budget` runs
    /// out. With `readsDetails`, also reads each window's title and subrole.
    /// Blocking; call it off the main actor unless one window is needed now.
    static func accessibilityWindows(
        pid: pid_t,
        wanted: [CGWindowID: CGRect],
        budget: Duration,
        readsDetails: Bool
    ) -> [CGWindowID: AccessibilityWindowElement] {
        var found: [CGWindowID: AccessibilityWindowElement] = [:]
        func match(_ element: AXUIElement) {
            var windowID: CGWindowID = 0
            if _AXUIElementGetWindow(element, &windowID) != .success || windowID == 0 {
                guard let frame = frame(of: element),
                      let byFrame = wanted.first(where: {
                          found[$0.key] == nil && $0.value.isApproximately(frame)
                      })?.key else { return }
                windowID = byFrame
            }
            guard wanted[windowID] != nil, found[windowID] == nil else { return }
            var title: String?
            var subrole: String?
            if readsDetails {
                title = stringAttribute(kAXTitleAttribute, of: element)
                subrole = stringAttribute(kAXSubroleAttribute, of: element)
            }
            // Scans shorten the timeout; cached elements use the global one.
            AXUIElementSetMessagingTimeout(element, 0)
            found[windowID] = AccessibilityWindowElement(element: element, title: title, subrole: subrole)
        }

        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.25)
        var listed: CFArray?
        if AXUIElementCopyAttributeValues(application, kAXWindowsAttribute as CFString, 0, 256, &listed) == .success,
           let elements = listed as? [AXUIElement] {
            for element in elements {
                AXUIElementSetMessagingTimeout(element, 0.25)
                match(element)
            }
        }
        guard found.count < wanted.count, let createWithRemoteToken = symbols?.createWithRemoteToken else {
            return found
        }

        // Token layout: pid, 4 zero bytes, the "coco" marker, then the
        // 64-bit element ID. Window elements had IDs below 1,000 in testing.
        var token = Data(count: 20)
        token.withUnsafeMutableBytes { bytes in
            bytes.storeBytes(of: pid, toByteOffset: 0, as: pid_t.self)
            bytes.storeBytes(of: Int32(0x636f_636f), toByteOffset: 8, as: Int32.self)
        }
        let deadline = ContinuousClock.now + budget
        for elementID: UInt64 in 0..<1000 {
            guard found.count < wanted.count, ContinuousClock.now < deadline else { break }
            token.withUnsafeMutableBytes { $0.storeBytes(of: elementID, toByteOffset: 12, as: UInt64.self) }
            guard let element = createWithRemoteToken(token as CFData)?.takeRetainedValue() else { continue }
            AXUIElementSetMessagingTimeout(element, 0.1)
            guard stringAttribute(kAXRoleAttribute, of: element) == kAXWindowRole as String else { continue }
            match(element)
        }
        return found
    }

    private static func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else {
            return nil
        }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    private static let symbols = Symbols.load()
}

private nonisolated struct Symbols: @unchecked Sendable {
    typealias MainConnection = @convention(c) () -> Int32
    typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    typealias CopyWindowsWithOptionsAndTags = @convention(c) (
        Int32, UInt32, CFArray, UInt32, UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>
    ) -> Unmanaged<CFArray>?
    /// The count is read as a 64-bit value.
    typealias QueryWindows = @convention(c) (Int32, CFArray, Int) -> Unmanaged<CFTypeRef>?
    typealias QueryResultCopyWindows = @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?
    typealias IteratorAdvance = @convention(c) (CFTypeRef) -> Bool
    typealias IteratorUInt32 = @convention(c) (CFTypeRef) -> UInt32
    typealias IteratorUInt64 = @convention(c) (CFTypeRef) -> UInt64
    typealias IteratorInt32 = @convention(c) (CFTypeRef) -> Int32
    typealias IteratorPID = @convention(c) (CFTypeRef) -> pid_t
    typealias IteratorBounds = @convention(c) (CFTypeRef) -> CGRect
    /// Writes one byte and always returns 0, so the byte is read as `UInt8`.
    typealias WindowIsOrderedIn = @convention(c) (Int32, UInt32, UnsafeMutablePointer<UInt8>) -> Int32
    typealias GetWindowBounds = @convention(c) (Int32, UInt32, UnsafeMutablePointer<CGRect>) -> Int32
    typealias GetWindowOwner = @convention(c) (Int32, UInt32, UnsafeMutablePointer<Int32>) -> Int32
    typealias ConnectionGetPID = @convention(c) (Int32, UnsafeMutablePointer<pid_t>) -> Int32
    typealias HWCaptureWindowList = @convention(c) (Int32, UnsafeMutablePointer<UInt32>, Int32, UInt32)
        -> Unmanaged<CFArray>?
    typealias RegisterConnectionNotifyProc = @convention(c) (
        Int32, WindowServerWindows.NotificationCallback, UInt32, UnsafeMutableRawPointer?
    ) -> Int32
    typealias RequestNotificationsForWindows = @convention(c) (Int32, UnsafeMutablePointer<UInt32>?, Int32)
        -> Int32
    typealias CreateWithRemoteToken = @convention(c) (CFData) -> Unmanaged<AXUIElement>?

    // Listing; required.
    let mainConnection: MainConnection
    let copyManagedDisplaySpaces: CopyManagedDisplaySpaces
    let copyWindowsWithOptionsAndTags: CopyWindowsWithOptionsAndTags
    let queryWindows: QueryWindows
    let queryResultCopyWindows: QueryResultCopyWindows
    let iteratorAdvance: IteratorAdvance
    let iteratorWindowID: IteratorUInt32
    let iteratorParentID: IteratorUInt32
    let iteratorPID: IteratorPID
    let iteratorLevel: IteratorInt32
    let iteratorTags: IteratorUInt64
    let iteratorAttributes: IteratorUInt64
    let iteratorBounds: IteratorBounds

    // Optional; each disables only its own feature.
    let windowIsOrderedIn: WindowIsOrderedIn?
    let getWindowBounds: GetWindowBounds?
    let getWindowOwner: GetWindowOwner?
    let connectionGetPID: ConnectionGetPID?
    let hwCaptureWindowList: HWCaptureWindowList?
    let registerConnectionNotifyProc: RegisterConnectionNotifyProc?
    let requestNotificationsForWindows: RequestNotificationsForWindows?
    /// HIServices; only needed for windows on other Spaces.
    let createWithRemoteToken: CreateWithRemoteToken?

    /// Window IDs on `spaces`, including minimized windows (options `0x7`).
    func windowIDs(connection: Int32, spaces: [UInt64]) -> [CGWindowID] {
        var setTags: UInt64 = 1
        var clearTags: UInt64 = 0
        let spaceArray = spaces.map { NSNumber(value: $0) } as CFArray
        guard let ids = copyWindowsWithOptionsAndTags(connection, 0, spaceArray, 0x7, &setTags, &clearTags)?
                .takeRetainedValue() as? [NSNumber] else { return [] }
        return ids.map(\.uint32Value)
    }

    /// Falls back to the ordered-in attribute bit, which matched
    /// `SLSWindowIsOrderedIn` for every user window tested.
    func isOrderedIn(connection: Int32, windowID: CGWindowID, attributes: UInt64) -> Bool {
        guard let windowIsOrderedIn else {
            return WindowServerWindowRules.hasOrderedInAttribute(attributes)
        }
        var orderedIn: UInt8 = 0
        _ = windowIsOrderedIn(connection, windowID, &orderedIn)
        return orderedIn == 1
    }

    static func load() -> Symbols? {
        guard let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else {
            logger.error("SkyLight could not be loaded; Docky can't list windows")
            return nil
        }
        var missing: [String] = []
        func resolve<T>(_ name: String, as type: T.Type, in image: UnsafeMutableRawPointer?) -> T? {
            guard let image, let address = dlsym(image, name) else {
                missing.append(name)
                return nil
            }
            return unsafeBitCast(address, to: type)
        }
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            resolve(name, as: type, in: skyLight)
        }
        let hiServices = dlopen(
            "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
            RTLD_LAZY
        )
        let windowIsOrderedIn = symbol("SLSWindowIsOrderedIn", as: WindowIsOrderedIn.self)
        let getWindowBounds = symbol("SLSGetWindowBounds", as: GetWindowBounds.self)
        let getWindowOwner = symbol("SLSGetWindowOwner", as: GetWindowOwner.self)
        let connectionGetPID = symbol("SLSConnectionGetPID", as: ConnectionGetPID.self)
        let capture = symbol("SLSHWCaptureWindowList", as: HWCaptureWindowList.self)
        let register = symbol("SLSRegisterConnectionNotifyProc", as: RegisterConnectionNotifyProc.self)
        let request = symbol("SLSRequestNotificationsForWindows", as: RequestNotificationsForWindows.self)
        let remoteToken = resolve("_AXUIElementCreateWithRemoteToken", as: CreateWithRemoteToken.self, in: hiServices)
        let optionalMissing = missing

        guard let mainConnection = symbol("SLSMainConnectionID", as: MainConnection.self),
              let copyManagedDisplaySpaces = symbol("SLSCopyManagedDisplaySpaces", as: CopyManagedDisplaySpaces.self),
              let copyWindows = symbol("SLSCopyWindowsWithOptionsAndTags", as: CopyWindowsWithOptionsAndTags.self),
              let queryWindows = symbol("SLSWindowQueryWindows", as: QueryWindows.self),
              let queryResult = symbol("SLSWindowQueryResultCopyWindows", as: QueryResultCopyWindows.self),
              let advance = symbol("SLSWindowIteratorAdvance", as: IteratorAdvance.self),
              let windowID = symbol("SLSWindowIteratorGetWindowID", as: IteratorUInt32.self),
              let parentID = symbol("SLSWindowIteratorGetParentID", as: IteratorUInt32.self),
              let pid = symbol("SLSWindowIteratorGetPID", as: IteratorPID.self),
              let level = symbol("SLSWindowIteratorGetLevel", as: IteratorInt32.self),
              let tags = symbol("SLSWindowIteratorGetTags", as: IteratorUInt64.self),
              let attributes = symbol("SLSWindowIteratorGetAttributes", as: IteratorUInt64.self),
              let bounds = symbol("SLSWindowIteratorGetBounds", as: IteratorBounds.self) else {
            logger.error("Missing SkyLight symbols \(missing.joined(separator: ", "), privacy: .public); Docky can't list windows")
            return nil
        }
        if !optionalMissing.isEmpty {
            logger.error("Missing optional window symbols: \(optionalMissing.joined(separator: ", "), privacy: .public)")
        }
        return Symbols(
            mainConnection: mainConnection,
            copyManagedDisplaySpaces: copyManagedDisplaySpaces,
            copyWindowsWithOptionsAndTags: copyWindows,
            queryWindows: queryWindows,
            queryResultCopyWindows: queryResult,
            iteratorAdvance: advance,
            iteratorWindowID: windowID,
            iteratorParentID: parentID,
            iteratorPID: pid,
            iteratorLevel: level,
            iteratorTags: tags,
            iteratorAttributes: attributes,
            iteratorBounds: bounds,
            windowIsOrderedIn: windowIsOrderedIn,
            getWindowBounds: getWindowBounds,
            getWindowOwner: getWindowOwner,
            connectionGetPID: connectionGetPID,
            hwCaptureWindowList: capture,
            registerConnectionNotifyProc: register,
            requestNotificationsForWindows: request,
            createWithRemoteToken: remoteToken
        )
    }
}
