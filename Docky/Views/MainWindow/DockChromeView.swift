import AppKit
import QuartzCore

final class DockChromeView: NSView {
    private let glass = LiveGlassBackdropView()
    private let nativeGlass = NSGlassEffectView()
    private let tint = CALayer()
    private let windowsEdge = CALayer()
    private let windowsMaterial = NSVisualEffectView()
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
        windowsMaterial.material = .hudWindow
        windowsMaterial.blendingMode = .behindWindow
        windowsMaterial.state = .active
        addSubview(windowsMaterial)
        addSubview(nativeGlass)
        addSubview(glass)
        layer?.addSublayer(tint)
        layer?.addSublayer(imageLayer)
        layer?.addSublayer(border)
        layer?.addSublayer(windowsEdge)
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
        windowsMaterial.isHidden = !WindowsTaskbarStyle.isActive
            || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let hidesGlass = WindowsTaskbarStyle.isActive ||
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
        if WindowsTaskbarStyle.isActive {
            layoutWindowsChrome(layer)
            return
        }
        tint.zPosition = 0
        windowsEdge.zPosition = 0
        windowsEdge.isHidden = true
        imageLayer.isHidden = false
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
    private func layoutWindowsChrome(_ layer: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.mask = nil
        windowsMaterial.frame = bounds
        tint.zPosition = 1
        windowsEdge.zPosition = 2
        tint.frame = bounds
        let color = WindowsTaskbarStyle.background(effectiveAppearance)
        tint.backgroundColor = color.withAlphaComponent(
            NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : color.alphaComponent).cgColor
        tint.isHidden = false
        imageLayer.isHidden = true
        border.isHidden = true
        borderGradient.isHidden = true
        windowsEdge.isHidden = false
        windowsEdge.frame = CGRect(
            x: 0, y: 0, width: bounds.width, height: 1 / (window?.backingScaleFactor ?? 2))
        let edgeColor = WindowsTaskbarStyle.foreground(effectiveAppearance).withAlphaComponent(0.12)
        windowsEdge.backgroundColor = edgeColor.cgColor
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
        let position = preferences.effectiveWindowPosition.resolved(
            systemOrientation: DockSettingsService.shared.orientation)
        if position.isVertical {
            imageLayer.bounds.size = CGSize(width: bounds.height, height: bounds.width)
            imageLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            imageLayer.setAffineTransform(CGAffineTransform(rotationAngle: position == .left ? .pi / 2 : -.pi / 2))
        } else {
            imageLayer.setAffineTransform(.identity)
        }
    }
    private var windowsBackgroundActions: [ContextAction] {
        [
            .action("Activity Monitor") {
                let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
                NSWorkspace.shared.openApplication(at: url,
                                                   configuration: NSWorkspace.OpenConfiguration())
            },
            .action("Show Menu Extras", isOn: MenuExtrasNativeBridge.shared.enabled) {
                MenuExtrasNativeBridge.shared.enabled.toggle()
            },
            .action("Taskbar Settings") { (NSApp.delegate as? AppDelegate)?.showSettingsWindow(nil) }
        ]
    }
    override func rightMouseDown(with event: NSEvent) {
        guard WindowsTaskbarStyle.isActive else { super.rightMouseDown(with: event); return }
        // Anchor at the pointer so the menu opens where the bar was clicked, not mid-bar.
        let point = convert(event.locationInWindow, from: nil)
        ContextActionMenuPresenter.popUpMenu(
            actions: windowsBackgroundActions, from: self,
            anchorRect: CGRect(x: point.x, y: bounds.minY, width: 1, height: bounds.height))
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
