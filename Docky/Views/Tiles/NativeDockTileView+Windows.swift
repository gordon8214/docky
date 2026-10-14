import AppKit
import QuartzCore

extension NativeDockTileView {
    func layoutWindowsTile() {
        imageView.frame = CGRect(x: (bounds.width - 24) / 2, y: 8, width: 24, height: 24)
        imageView.layer?.masksToBounds = false
        hoverBackdrop.frame = bounds
        activeBackdrop.frame = bounds
        pressOverlay.frame = .zero
        indicator.frame = CGRect(x: (bounds.width - 16) / 2, y: 36, width: 16, height: 3)
        badge.font = WindowsTaskbarStyle.font(size: 9)
        let badgeWidth = max(16, badge.intrinsicContentSize.width + 6)
        badge.frame = CGRect(x: bounds.width - badgeWidth, y: 2, width: badgeWidth, height: 16)
        content?.frame = bounds.insetBy(dx: 4, dy: 4)
    }
    func updateWindowsAppearance() {
        let pressed = TilePressService.shared.pressedTileID == interaction.tile.id && !wasDragging
        let selected =
            interaction.isAppFolderDropTarget || interaction.isTrashDropTarget
            || interaction.isDocumentDropTarget
        layer?.backgroundColor =
            selected ? WindowsTaskbarStyle.accent(effectiveAppearance).withAlphaComponent(0.2).cgColor : nil
        layer?.cornerRadius = 4
        layer?.shadowOpacity = 0
        alphaValue = 1
        pressOverlay.opacity = 0
        hoverBackdrop.image = nil
        activeBackdrop.image = nil
        hoverBackdrop.isHidden = false
        activeBackdrop.isHidden = false
        hoverBackdrop.layer?.cornerRadius = 4
        activeBackdrop.layer?.cornerRadius = 4
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
        windowsIndicator.cornerRadius = 1.5
        windowsIndicator.backgroundColor =
            (interaction.isFrontmostTile
            ? WindowsTaskbarStyle.accent(effectiveAppearance)
            : WindowsTaskbarStyle.foreground(effectiveAppearance).withAlphaComponent(0.45)).cgColor
        setWindowsIndicatorWidth(interaction.isFrontmostTile ? 16 : 6)
    }
    func setWindowsIndicatorWidth(_ width: CGFloat) {
        // AppKit manages the host layer with an origin anchor. Animate our own centered layer instead.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        windowsIndicator.position = CGPoint(x: 8, y: 1.5)
        CATransaction.commit()
        WindowsTaskbarStyle.animate(
            windowsIndicator, keyPath: "bounds",
            to: NSValue(rect: CGRect(x: 0, y: 0, width: width, height: 3)),
            duration: 0.12)
    }
}
