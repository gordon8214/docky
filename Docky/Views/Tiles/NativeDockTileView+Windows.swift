import AppKit
import QuartzCore

extension NativeDockTileView {
    var windowsMetrics: WindowsTaskbarMetrics { canvas?.windowsMetrics ?? .standard }
    func layoutWindowsTile() {
        let metrics = windowsMetrics
        imageView.frame = CGRect(
            x: ((bounds.width - metrics.iconSize) / 2).rounded(.down), y: metrics.iconOrigin,
            width: metrics.iconSize, height: metrics.iconSize)
        imageView.layer?.masksToBounds = false
        hoverBackdrop.frame = bounds
        activeBackdrop.frame = bounds
        pressOverlay.frame = .zero
        let indicatorWidth = metrics.activeIndicatorWidth
        indicator.frame = CGRect(
            x: (bounds.width - indicatorWidth) / 2, y: metrics.indicatorY,
            width: indicatorWidth, height: metrics.indicatorHeight)
        badge.font = WindowsTaskbarStyle.font(size: metrics.badgeFontSize)
        badge.layer?.cornerRadius = metrics.badgeHeight / 2
        let badgeWidth = max(metrics.badgeHeight, badge.intrinsicContentSize.width + metrics.badgePadding)
        badge.frame = CGRect(
            x: bounds.width - badgeWidth, y: metrics.badgeY, width: badgeWidth, height: metrics.badgeHeight)
        content?.frame = bounds.insetBy(dx: metrics.inset, dy: metrics.inset)
    }
    func updateWindowsAppearance() {
        let pressed = TilePressService.shared.pressedTileID == interaction.tile.id && !wasDragging
        let selected =
            interaction.isAppFolderDropTarget || interaction.isTrashDropTarget
            || interaction.isDocumentDropTarget
        layer?.backgroundColor =
            selected ? WindowsTaskbarStyle.accent(effectiveAppearance).withAlphaComponent(0.2).cgColor : nil
        let cornerRadius = windowsMetrics.cornerRadius
        layer?.cornerRadius = cornerRadius
        shadow = nil
        alphaValue = 1
        pressOverlay.opacity = 0
        hoverBackdrop.image = nil
        activeBackdrop.image = nil
        hoverBackdrop.isHidden = false
        activeBackdrop.isHidden = false
        hoverBackdrop.layer?.cornerRadius = cornerRadius
        activeBackdrop.layer?.cornerRadius = cornerRadius
        hoverBackdrop.layer?.backgroundColor =
            WindowsTaskbarStyle.highlight(effectiveAppearance, pressed: pressed).cgColor
        activeBackdrop.layer?.backgroundColor = WindowsTaskbarStyle.highlight(effectiveAppearance).cgColor
        WindowsTaskbarStyle.animate(
            hoverBackdrop.layer, keyPath: "opacity",
            to: interaction.isHovering ? 1 : 0, duration: 0.10)
        WindowsTaskbarStyle.animate(
            activeBackdrop.layer, keyPath: "opacity",
            to: windowsShowsActiveBackground ? 1 : 0, duration: 0.12)
        WindowsTaskbarStyle.animate(
            imageView.layer, keyPath: "transform.scale", to: pressed ? 0.83 : 1,
            duration: WindowsTaskbarStyle.pressDuration)
    }
    private var windowsShowsActiveBackground: Bool {
        if case .startMenu = interaction.tile.content { return StartMenuService.shared.isPresented }
        return interaction.isFrontmostTile
    }
    func updateWindowsIndicator() {
        indicator.image = nil
        indicator.isHidden = !interaction.showsRunningIndicator
        indicator.layer?.backgroundColor = nil
        if windowsIndicator.superlayer == nil { indicator.layer?.addSublayer(windowsIndicator) }
        windowsIndicator.cornerRadius = windowsMetrics.indicatorHeight / 2
        windowsIndicator.backgroundColor =
            (interaction.isFrontmostTile
            ? WindowsTaskbarStyle.accent(effectiveAppearance)
            : WindowsTaskbarStyle.foreground(effectiveAppearance).withAlphaComponent(0.45)).cgColor
        let metrics = windowsMetrics
        setWindowsIndicatorWidth(
            interaction.isFrontmostTile ? metrics.activeIndicatorWidth : metrics.inactiveIndicatorWidth)
    }
    func setWindowsIndicatorWidth(_ width: CGFloat) {
        // AppKit manages the host layer with an origin anchor. Animate our own centered layer instead.
        let metrics = windowsMetrics
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        windowsIndicator.position = CGPoint(x: metrics.activeIndicatorWidth / 2, y: metrics.indicatorHeight / 2)
        CATransaction.commit()
        WindowsTaskbarStyle.animate(
            windowsIndicator, keyPath: "bounds",
            to: NSValue(rect: CGRect(x: 0, y: 0, width: width, height: metrics.indicatorHeight)),
            duration: 0.12)
    }
}
