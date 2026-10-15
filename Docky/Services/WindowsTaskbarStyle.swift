import AppKit
import QuartzCore

/// Windows geometry uses logical pixels, independent of the display's backing scale.
@MainActor
enum WindowsTaskbarStyle {
    /// The user's taskbar size, set by dragging the bar's top edge or from Settings.
    static var metrics: WindowsTaskbarMetrics {
        WindowsTaskbarMetrics(height: DockyPreferences.shared.windowsTaskbarHeight)
    }
    // Source: Windows Taskbar Behavior.mov, insertions at 11.758–12.033 and 16.817–17.075.
    static let layoutDuration: TimeInterval = 0.291667
    static let removalDuration: TimeInterval = 0.233333
    static let pressDuration: TimeInterval = 0.10
    static let popupDuration: TimeInterval = 0.16
    static var timingFunction: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1) }
    static var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Tiles off the taskbar (the tray's overflow popup of folders, stacks
    /// and widgets, and drag previews) keep the generic tile layout with
    /// these values.
    enum Tray {
        static let verticalPadding: CGFloat = 4
        static let iconPadding: CGFloat = 6
        static let indicatorScale: CGFloat = 0.7
        static let indicatorOffset: CGFloat = -2
        static var indicatorColor: NSColor { .controlAccentColor }
        /// Widgets wider than one tile fill their tile edge to edge.
        static func fillsTile(_ span: TileSpan) -> Bool { span != .one }
    }
    static func font(size: CGFloat = 12) -> NSFont {
        NSFont(name: "SegoeUI", size: size) ?? NSFont(name: "Segoe UI", size: size)
            ?? .systemFont(ofSize: size)
    }
    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
    static func background(_ appearance: NSAppearance) -> NSColor {
        isDark(appearance)
            ? NSColor(calibratedWhite: 0.10, alpha: 0.84)
            : NSColor(calibratedWhite: 0.96, alpha: 0.86)
    }
    static func foreground(_ appearance: NSAppearance) -> NSColor {
        isDark(appearance) ? .white : NSColor(calibratedWhite: 0.12, alpha: 1)
    }
    static func highlight(_ appearance: NSAppearance, pressed: Bool = false) -> NSColor {
        let dark = isDark(appearance)
        return (dark ? NSColor.white : .black).withAlphaComponent(
            pressed ? (dark ? 0.04 : 0.025) : (dark ? 0.075 : 0.045))
    }
    static func accent(_ appearance: NSAppearance) -> NSColor {
        isDark(appearance)
            ? NSColor(calibratedRed: 0.30, green: 0.76, blue: 0.96, alpha: 1)
            : NSColor(calibratedRed: 0, green: 0.40, blue: 0.75, alpha: 1)
    }
    static func startImage() -> NSImage {
        let image = NSImage(size: CGSize(width: 24, height: 24), flipped: false) { _ in
            let gradient = NSGradient(
                starting: NSColor(calibratedRed: 0.05, green: 0.58, blue: 0.93, alpha: 1),
                ending: NSColor(calibratedRed: 0.43, green: 0.85, blue: 1, alpha: 1))
            for row in 0..<2 {
                for column in 0..<2 {
                    let cell = CGRect(
                        x: CGFloat(column) * 12.5, y: CGFloat(row) * 12.5, width: 11.5, height: 11.5)
                    gradient?.draw(in: NSBezierPath(rect: cell), angle: 90)
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
    /// Sampled Start-button movement, normalized from 44 physical pixels at 2x.
    static func positionAnimation(offset: CGPoint, removing: Bool) -> CAKeyframeAnimation {
        let samples: [(Double, Double)] = removing
            ? [(0, 0), (0.017, 2), (0.05, 4), (0.067, 8), (0.083, 16), (0.1, 26),
               (0.117, 32), (0.133, 36), (0.15, 38), (0.167, 40), (0.2, 42), (0.233333, 44)]
            : [(0, 0), (0.017, 2), (0.033, 6), (0.05, 12), (0.067, 22), (0.083, 28),
               (0.1, 34), (0.117, 36), (0.133, 38), (0.175, 40), (0.192, 42), (0.291667, 44)]
        let duration = removing ? removalDuration : layoutDuration
        let animation = CAKeyframeAnimation(keyPath: "position")
        animation.isAdditive = true
        animation.duration = duration
        animation.keyTimes = samples.map { NSNumber(value: min(1, $0.0 / duration)) }
        animation.values = samples.map { _, pixels in
            NSValue(point: CGPoint(x: offset.x * (1 - pixels / 44), y: offset.y * (1 - pixels / 44)))
        }
        animation.calculationMode = .linear
        return animation
    }
    /// Edge's entrance at 11.933–12.433 seconds includes a delayed, damped bounce.
    static func entryAnimation(metrics: WindowsTaskbarMetrics = .standard) -> CAKeyframeAnimation {
        let samples: [(Double, Double)] = [
            (0, 48), (0.18, 48), (0.191667, 31), (0.208333, 19), (0.225, 12),
            (0.241667, 8), (0.258333, 4), (0.275, 2), (0.291667, 0),
            (0.308333, -1), (0.325, -2), (0.341667, -3), (0.416667, -2.5),
            (0.433333, -2), (0.466667, -1), (0.5, 0), (0.516667, 1),
            (0.658333, 0.5), (0.691667, 0)
        ]
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.y")
        animation.duration = 0.691667
        animation.keyTimes = samples.map { NSNumber(value: $0.0 / animation.duration) }
        animation.values = samples.map { NSNumber(value: $0.1 * Double(metrics.scale)) }
        animation.calculationMode = .linear
        return animation
    }
    /// Retarget from the presentation value rather than the previous destination.
    static func animate(_ layer: CALayer?, keyPath: String, to value: Any, duration: TimeInterval) {
        guard let layer else { return }
        if let current = layer.value(forKeyPath: keyPath) as? NSObject,
            let target = value as? NSObject, current.isEqual(target) {
            return
        }
        let from = layer.presentation()?.value(forKeyPath: keyPath) ?? layer.value(forKeyPath: keyPath)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(value, forKeyPath: keyPath)
        layer.removeAnimation(forKey: keyPath)
        if !reducesMotion, duration > 0 {
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = from
            animation.toValue = value
            animation.duration = duration
            animation.timingFunction = timingFunction
            layer.add(animation, forKey: keyPath)
        }
        CATransaction.commit()
    }
}

/// Taskbar sizes derived from the bar height. Every value matches the fixed
/// Windows 11 layout at the standard 48-point height and scales with it.
struct WindowsTaskbarMetrics: Equatable, Sendable {
    static let standardHeight: CGFloat = 48
    static let heightRange: ClosedRange<CGFloat> = 32...96
    static let standard = WindowsTaskbarMetrics(height: standardHeight)

    let height: CGFloat

    init(height: CGFloat) {
        self.height = Self.clampedHeight(height)
    }

    /// Whole points within `heightRange`.
    static func clampedHeight(_ height: CGFloat) -> CGFloat {
        guard height.isFinite else { return standardHeight }
        return min(max(height.rounded(), heightRange.lowerBound), heightRange.upperBound)
    }

    var scale: CGFloat { height / Self.standardHeight }
    /// Gap between the bar edges and its buttons, and between buttons.
    var inset: CGFloat { (4 * scale).rounded() }
    var buttonSize: CGFloat { height - 2 * inset }
    var pitch: CGFloat { buttonSize + inset }
    /// Leading offset of the first button inside the apps section.
    var buttonOffset: CGFloat { (inset / 2).rounded(.down) }
    var margin: CGFloat { (12 * scale).rounded() }
    var iconSize: CGFloat { (24 * scale).rounded() }
    var iconOrigin: CGFloat { ((buttonSize - iconSize) / 2).rounded(.down) }
    var cornerRadius: CGFloat { 4 * scale }
    var indicatorY: CGFloat { buttonSize - inset }
    var indicatorHeight: CGFloat { max(2, (3 * scale).rounded()) }
    var activeIndicatorWidth: CGFloat { (16 * scale).rounded() }
    var inactiveIndicatorWidth: CGFloat { (6 * scale).rounded() }
    var badgeFontSize: CGFloat { 9 * scale }
    var badgeHeight: CGFloat { (16 * scale).rounded() }
    var badgeY: CGFloat { (2 * scale).rounded() }
    var badgePadding: CGFloat { (6 * scale).rounded() }
    var overflowWidth: CGFloat { (32 * scale).rounded() }
    var overflowGlyphSize: CGFloat { (18 * scale).rounded() }
    var trayIconSize: CGFloat { (20 * scale).rounded() }
    var clockWidth: CGFloat { (98 * scale).rounded() }
    var clockFontSize: CGFloat { 12 * scale }
    var clockInset: CGFloat { (7 * scale).rounded() }
    // Native menu extras keep their menu-bar size, so their slots grow but never shrink.
    var menuExtraSlotWidth: CGFloat { max(32, (32 * scale).rounded()) }
    var menuExtraButtonHeight: CGFloat { min(buttonSize, max(32, (32 * scale).rounded())) }
    var menuExtrasMaximumWidth: CGFloat { max(448, (448 * scale).rounded()) }
    /// Height of the top-edge strip that resizes the bar.
    var resizeHandleHeight: CGFloat { max(4, inset) }
}

struct WindowsTaskbarGeometry {
    let apps: CGRect
    let tray: CGRect
    let contentWidth: CGFloat
    var scrolls: Bool { contentWidth > apps.width }
    init(width: CGFloat, appCount: Int, trayWidth: CGFloat, metrics: WindowsTaskbarMetrics = .standard) {
        let available = max(0, width)
        let trayLength = min(available, max(0, trayWidth))
        tray = CGRect(x: available - trayLength, y: 0, width: trayLength, height: metrics.height)
        contentWidth = CGFloat(max(0, appCount)) * metrics.pitch
        let limit = max(0, tray.minX - metrics.margin)
        let length = min(contentWidth, max(0, limit - metrics.margin))
        let origin = max(metrics.margin, min((available - contentWidth) / 2, limit - length))
        apps = CGRect(x: min(origin, limit), y: 0, width: length, height: metrics.height)
    }
}
