//
//  CGSPrivate.swift
//  Docky
//
//  SkyLight (CoreGraphics Services) SPI. Not for App Store submission without review.
//

import AppKit
import ApplicationServices
import CoreGraphics

typealias CGSConnectionID = Int

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

// Returns the SkyLight space ID for the currently-active Mission Control
// space on the focused display. Stable across logins (the same UUID-backed
// id used by `com.apple.spaces`). Combined with
// `NSWorkspace.activeSpaceDidChangeNotification` to drive profile-trigger
// matching on space switches.
@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ connection: CGSConnectionID) -> UInt64

// Returns the ordered list of spaces per managed display. Each element is
// a dictionary with `Display Identifier` and `Spaces` keys; `Spaces` is
// an ordered array of `{id64, uuid, type, …}` dicts. We use it to resolve
// the active space's 1-based positional index.
@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ connection: CGSConnectionID) -> Unmanaged<CFArray>?

// Returns the system CGWindowID backing an AX window element. Preferred over
// the AXWindowNumber attribute, which some apps populate with their own
// internal IDs rather than the system window number.
@_silgen_name("_AXUIElementGetWindow") @discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: inout CGWindowID) -> AXError

// WindowServer symbolic hotkeys that the Dock consumes for its app switcher:
// ⌘Tab (1) and ⇧⌘Tab (2). WindowServer matches them in its symbolic-hotkey
// layer ahead of every Carbon hotkey, so a `RegisterEventHotKey` for ⌘Tab
// never fires while they are enabled. Docky turns them off while its window
// switcher replaces ⌘Tab and back on when it stops. The setting is global to
// the login session and outlives the process that changed it, which is why
// the watchdog re-enables them after a crash. ⌘` (27) is not consumed by any
// system process, so it is left alone.
enum SystemSymbolicHotKey: Int32, CaseIterable {
    case commandTab = 1
    case commandShiftTab = 2
}

@_silgen_name("CGSSetSymbolicHotKeyEnabled") @discardableResult
func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ isEnabled: Bool) -> CGError

@_silgen_name("CGSIsSymbolicHotKeyEnabled")
func CGSIsSymbolicHotKeyEnabled(_ hotKey: Int32) -> Bool

@_silgen_name("CGSSetWindowBackgroundBlurRadius")
func CGSSetWindowBackgroundBlurRadius(
    _ connection: CGSConnectionID,
    _ windowID: Int,
    _ radius: Int
) -> Int32

// Window previews use asynchronous ScreenCaptureKit captures with explicit
// output dimensions. The legacy CGWindowListCreateImage entry point blocks the
// caller while macOS proxies it through ScreenCaptureKit, stalling the main run
// loop and repeatedly enumerating the entire desktop for each window.

@_silgen_name("CGSGetWindowAlpha")
func CGSGetWindowAlpha(
    _ connection: CGSConnectionID,
    _ windowID: Int,
    _ alpha: UnsafeMutablePointer<Float>
) -> Int32

@_silgen_name("CGSSetWindowAlpha")
func CGSSetWindowAlpha(
    _ connection: CGSConnectionID,
    _ windowID: Int,
    _ alpha: Float
) -> Int32

@_silgen_name("CGSSetConnectionProperty") @discardableResult
func CGSSetConnectionProperty(
    _ connection: CGSConnectionID,
    _ targetConnection: CGSConnectionID,
    _ key: CFString,
    _ value: CFTypeRef
) -> Int32

// Docky is an accessory app that is almost never active, and WindowServer
// ignores cursor changes from background connections. Without this, dragging
// the Windows taskbar's top edge still resizes it, but the resize cursor never
// appears. Callers enable it only while the pointer is over that edge.
@MainActor
func setsCursorInBackground(_ enabled: Bool) {
    let connection = CGSMainConnectionID()
    let value: CFBoolean = enabled ? kCFBooleanTrue : kCFBooleanFalse
    CGSSetConnectionProperty(connection, connection, "SetsCursorInBackground" as CFString, value)
}

// MARK: - SkyLight Process Switching (SLPS)

struct ProcessSerialNumber {
    var highLongOfPSN: UInt32 = 0
    var lowLongOfPSN: UInt32 = 0
}

@_silgen_name("GetProcessForPID")
func GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

enum SLPSMode: UInt32 {
    case allWindows = 0x100
    case userGenerated = 0x200
    case noWindows = 0x400
}

private typealias SLPSSetFrontProcessWithOptionsType = @convention(c) (
    UnsafeMutableRawPointer,
    CGWindowID,
    UInt32
) -> CGError

private typealias SLPSPostEventRecordToType = @convention(c) (
    UnsafeMutableRawPointer,
    UnsafeMutablePointer<UInt8>
) -> CGError

