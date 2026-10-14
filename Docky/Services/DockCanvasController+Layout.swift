import AppKit
import OSLog

extension DockCanvasController {
    var layoutComponents: [DockCanvasComponent] {
        Self.layoutComponents(for: displayTiles)
    }

    static func layoutComponents(for tiles: [Tile]) -> [DockCanvasComponent] {
        var components: [DockCanvasComponent] = []
        var currentSectionID = "primary"
        var currentTiles: [Tile] = []

        func appendCurrentSection() {
            guard !currentTiles.isEmpty else { return }
            let idx = components.count
            components.append(.section(DockCanvasSection(index: idx, id: currentSectionID, tiles: currentTiles)))
            currentTiles = []
        }

        for tile in tiles {
            if tile.id == "divider:running" || tile.id == "divider:trailing" {
                appendCurrentSection()
                components.append(.divider(tile))
                currentSectionID = tile.id == "divider:running" ? "running" : "trailing"
                continue
            }

            currentTiles.append(tile)
        }

        appendCurrentSection()
        return components
    }

    var layoutSections: [DockCanvasSection] {
        layoutComponents.compactMap { component in
            if case .section(let section) = component {
                return section
            }
            return nil
        }
    }

    func scrollableSectionLayout(in proxy: CanvasGeometry) -> DockCanvasScrollSection? {
        guard preferences.overflowBehavior == .scroll else {
            return nil
        }

        let components = layoutComponents
        let availableAxisLength = projected(size: proxy.size)
        guard totalAxisLength(for: components) > availableAxisLength else {
            return nil
        }

        let sections = components.compactMap { component -> DockCanvasSection? in
            if case .section(let section) = component {
                return section
            }
            return nil
        }
        guard let largestSection = sections.max(by: { axisLength(of: $0.tiles) < axisLength(of: $1.tiles) }) else {
            return nil
        }

        let viewportAxisLength = scrollableSectionAxisLength(
            for: largestSection.id,
            in: components,
            availableAxisLength: availableAxisLength
        )
        guard viewportAxisLength > 0 else {
            return nil
        }

        return DockCanvasScrollSection(
            index: largestSection.index, id: largestSection.id, axisLength: viewportAxisLength)
    }

    func totalAxisLength(for components: [DockCanvasComponent]) -> CGFloat {
        let componentLengths = components.reduce(CGFloat(0)) { partialResult, component in
            partialResult + axisLength(of: component)
        }
        let spacings = CGFloat(max(0, components.count - 1)) * effectiveTileSpacing
        return componentLengths + spacings + effectiveEdgePadding * 2
    }

    func scrollableSectionAxisLength(
        for sectionID: String,
        in components: [DockCanvasComponent],
        availableAxisLength: CGFloat
    ) -> CGFloat {
        let innerAvailableAxisLength = max(0, availableAxisLength - effectiveEdgePadding * 2)
        let spacings = CGFloat(max(0, components.count - 1)) * effectiveTileSpacing
        let fixedAxisLength = components.reduce(CGFloat(0)) { partialResult, component in
            switch component {
            case .section(let section) where section.id == sectionID:
                partialResult
            default:
                partialResult + axisLength(of: component)
            }
        }
        return max(0, innerAvailableAxisLength - fixedAxisLength - spacings)
    }

    func axisLength(of component: DockCanvasComponent) -> CGFloat {
        switch component {
        case .divider(let tile):
            let size = DockTileGeometry.size(
                for: tile,
                tileSize: effectiveTileSize,
                tileHeight: tileHeight,
                tileSpacing: effectiveTileSpacing,
                position: position,
                compactWidgets: layout.compactsWidgetsForOverflow
            )
            return projected(size: size)
        case .section(let section):
            return axisLength(of: section.tiles)
        }
    }

    func axisLength(of tiles: [Tile]) -> CGFloat {
        let size = DockTileGeometry.contentSize(
            tiles: tiles,
            tileSize: effectiveTileSize,
            tileHeight: tileHeight,
            tileSpacing: effectiveTileSpacing,
            position: position,
            compactWidgets: layout.compactsWidgetsForOverflow,
            edgePadding: 0
        )
        return projected(size: size)
    }

    var effectiveEdgePadding: CGFloat {
        layout.scaled(Self.edgePadding)
    }

    var effectiveTileSize: CGFloat {
        layout.scaled(baseTileSize)
    }

    var effectiveTileSpacing: CGFloat {
        layout.scaled(preferences.effectiveTileSpacing)
    }

    var dragPreviewStackTileChromeInset: CGFloat {
        floor(effectiveTileSize * 3 / 32)
    }

    func dragPreviewStackRotationDegrees(for depth: Int) -> Double {
        let magnitude = Double(depth) * (Double(depth) + 0.5)
        return depth.isMultiple(of: 2) ? magnitude : -magnitude
    }

    func dragPreviewStackOffset(for depth: Int) -> Double {
        let magnitude = Double(depth) * 2.5
        return depth.isMultiple(of: 2) ? magnitude : -magnitude
    }

    var tileHeight: CGFloat {
        effectiveTileSize + layout.scaled(preferences.effectiveTileVerticalPadding) * 2
    }

    var baseTileSize: CGFloat {
        dockSettings.displayTileSize
    }

    var position: ResolvedDockWindowPosition {
        preferences.windowPosition.resolved(systemOrientation: dockSettings.orientation)
    }

    /// Cross-axis alignment that pushes tiles toward the screen edge the
    /// dock is anchored to, so magnified icons grow inward (away from the
    /// edge) instead of bleeding off-screen.
}
