import CoreGraphics
import Foundation

enum ResolvedDockWindowPosition {
    case top
    case left
    case right
    case bottom

    var isVertical: Bool {
        switch self {
        case .left, .right:
            true
        case .top, .bottom:
            false
        }
    }
}

enum DockAxisGeometry {
    static func frame(size: CGSize, offset: CGFloat, canvas: CGSize, edge: ResolvedDockWindowPosition) -> CGRect {
        switch edge {
        case .left: return CGRect(x: 0, y: offset, width: size.width, height: size.height)
        case .right: return CGRect(x: canvas.width - size.width, y: offset, width: size.width, height: size.height)
        case .top: return CGRect(x: offset, y: 0, width: size.width, height: size.height)
        case .bottom: return CGRect(x: offset, y: canvas.height - size.height, width: size.width, height: size.height)
        }
    }

    static func topLeftFrame(_ frame: CGRect, containerHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: containerHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    static func insertionIndex(at location: CGFloat, frames: [CGRect?], vertical: Bool) -> Int {
        frames.firstIndex { frame in
            guard let frame else { return false }
            return location < (vertical ? frame.midY : frame.midX)
        } ?? frames.count
    }
}
