//
//  WindowSwitcherCardView.swift
//  Docky
//
//  One window in the Windows 11–style switcher: a rounded tile holding an
//  icon-and-title header above the window's thumbnail, a selection frame,
//  a hover fill, and a close button that appears on hover.
//

import AppKit
import Combine

/// What a switcher card shows. Plain values rather than `AppWindow`, so the
/// UI regression can build cards without live AX elements.
struct WindowSwitcherCard: Equatable {
    let id: String
    let title: String
    let appName: String
    let icon: NSImage?
    let thumbnail: NSImage?
    /// Width over height of the window, which sets the card's width.
    let aspectRatio: CGFloat
}

/// The header's icon and title sizes, which Settings controls.
@MainActor
struct WindowSwitcherHeaderStyle: Equatable {
    static let standard = Self(
        iconSize: WindowSwitcherGeometry.Metrics.defaultIconSize,
        fontSize: WindowSwitcherGeometry.Metrics.defaultFontSize)

    let iconSize: CGFloat
    let fontSize: CGFloat
    let font: NSFont
    /// Fits the icon and one line of the title.
    let height: CGFloat

    init(iconSize: CGFloat, fontSize: CGFloat) {
        self.iconSize = WindowSwitcherGeometry.clampedIconSize(iconSize)
        self.fontSize = WindowSwitcherGeometry.clampedFontSize(fontSize)
        font = WindowsTaskbarStyle.font(size: self.fontSize)
        height = WindowSwitcherGeometry.headerHeight(
            iconSize: self.iconSize, textHeight: NSLayoutManager().defaultLineHeight(for: font))
    }

    /// The sizes in Settings, reusing this style while they're unchanged.
    func updatedFromPreferences() -> Self {
        let preferences = DockyPreferences.shared
        guard preferences.windowSwitcherIconSize != iconSize || preferences.windowSwitcherFontSize != fontSize else {
            return self
        }
        return Self(iconSize: preferences.windowSwitcherIconSize, fontSize: preferences.windowSwitcherFontSize)
    }
}

final class WindowSwitcherCardView: NSView {
    static let selectionBorderWidth: CGFloat = 3
    static let cornerRadius: CGFloat = 8
    static let tileEdgeWidth: CGFloat = 1
    static let thumbnailCornerRadius: CGFloat = 4
    static let thumbnailBorderWidth: CGFloat = 1
    static let thumbnailShadowBlurRadius: CGFloat = 3
    /// One point down; the shadow view isn't flipped.
    static let thumbnailShadowOffset = CGSize(width: 0, height: -1)
    static let fallbackIconSize: CGFloat = 48
    static let closeButtonSize: CGFloat = 24

    var onConfirm: (() -> Void)?
    var onClose: (() -> Void)?
    var onContextMenu: ((WindowSwitcherCardView) -> Void)?

