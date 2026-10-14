import AppKit
import QuartzCore

final class DockChromeView: NSView {
    private let glass = LiveGlassBackdropView()
    private let nativeGlass = NSGlassEffectView()
    private let tint = CALayer()
    private let imageLayer = CALayer()
    private let border = CAShapeLayer()
    private let borderGradient = CAGradientLayer()
    private let borderMask = CAShapeLayer()
    private var backgroundURL: URL?
    private var backgroundImage: NSImage?
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(nativeGlass)
        addSubview(glass)
        layer?.addSublayer(tint)
        layer?.addSublayer(imageLayer)
        layer?.addSublayer(border)
        border.fillColor = nil
        borderMask.fillColor = nil
        borderMask.strokeColor = NSColor.white.cgColor
        borderGradient.mask = borderMask
        borderGradient.colors = [
            NSColor.white.withAlphaComponent(0.5).cgColor,
            NSColor.white.withAlphaComponent(0.1).cgColor, NSColor.white.withAlphaComponent(0.3).cgColor
        ]
        layer?.addSublayer(borderGradient)
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }
    func refresh() {
        let preferences = DockyPreferences.shared
        let hidesGlass =
            preferences.effectiveDisablesGlassLook || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        glass.isHidden = hidesGlass || !glass.isAvailable
        nativeGlass.isHidden = hidesGlass || glass.isAvailable
        if backgroundURL != preferences.effectiveWindowBackgroundImageURL {
            backgroundURL = preferences.effectiveWindowBackgroundImageURL
            backgroundImage = backgroundURL.flatMap(NSImage.init(contentsOf:))
        }
        needsLayout = true
    }
    override func layout() {
        super.layout()
        guard let layer else { return }
        let preferences = DockyPreferences.shared
        let cap = min(bounds.width, bounds.height) / 2
        let radii = [
            preferences.effectiveWindowCornerRadiusTopLeading, preferences.effectiveWindowCornerRadiusTopTrailing,
            preferences.effectiveWindowCornerRadiusBottomTrailing, preferences.effectiveWindowCornerRadiusBottomLeading
        ].map { min(max(0, $0), cap) }
        let path = Self.roundedPath(in: bounds, radii: radii)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let mask = CAShapeLayer()
        mask.path = path
        layer.mask = mask
        glass.frame = bounds
        glass.apply(cornerRadius: 0, blurRadius: 25, saturation: 1.8)
        nativeGlass.frame = bounds
        nativeGlass.cornerRadius = radii.max() ?? 0
        tint.frame = bounds
        let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        tint.backgroundColor =
            preferences.effectiveWindowTintColor
            .withAlphaComponent(opaque ? 1 : preferences.effectiveWindowTintOpacity).cgColor
        tint.isHidden = backgroundImage != nil
        configureBackgroundImage(preferences)
        border.frame = bounds
        border.path = path
        border.lineWidth = max(0, preferences.effectiveWindowBorderWidth)
        border.strokeColor = preferences.effectiveWindowBorderColor?.cgColor
        borderGradient.frame = bounds
        borderMask.frame = bounds
        borderMask.path = path
        borderMask.lineWidth = border.lineWidth
        borderGradient.isHidden =
            preferences.effectiveWindowBorderColor != nil || preferences.effectiveDisablesGlassLook
        border.isHidden = preferences.effectiveWindowBorderColor == nil
        CATransaction.commit()
    }
    private func configureBackgroundImage(_ preferences: DockyPreferences) {
        imageLayer.frame = bounds
        imageLayer.contents = backgroundImage
        imageLayer.contentsGravity = .resizeAspectFill
        if let image = backgroundImage, preferences.effectiveWindowBackgroundImageMode == .sprite {
            let capWidth = max(1, min(image.size.width / 3, image.size.height)) / image.size.width
            imageLayer.contentsCenter = CGRect(x: capWidth, y: 0, width: max(0, 1 - capWidth * 2), height: 1)
            imageLayer.contentsGravity = .resize
        } else {
            imageLayer.contentsCenter = CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let position = preferences.windowPosition.resolved(systemOrientation: DockSettingsService.shared.orientation)
        if position.isVertical {
            imageLayer.bounds.size = CGSize(width: bounds.height, height: bounds.width)
            imageLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            imageLayer.setAffineTransform(CGAffineTransform(rotationAngle: position == .left ? .pi / 2 : -.pi / 2))
        } else {
            imageLayer.setAffineTransform(.identity)
        }
    }
    static func roundedPath(in rect: CGRect, radii: [CGFloat]) -> CGPath {
        let path = CGMutablePath()
        let topLeading = radii[0]
        let topTrailing = radii[1]
        let bottomTrailing = radii[2]
        let bottomLeading = radii[3]
        path.move(to: CGPoint(x: rect.minX + topLeading, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topTrailing, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + topTrailing), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomTrailing))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - bottomTrailing, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bottomLeading, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - bottomLeading), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeading))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topLeading, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