private typealias SLSWindowIsOrderedInType = @convention(c) (
    CGSConnectionID,
    CGWindowID,
    UnsafeMutablePointer<Bool>
) -> CGError

@MainActor private var skyLightHandle: UnsafeMutableRawPointer?
@MainActor private var setFrontProcessPtr: SLPSSetFrontProcessWithOptionsType?
@MainActor private var postEventRecordPtr: SLPSPostEventRecordToType?
@MainActor private var windowIsOrderedInPtr: SLSWindowIsOrderedInType?

// Focus paths and lazy symbol loading are isolated to the main actor.
@MainActor
private func loadSkyLightFunctions() {
    guard skyLightHandle == nil else { return }

    let skyLightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    guard let handle = dlopen(skyLightPath, RTLD_LAZY) else { return }
    skyLightHandle = handle

    if let symbol = dlsym(handle, "_SLPSSetFrontProcessWithOptions") {
        setFrontProcessPtr = unsafeBitCast(symbol, to: SLPSSetFrontProcessWithOptionsType.self)
    }
    if let symbol = dlsym(handle, "SLPSPostEventRecordTo") {
        postEventRecordPtr = unsafeBitCast(symbol, to: SLPSPostEventRecordToType.self)
    }
    if let symbol = dlsym(handle, "SLSWindowIsOrderedIn") {
        windowIsOrderedInPtr = unsafeBitCast(symbol, to: SLSWindowIsOrderedInType.self)
    }
}

// Whether the window server has the window mapped on some Space — the only
// signal that separates a live off-Space window from the stale entries
// CGWindowListCopyWindowInfo keeps serving after a window closes.
@MainActor
func SLSWindowIsOrderedIn(_ connection: CGSConnectionID, _ windowID: CGWindowID) -> Bool {
    loadSkyLightFunctions()
    guard let fn = windowIsOrderedInPtr else { return false }
    var orderedIn = false
    guard fn(connection, windowID, &orderedIn) == .success else { return false }
    return orderedIn
}

@discardableResult
@MainActor
func _SLPSSetFrontProcessWithOptions(
    _ psn: UnsafeMutablePointer<ProcessSerialNumber>,
    _ wid: CGWindowID,
    _ mode: SLPSMode.RawValue
) -> CGError {
    loadSkyLightFunctions()
    guard let fn = setFrontProcessPtr else { return CGError(rawValue: -1)! }
    return fn(psn, wid, mode)
}

@discardableResult
@MainActor
func SLPSPostEventRecordTo(
    _ psn: UnsafeMutablePointer<ProcessSerialNumber>,
    _ bytes: UnsafeMutablePointer<UInt8>
) -> CGError {
    loadSkyLightFunctions()
    guard let fn = postEventRecordPtr else { return CGError(rawValue: -1)! }
    return fn(psn, bytes)
}

// MARK: - Dock Notifications (HIServices)
//
// `CoreDockSendNotification` is the private function the system Dock invokes
// when its own menus pick "Show All Windows" / "Mission Control" / etc.
// Posting via `DistributedNotificationCenter` with the same name string does
// not route through the Dock and is a no-op. Loaded by dlsym because the
// symbol is not exported in the SDK.

private typealias CoreDockSendNotificationType = @convention(c) (CFString, Int32) -> Void
@MainActor private var hiServicesHandle: UnsafeMutableRawPointer?
@MainActor private var coreDockSendNotificationPtr: CoreDockSendNotificationType?

@MainActor
private func loadHIServicesFunctions() {
    guard hiServicesHandle == nil else { return }

    let hiServicesPath = "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/HIServices"
    guard let handle = dlopen(hiServicesPath, RTLD_LAZY) else { return }
    hiServicesHandle = handle

    if let symbol = dlsym(handle, "CoreDockSendNotification") {
        coreDockSendNotificationPtr = unsafeBitCast(symbol, to: CoreDockSendNotificationType.self)
    }
}

@MainActor
func CoreDockSendNotification(_ message: String) {
    loadHIServicesFunctions()
    guard let fn = coreDockSendNotificationPtr else { return }
    fn(message as CFString, 0)
}

@MainActor
func slpsMakeKeyWindow(psn: inout ProcessSerialNumber, windowID: CGWindowID) {
    var bytes = [UInt8](repeating: 0, count: 0xF8)
    bytes[0x04] = 0xF8
    bytes[0x3A] = 0x10
    var wid = UInt32(windowID)
    memcpy(&bytes[0x3C], &wid, MemoryLayout<UInt32>.size)
    memset(&bytes[0x20], 0xFF, 0x10)
    bytes[0x08] = 0x01
    _ = SLPSPostEventRecordTo(&psn, &bytes)
    bytes[0x08] = 0x02
    _ = SLPSPostEventRecordTo(&psn, &bytes)
}
