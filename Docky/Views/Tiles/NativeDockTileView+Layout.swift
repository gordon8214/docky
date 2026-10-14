import AppKit
import QuartzCore

extension NativeDockTileView {
    func layoutTile() {
        let pad = interaction.appliedTileIconPadding
        let insets = interaction.contentInsets
        var rect = bounds.insetBy(dx: pad + insets.width, dy: pad + insets.height)
        let preferences = interaction.preferences
        let fraction = iconPaddingFraction()
        rect = rect.insetBy(dx: fraction * min(rect.width, rect.height), dy: fraction * min(rect.width, rect.height))
        hoverBackdrop.frame = bounds
        activeBackdrop.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pressOverlay.frame = rect
        CATransaction.commit()
        imageView.frame = rect
        imageView.layer?.cornerRadius =
            preferences.effectiveTileClipShape == .circle ? min(rect.width, rect.height) / 2 : 0
        layoutMinimizedIcon(in: rect)
        content?.frame = rect
        if content is NativeWidgetView { content?.layer?.cornerRadius = interaction.nonAppTileCornerRadius }
        badge.frame = CGRect(
            x: max(0, bounds.width - max(18, badge.intrinsicContentSize.width + 8) - pad), y: pad,
            width: max(18, badge.intrinsicContentSize.width + 8), height: 17)
        let size = interaction.runningIndicatorSize
        let inset = interaction.runningIndicatorInset
        let offset = interaction.runningIndicatorOffsetVector
        let origin: CGPoint
        switch interaction.position {
        case .bottom: origin = CGPoint(x: (bounds.width - size.width) / 2, y: bounds.height - size.height - inset)
        case .top: origin = CGPoint(x: (bounds.width - size.width) / 2, y: inset)
        case .left: origin = CGPoint(x: inset, y: (bounds.height - size.height) / 2)
        case .right: origin = CGPoint(x: bounds.width - size.width - inset, y: (bounds.height - size.height) / 2)
        }
        indicator.frame = CGRect(origin: CGPoint(x: origin.x + offset.width, y: origin.y + offset.height), size: size)
    }

    private func iconPaddingFraction() -> CGFloat {
        let preferences = interaction.preferences
        switch interaction.tile.content {
        case .app(let app): return preferences.appIconOverridePadding(forBundleIdentifier: app.bundleIdentifier)
        case .launchpad: return preferences.launchpadIconPaddingFraction ?? 0
        case .startMenu: return preferences.effectiveStartMenuIconOverridePadding
        case .folder(let folder): return preferences.folderIconOverridePadding(forPath: folder.url.path)
        case .trash:
            return preferences.trashIconOverridePadding(forState: TrashService.shared.isEmpty ? .empty : .full)
        default: return 0
        }
    }

    func layoutMinimizedIcon(in rect: CGRect) {
        let preferences = interaction.preferences
        if case .minimizedWindow(let value) = interaction.tile.content {
            imageView.frame = CGRect(
                x: rect.minX + 4, y: rect.minY + rect.height * 0.1, width: max(0, rect.width - 8),
                height: rect.height * 0.8)
            let side = rect.width * 0.32
            let fraction = preferences.appIconOverridePadding(forBundleIdentifier: value.bundleIdentifier)
            minimizedAppIcon.frame = CGRect(x: rect.maxX - side - 3, y: rect.maxY - side - 3, width: side, height: side)
                .insetBy(dx: side * fraction, dy: side * fraction)
        }
    }

    func drawTile(_ dirtyRect: NSRect) {
        guard interaction.tile.content == .divider else { return }
        let preferences = interaction.preferences
        let vertical = interaction.position.isVertical
        let canvasFrame = DockLayoutService.shared.tileCanvasFrame
        let tileFrame = interaction.globalTileFrame
        let relative =
            vertical
            ? (tileFrame.midY - canvasFrame.minY) / max(1, canvasFrame.height)
            : (tileFrame.midX - canvasFrame.minX) / max(1, canvasFrame.width)
        let positionClass: DockDividerPositionClass = relative < 1 / 3 ? .left : relative >= 2 / 3 ? .right : .center
        let padding =
            DockLayoutService.shared.scaled(DockSettingsService.shared.displayTileSize)
            * min(0.5, max(0, preferences.effectiveDividerPaddingFraction))
        let opacity = min(1, max(0, preferences.effectiveDividerOpacity))
        let offset = preferences.effectiveDividerOffset
        if let resolved = preferences.resolvedDividerImage(forPositionClass: positionClass),
            let image = IconCacheService.shared.image(forImageFileURL: resolved.url),
            let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.translateBy(x: bounds.midX + (vertical ? offset : 0), y: bounds.midY + (vertical ? 0 : -offset))
            if vertical { context.rotate(by: .pi / 2) }
            let available =
                vertical
                ? CGSize(width: bounds.height, height: max(0, bounds.width - padding * 2))
                : CGSize(width: bounds.width, height: max(0, bounds.height - padding * 2))
            let scale =
                min(available.width / max(1, image.size.width), available.height / max(1, image.size.height))
                * max(0.25, preferences.effectiveDividerImageScale)
            context.scaleBy(x: resolved.mirrored ? -1 : 1, y: 1)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(
                in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height),
                from: .zero, operation: .sourceOver, fraction: opacity, respectFlipped: true, hints: nil)
            context.restoreGState()
        } else {
            (preferences.effectiveDividerColor ?? .labelColor).withAlphaComponent(opacity).setFill()
            let rect =
                vertical
                ? CGRect(x: padding + offset, y: bounds.midY, width: max(0, bounds.width - padding * 2), height: 1)
                : CGRect(x: bounds.midX, y: padding - offset, width: 1, height: max(0, bounds.height - padding * 2))
            rect.fill()
        }
    }

}
