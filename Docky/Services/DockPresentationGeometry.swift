import CoreGraphics
import Foundation

/// Screen-space placement shared by anchored native presentations.
enum DockPresentationGeometry {
    struct Request {
        let size: CGSize
        let source: CGRect
        let visible: CGRect
        let edge: ResolvedDockWindowPosition
        var gap: CGFloat = 0
    }
    static func screenIndex(containing source: CGRect, frames: [CGRect]) -> Int? {
        let center = CGPoint(x: source.midX, y: source.midY)
        return frames.firstIndex { $0.contains(center) } ?? frames.firstIndex { $0.intersects(source) }
    }
    static func origin(for request: Request) -> CGPoint {
        let size = request.size
        let source = request.source
        let visible = request.visible
        let gap = request.gap
        let centeredX = min(
            max(source.midX - size.width / 2, visible.minX), max(visible.minX, visible.maxX - size.width))
        let centeredY = min(
            max(source.midY - size.height / 2, visible.minY), max(visible.minY, visible.maxY - size.height))
        switch request.edge {
        case .bottom:
            let proposed = source.maxY + gap
            return CGPoint(
                x: centeredX,
                y: proposed + size.height <= visible.maxY
                    ? proposed : max(visible.minY, source.minY - size.height - gap))
        case .top:
            let proposed = source.minY - size.height - gap
            return CGPoint(x: centeredX, y: proposed >= visible.minY ? proposed : source.maxY + gap)
        case .left:
            let proposed = source.maxX + gap
            return CGPoint(
                x: proposed + size.width <= visible.maxX
                    ? proposed : max(visible.minX, source.minX - size.width - gap), y: centeredY)
        case .right:
            let proposed = source.minX - size.width - gap
            return CGPoint(x: proposed >= visible.minX ? proposed : source.maxX + gap, y: centeredY)
        }
    }
    static func screenFrame(fromTopLeft frame: CGRect, windowFrame: CGRect) -> CGRect {
        CGRect(
            x: windowFrame.minX + frame.minX, y: windowFrame.maxY - frame.maxY,
            width: frame.width, height: frame.height)
    }
}
