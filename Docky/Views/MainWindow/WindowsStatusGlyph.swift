import AppKit

/// Simple stroked vector status glyphs, rendered in logical points.
@MainActor
enum WindowsStatusGlyph {
    static func draw(_ name: String, in rect: CGRect, color: NSColor, level: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        color.setStroke()
        color.setFill()
        let path = NSBezierPath()
        path.lineWidth = 1.2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        switch name {
        case "overflow":
            path.move(to: CGPoint(x: 4, y: 11))
            path.line(to: CGPoint(x: 9, y: 6))
            path.line(to: CGPoint(x: 14, y: 11))
        case "network-wifi":
            for radius: CGFloat in [4, 7, 10] {
                path.move(to: CGPoint(x: 9 - radius * 0.7, y: 14 - radius * 0.7))
                path.curve(
                    to: CGPoint(x: 9 + radius * 0.7, y: 14 - radius * 0.7),
                    controlPoint1: CGPoint(x: 9 - radius * 0.35, y: 14 - radius * 1.15),
                    controlPoint2: CGPoint(x: 9 + radius * 0.35, y: 14 - radius * 1.15))
            }
            NSBezierPath(ovalIn: CGRect(x: 8, y: 13, width: 2, height: 2)).fill()
        case "network-wired":
            path.appendRoundedRect(CGRect(x: 1, y: 2, width: 14, height: 10), xRadius: 1, yRadius: 1)
            path.move(to: CGPoint(x: 8, y: 12))
            path.line(to: CGPoint(x: 8, y: 16))
            path.move(to: CGPoint(x: 4, y: 16))
            path.line(to: CGPoint(x: 12, y: 16))
        case "network-offline":
            path.appendOval(in: CGRect(x: 2, y: 2, width: 14, height: 14))
            path.appendOval(in: CGRect(x: 6, y: 2, width: 6, height: 14))
            path.move(to: CGPoint(x: 2, y: 9))
            path.line(to: CGPoint(x: 16, y: 9))
        case "volume", "volume-muted": drawVolume(name, path: path)
        default: drawBattery(name, level: level, path: path)
        }
        path.stroke()
        context.restoreGState()
    }

    private static func drawVolume(_ name: String, path: NSBezierPath) {
        path.move(to: CGPoint(x: 1, y: 7))
        path.line(to: CGPoint(x: 5, y: 7))
        path.line(to: CGPoint(x: 9, y: 3))
        path.line(to: CGPoint(x: 9, y: 15))
        path.line(to: CGPoint(x: 5, y: 11))
        path.line(to: CGPoint(x: 1, y: 11))
        path.close()
        if name == "volume-muted" {
            path.move(to: CGPoint(x: 12, y: 6))
            path.line(to: CGPoint(x: 17, y: 12))
            path.move(to: CGPoint(x: 17, y: 6))
            path.line(to: CGPoint(x: 12, y: 12))
        } else {
            for offset: CGFloat in [12, 15] {
                path.move(to: CGPoint(x: offset, y: offset == 12 ? 6 : 3))
                path.curve(
                    to: CGPoint(x: offset, y: offset == 12 ? 12 : 15),
                    controlPoint1: CGPoint(x: offset + 3, y: 7), controlPoint2: CGPoint(x: offset + 3, y: 11))
            }
        }
    }

    private static func drawBattery(_ name: String, level: CGFloat, path: NSBezierPath) {
            path.appendRoundedRect(CGRect(x: 1, y: 5, width: 14, height: 8), xRadius: 2, yRadius: 2)
            NSBezierPath(rect: CGRect(x: 16, y: 7, width: 1.5, height: 4)).fill()
            NSBezierPath(
                roundedRect: CGRect(x: 3, y: 7, width: 10 * min(1, max(0, level)), height: 4), xRadius: 0.5,
                yRadius: 0.5
            ).fill()
            if name == "battery-charging" {
                let bolt = NSBezierPath()
                bolt.move(to: CGPoint(x: 10, y: 3))
                bolt.line(to: CGPoint(x: 6, y: 10))
                bolt.line(to: CGPoint(x: 9, y: 10))
                bolt.line(to: CGPoint(x: 7, y: 15))
                bolt.line(to: CGPoint(x: 12, y: 7))
                bolt.line(to: CGPoint(x: 9, y: 7))
                bolt.close()
                bolt.lineWidth = 1
                bolt.stroke()
            }
    }

}
