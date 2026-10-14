import AppKit
import QuartzCore

/// Live custom glass renderer, retained directly without a hosting adapter.
final class LiveGlassBackdropView: NSView {
    private var lastBlurRadius: Double?
    private var lastSaturation: Double?
    var isAvailable: Bool { NSClassFromString("CABackdropLayer") != nil && NSClassFromString("CAFilter") != nil }
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        apply(cornerRadius: 0, blurRadius: 25, saturation: 1.8)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not available") }

    override func makeBackingLayer() -> CALayer {
        if let cls = NSClassFromString("CABackdropLayer") as? CALayer.Type {
            return cls.init()
        }
        // Fallback when the private class is unavailable: a plain CALayer
        // renders nothing, so the chrome silently degrades to no material
        // rather than crashing.
        return CALayer()
    }

    func apply(cornerRadius: CGFloat, blurRadius: Double, saturation: Double) {
        guard let layer else { return }
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        if lastBlurRadius != blurRadius || lastSaturation != saturation {
            lastBlurRadius = blurRadius
            lastSaturation = saturation
            layer.filters = makeFilters(blurRadius: blurRadius, saturation: saturation)
        }
    }

    private func makeFilters(blurRadius: Double, saturation: Double) -> [Any] {
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type else {
            return []
        }
        let selector = NSSelectorFromString("filterWithType:")
        guard filterClass.responds(to: selector) else { return [] }

        var filters: [Any] = []
        if let blur = filterInstance(filterClass: filterClass, selector: selector, type: "gaussianBlur") {
            blur.setValue(blurRadius, forKey: "inputRadius")
            filters.append(blur)
        }
        if let saturate = filterInstance(filterClass: filterClass, selector: selector, type: "colorSaturate") {
            saturate.setValue(saturation, forKey: "inputAmount")
            filters.append(saturate)
        }
        return filters
    }

    private func filterInstance(
        filterClass: NSObject.Type,
        selector: Selector,
        type: String
    ) -> NSObject? {
        let result = filterClass.perform(selector, with: type)
        return result?.takeUnretainedValue() as? NSObject
    }
}
