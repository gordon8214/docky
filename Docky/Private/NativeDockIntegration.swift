import AppKit
import Darwin

/// The Dock uses a CGRect by value, followed by 32-bit reason and orientation.
/// Verified against the macOS 27 Dock and SkyLight binaries. Reason 0 reserves
/// space; reason 2 describes an autohiding Dock. Notification 1201 carries four
/// Float coordinates followed by reason/orientation (24 bytes), not a CGRect.
@MainActor
enum NativeDockIntegration {
    struct Reservation: Equatable {
        var rect: CGRect
        var reason: Int32
        var orientation: Int32
        init(rect: CGRect, reason: Int32, orientation: Int32) {
            // SkyLight transports these values as floats. Normalize once so
            // fractional-point geometry does not cause endless republishing.
            self.rect = CGRect(x: CGFloat(Float(rect.minX)), y: CGFloat(Float(rect.minY)),
                               width: CGFloat(Float(rect.width)), height: CGFloat(Float(rect.height)))
            self.reason = reason
            self.orientation = orientation
        }
    }
    private struct GeometryNotification {
        var originX: Float
        var originY: Float
        var width: Float
        var height: Float
        var reason: Int32
        var orientation: Int32
    }
    private typealias Connection = @convention(c) () -> Int32
    private typealias GetRect = @convention(c) (
        Int32, UnsafeMutablePointer<CGRect>, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>
    ) -> Int32
    private typealias SetRect = @convention(c) (Int32, CGRect, Int32, Int32) -> Int32
    private typealias Broadcast = @convention(c) (UInt32, UnsafeMutableRawPointer, UInt32) -> Int32
    private typealias MenuHeight = @convention(c) (UInt32, UnsafeMutablePointer<UInt32>) -> Int32
    private typealias ManagedSpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let connection: Connection? = symbol("SLSMainConnectionID", as: Connection.self)
    private static let getRect: GetRect? = symbol("SLSGetDockRectWithOrientation", as: GetRect.self)
    private static let setRect: SetRect? = symbol("SLSSetDockRectWithOrientation", as: SetRect.self)
    private static let broadcast: Broadcast? = symbol("SLSPostBroadcastNotification", as: Broadcast.self)
    private static let menuHeight: MenuHeight? = symbol("SLSGetDisplayMenubarHeight", as: MenuHeight.self)
    private static let managedSpaces: ManagedSpaces? = symbol("SLSCopyManagedDisplaySpaces", as: ManagedSpaces.self)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let address = dlsym(handle, name) else { return nil }
        return unsafeBitCast(address, to: type)
    }
    static func readReservation() -> Reservation? {
        guard let connection, let getRect else { return nil }
        var rect = CGRect.zero
        var reason: Int32 = 0
        var orientation: Int32 = 0
        guard getRect(connection(), &rect, &reason, &orientation) == 0 else { return nil }
        return Reservation(rect: rect, reason: reason, orientation: orientation)
    }
    static func publish(_ reservation: Reservation) -> Int32 {
        guard let connection, let setRect, let broadcast else { return -1 }
        let result = setRect(connection(), reservation.rect, reservation.reason, reservation.orientation)
        guard result == 0 else { return result }
        var notification = GeometryNotification(
            originX: Float(reservation.rect.minX), originY: Float(reservation.rect.minY),
            width: Float(reservation.rect.width), height: Float(reservation.rect.height),
            reason: reservation.reason, orientation: reservation.orientation)
        return withUnsafeMutablePointer(to: &notification) {
            broadcast(1201, UnsafeMutableRawPointer($0), UInt32(MemoryLayout<GeometryNotification>.size))
        }
    }
    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
    static func isFullscreen(_ screen: NSScreen) -> Bool? {
        guard let connection, let managedSpaces,
              let displays = managedSpaces(connection())?.takeRetainedValue() as? [[String: Any]],
              let displayID = displayID(screen),
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
        else { return nil }
        let identifier = CFUUIDCreateString(nil, uuid) as String
        return DockSystemGeometry.fullscreen(displayID: identifier, separateSpaces: NSScreen.screensHaveSeparateSpaces,
                                             displays: displays)
    }
    /// Reading visibleFrame here would feed Docky's own reservation back into
    /// its layout. Menu-bar height comes from the display, independent of Dock.
    static func unreservedFrame(_ screen: NSScreen, fullscreen: Bool = false) -> CGRect {
        var height: UInt32 = 0
        if let display = displayID(screen), let menuHeight { _ = menuHeight(display, &height) }
        let inset = fullscreen ? 0 : max(CGFloat(height), screen.safeAreaInsets.top)
        return CGRect(x: screen.frame.minX, y: screen.frame.minY,
                      width: screen.frame.width, height: max(0, screen.frame.height - inset))
    }
}
