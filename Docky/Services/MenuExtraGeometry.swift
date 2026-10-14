import CoreGraphics

/// All backend frames use the global, top-left coordinate system used by Accessibility.
enum MenuExtraGeometry {
    static func visibleItem(_ frame: CGRect, on display: CGRect) -> Bool {
        frame.width.isFinite && frame.height.isFinite && frame.width > 2 && frame.height > 2
            && frame.height <= 64 && display.contains(frame)
            && frame.minY >= display.minY && frame.maxY <= display.minY + 64
    }

    static func popupOrigin(size: CGSize, anchor: CGRect, visible: CGRect) -> CGPoint {
        CGPoint(
            x: max(visible.minX, min(anchor.midX - size.width / 2, visible.maxX - size.width)),
            y: max(visible.minY, min(anchor.minY - size.height - 8, visible.maxY - size.height)))
    }

    static func windowOrigin(container: CGRect, content: CGRect, anchor: CGRect, visible: CGRect) -> CGPoint {
        let destination = popupOrigin(size: content.size, anchor: anchor, visible: visible)
        return CGPoint(x: destination.x - content.minX + container.minX,
                       y: destination.y - content.minY + container.minY)
    }

    static func crop(frame: CGRect, region: CGRect, pixels: CGSize) -> CGRect? {
        guard region.width > 0, region.height > 0, region.contains(frame) else { return nil }
        let scaleX = pixels.width / region.width
        let scaleY = pixels.height / region.height
        return CGRect(x: (frame.minX - region.minX) * scaleX, y: (frame.minY - region.minY) * scaleY,
                      width: frame.width * scaleX, height: frame.height * scaleY).integral
            .intersection(CGRect(origin: .zero, size: pixels))
    }
}