    private(set) var card: WindowSwitcherCard
    var headerStyle = WindowSwitcherHeaderStyle.standard {
        didSet {
            guard headerStyle != oldValue else { return }
            titleField.font = headerStyle.font
            needsLayout = true
        }
    }
    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            setAccessibilitySelected(isSelected)
            updatePalette()
        }
    }
    private(set) var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            closeButton.isHidden = !isHovered
            updatePalette()
        }
    }

    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    let closeButton = WindowSwitcherCloseButton()
    private let thumbnailContainer = NSView()
    /// Casts the thumbnail's shadow into the card's padding. It sits beside
    /// `thumbnailContainer` rather than inside it: AppKit masks views that have
    /// a corner radius, so the container and `thumbnailView` would clip it.
    private let thumbnailShadowView = NSView()
    private let thumbnailView = NSImageView()
    private let selectionLayer = CALayer()
    private var trackingArea: NSTrackingArea?
    private var systemColorsObservation: AnyCancellable?

    var showsFallbackIcon: Bool { card.thumbnail == nil }

    override var isFlipped: Bool { true }

    init(card: WindowSwitcherCard) {
        self.card = card
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius

        iconView.imageScaling = .scaleProportionallyUpOrDown
        titleField.font = headerStyle.font
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.cell?.truncatesLastVisibleLine = true

        closeButton.isHidden = true
        closeButton.target = self
        closeButton.action = #selector(closeWindow)

        thumbnailContainer.wantsLayer = true
        thumbnailContainer.layer?.cornerRadius = Self.thumbnailCornerRadius
        thumbnailContainer.layer?.masksToBounds = true
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = Self.thumbnailCornerRadius
        thumbnailView.layer?.masksToBounds = true
        thumbnailContainer.addSubview(thumbnailView)
        thumbnailShadowView.wantsLayer = true

        selectionLayer.cornerRadius = Self.cornerRadius
        selectionLayer.borderWidth = Self.selectionBorderWidth
        selectionLayer.zPosition = 10
        layer?.addSublayer(selectionLayer)

        for child in [iconView, titleField, thumbnailShadowView, thumbnailContainer, closeButton] {
            addSubview(child)
        }

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        apply(card)
        updatePalette()
        // Cards outlive one switcher session, so follow accent color changes.
        systemColorsObservation = NotificationCenter.default.publisher(
            for: NSColor.systemColorsDidChangeNotification
        ).sink { [weak self] _ in self?.updatePalette() }
    }

    required init?(coder: NSCoder) { nil }

    func update(_ card: WindowSwitcherCard) {
        guard card != self.card else { return }
        apply(card)
        needsLayout = true
        updatePalette()
    }

    private func apply(_ card: WindowSwitcherCard) {
        self.card = card
        iconView.image = card.icon
        titleField.stringValue = card.title.isEmpty ? card.appName : card.title
        thumbnailView.image = card.thumbnail ?? card.icon
        let label = [card.title, card.appName].filter { !$0.isEmpty }.joined(separator: ", ")
        setAccessibilityLabel(label)
        closeButton.setAccessibilityLabel(
            String(localized: "Close \(card.title.isEmpty ? card.appName : card.title)"))
    }

    override func layout() {
        super.layout()
        typealias Metrics = WindowSwitcherGeometry.Metrics
        let padding = Metrics.cardPadding
        let headerMidY = padding + headerStyle.height / 2
        let iconSize = headerStyle.iconSize
        // A header with an odd height centers on a half point, so align to
        // pixels to keep the icon and × sharp on 1x displays.
        iconView.frame = backingAlignedRect(
            CGRect(x: padding + 2, y: headerMidY - iconSize / 2, width: iconSize, height: iconSize),
            options: .alignAllEdgesNearest)
        let closeSize = Self.closeButtonSize
        closeButton.frame = backingAlignedRect(
            CGRect(
                x: bounds.width - padding - closeSize, y: headerMidY - closeSize / 2,
                width: closeSize, height: closeSize),
            options: .alignAllEdgesNearest)
        let titleX = iconView.frame.maxX + 8
        let titleHeight = ceil(titleField.intrinsicContentSize.height)
        titleField.frame = CGRect(
            x: titleX, y: headerMidY - titleHeight / 2,
            width: max(0, closeButton.frame.minX - 4 - titleX), height: titleHeight)

        thumbnailContainer.frame = WindowSwitcherGeometry.thumbnailFrame(
            inCardOfSize: bounds.size, headerHeight: headerStyle.height)
        if showsFallbackIcon {
            let size = min(Self.fallbackIconSize, thumbnailContainer.bounds.height)
            thumbnailView.frame = CGRect(
                x: (thumbnailContainer.bounds.width - size) / 2,
                y: (thumbnailContainer.bounds.height - size) / 2, width: size, height: size)
        } else {
            // Fit the view to the picture so its own corners are the rounded ones,
            // including portrait windows that don't fill the thumbnail's width.
            // Pixel-aligned so the hairline border stays sharp.
            thumbnailView.frame = thumbnailContainer.backingAlignedRect(
                Self.aspectFitRect(for: card.thumbnail?.size ?? .zero, in: thumbnailContainer.bounds),
                options: .alignAllEdgesNearest)
        }
        thumbnailShadowView.frame = convert(thumbnailView.frame, from: thumbnailContainer)
        thumbnailShadowView.isHidden = showsFallbackIcon

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        selectionLayer.frame = bounds
        thumbnailShadowView.layer?.shadowPath = CGPath(
            roundedRect: thumbnailShadowView.bounds, cornerWidth: Self.thumbnailCornerRadius,
            cornerHeight: Self.thumbnailCornerRadius, transform: nil)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updatePalette()
    }

    /// Every card is a tile, like Windows 11's Alt+Tab, using the WinUI card
    /// fill (white at 70% light, 5% dark). Hovering lays the taskbar's hover
    /// highlight over it.
    static func tileFill(dark: Bool, hovered: Bool) -> NSColor {
        switch (dark, hovered) {
        case (false, false): NSColor(calibratedWhite: 1, alpha: 0.7)
        case (false, true): NSColor(calibratedWhite: 0.94, alpha: 0.71)
        case (true, false): NSColor(calibratedWhite: 1, alpha: 0.05)
        case (true, true): NSColor(calibratedWhite: 1, alpha: 0.12)
        }
    }

    /// Stronger than the WinUI card stroke so each tile reads clearly on the
    /// panel. Dark mode uses a light edge, which shows against the dark panel.
    static func tileEdge(dark: Bool) -> NSColor {
        dark ? NSColor.white.withAlphaComponent(0.18) : NSColor.black.withAlphaComponent(0.18)
    }

    static func aspectFitRect(for size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0, !bounds.isEmpty else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: bounds.minX + (bounds.width - fitted.width) / 2,
            y: bounds.minY + (bounds.height - fitted.height) / 2,
            width: fitted.width, height: fitted.height)
    }

    private func updatePalette() {
        let appearance = effectiveAppearance
        let dark = WindowsTaskbarStyle.isDark(appearance)
        let foreground = WindowsTaskbarStyle.foreground(appearance)
        titleField.textColor = foreground
        closeButton.glyphColor = foreground

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = Self.tileFill(dark: dark, hovered: isHovered).cgColor
        layer?.borderWidth = Self.tileEdgeWidth
        layer?.borderColor = Self.tileEdge(dark: dark).cgColor
        // The system accent color, resolved for this card's appearance.
        var accent = NSColor.controlAccentColor.cgColor
        appearance.performAsCurrentDrawingAppearance { accent = NSColor.controlAccentColor.cgColor }
        selectionLayer.borderColor = isSelected ? accent : NSColor.clear.cgColor
        thumbnailContainer.layer?.backgroundColor = showsFallbackIcon
            ? WindowsTaskbarStyle.highlight(appearance).cgColor
            : NSColor.clear.cgColor
        // A window edge and a soft shadow, but not for the fallback app icon.
        thumbnailView.layer?.borderWidth = showsFallbackIcon ? 0 : Self.thumbnailBorderWidth
        // A translucent mid gray, which shows against both light and dark
        // window contents; black or white disappears on half of them.
        thumbnailView.layer?.borderColor = (dark
            ? NSColor(calibratedWhite: 0.65, alpha: 0.5)
            : NSColor(calibratedWhite: 0.45, alpha: 0.55)).cgColor
        CATransaction.commit()

        // AppKit owns a layer-backed view's shadow and resets the layer's
        // shadow opacity, so the shadow goes through `NSView.shadow`. A black
        // shadow barely shows on the dark panel, so it's stronger there.
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.6 : 0.34)
        shadow.shadowBlurRadius = Self.thumbnailShadowBlurRadius
        shadow.shadowOffset = Self.thumbnailShadowOffset
        thumbnailShadowView.shadow = shadow
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    func setHovered(_ hovered: Bool) { isHovered = hovered }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Accept the press here so it isn't treated as a click outside the panel.
    override func mouseDown(with event: NSEvent) {}

    // Clicks switch to the window whatever modifiers are held: ⌘ is down for
    // the whole ⌘Tab session.
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        onConfirm?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onContextMenu?(self)
    }

    override func accessibilityPerformPress() -> Bool {
        onConfirm?()
        return true
    }

    @objc private func closeWindow() {
        onClose?()
    }
}

/// The hover-only × button. Like Windows close buttons it fills red on hover.
final class WindowSwitcherCloseButton: NSButton {
    var glyphColor: NSColor = .labelColor {
        didSet { updateAppearance() }
    }
    private var isHovered = false {
        didSet { updateAppearance() }
    }
    private var trackingArea: NSTrackingArea?

    init() {
        super.init(frame: .zero)
        isBordered = false
        title = ""
        imagePosition = .imageOnly
        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        wantsLayer = true
        layer?.cornerRadius = 4
        updateAppearance()
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override var isHidden: Bool {
        didSet { if isHidden { isHovered = false } }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func updateAppearance() {
        contentTintColor = isHovered ? .white : glyphColor
        layer?.backgroundColor = isHovered
            ? NSColor(calibratedRed: 0.77, green: 0.17, blue: 0.11, alpha: 1).cgColor
            : NSColor.clear.cgColor
    }
}
