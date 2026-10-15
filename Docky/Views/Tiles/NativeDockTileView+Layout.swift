import AppKit
import QuartzCore

extension NativeDockTileView {
    func layoutTile() {
        // Taskbar tiles use the Windows layout; tiles off the taskbar (the tray popup,
        // drag previews) use the generic one.
        if canvas != nil { layoutWindowsTile(); return }
        let pad = interaction.appliedTileIconPadding
        let insets = interaction.contentInsets
        var rect = bounds.insetBy(dx: pad + insets.width, dy: pad + insets.height)
        let fraction = iconPaddingFraction()
        rect = rect.insetBy(dx: fraction * min(rect.width, rect.height), dy: fraction * min(rect.width, rect.height))
        hoverBackdrop.frame = bounds
        activeBackdrop.frame = bounds
        imageView.frame = rect
        imageView.layer?.cornerRadius = 0
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
}
