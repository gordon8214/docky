import AppKit

@MainActor
enum WindowsStatusGlyph {
    static func drawOverflow(in rect: CGRect, color: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        // The chevron is drawn on an 18-point grid.
        let scale = rect.width / 18
        context.scaleBy(x: scale, y: scale)
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: CGPoint(x: 4, y: 11))
        path.line(to: CGPoint(x: 9, y: 6))
        path.line(to: CGPoint(x: 14, y: 11))
        path.stroke()
        context.restoreGState()
    }
}
