import AppKit
import QuartzCore

extension DockCanvasView {
    func layoutCanvas() {
        guard !isLayingOut else { return }
        isLayingOut = true
        defer { isLayingOut = false }
        controller.layout.setTileCanvasFrame(CGRect(origin: .zero, size: bounds.size))
        let pass = DockCanvasLayoutPass(controller: controller, bounds: bounds)
        discardMissingViews(
            tileIDs: Set(controller.displayTiles.map(\.id)), componentIDs: Set(pass.components.map(\.id)))
        controller.tileFrames.removeAll(keepingCapacity: true)
        var offset = pass.initialOffset
        for component in pass.components {
            switch component {
            case .divider(let tile):
                let tileView = view(for: tile)
                if tileView.superview !== self {
                    tileView.removeFromSuperview()
                    addSubview(tileView)
                }
                let size = pass.tileSize(tile)
                tileView.frame = positioned(size: size, offset: offset, vertical: pass.vertical)
                configure(tileView, tile: tile, magnification: pass.magnification)
                controller.tileFrames[tile.id] = tileView.frame
                offset += controller.projected(size: size) + pass.spacing
            case .section(let section): offset += layoutSection(section, offset: offset, pass: pass)
            }
        }
        refreshFrames(force: true)
        updateGroupBackdrops()
        updateDragPreviews()
    }
    func discardMissingViews(tileIDs: Set<String>, componentIDs: Set<String>) {
        for identifier in Array(tiles.keys) where !tileIDs.contains(identifier) {
            if let removed = tiles.removeValue(forKey: identifier) {
                removed.canvas = nil
                removed.removeFromSuperview()
            }
        }
        for identifier in Array(sectionViews.keys) where !componentIDs.contains(identifier) {
            sectionViews.removeValue(forKey: identifier)?.removeFromSuperview()
            scrollViews.removeValue(forKey: identifier)?.removeFromSuperview()
            if let token = scrollObservers.removeValue(forKey: identifier) {
                NotificationCenter.default.removeObserver(token)
            }
        }
    }
    func layoutSection(_ section: DockCanvasSection, offset: CGFloat, pass: DockCanvasLayoutPass) -> CGFloat {
        let component = DockCanvasComponent.section(section)
        let document = sectionViews[component.id] ?? FlippedDockSectionView()
        sectionViews[component.id] = document
        let isScrolling = pass.overflow?.id == section.id
        let sectionLength =
            pass.length(component) + CGFloat(section.tiles.filter { $0.content == .flexibleSpacer }.count) * pass.extra
        let cross = pass.vertical ? bounds.width : bounds.height
        let hostFrame =
            pass.vertical
            ? CGRect(x: 0, y: offset, width: cross, height: sectionLength)
            : CGRect(x: offset, y: 0, width: sectionLength, height: cross)
        configureSectionHost(
            document, id: component.id, frame: hostFrame, scrolling: isScrolling, vertical: pass.vertical)
        var localOffset: CGFloat = 0
        for tile in section.tiles {
            let tileView = view(for: tile)
            if tileView.superview !== document {
                tileView.removeFromSuperview()
                document.addSubview(tileView)
            }
            var size = pass.tileSize(tile)
            if tile.content == .flexibleSpacer {
                if pass.vertical { size.height += pass.extra } else { size.width += pass.extra }
            }
            tileView.frame = positioned(size: size, offset: localOffset, vertical: pass.vertical)
            configure(tileView, tile: tile, magnification: pass.magnification)
            controller.tileFrames[tile.id] = convert(tileView.bounds, from: tileView)
            localOffset += controller.projected(size: size) + pass.spacing
        }
        if isScrolling {
            document.frame.size =
                pass.vertical
                ? CGSize(width: cross, height: max(sectionLength, localOffset - pass.spacing))
                : CGSize(width: max(sectionLength, localOffset - pass.spacing), height: cross)
        }
        if isScrolling, sectionTileIDs[component.id] != section.tiles.map(\.id),
            let scroll = scrollViews[component.id] {
            let endpoint =
                pass.vertical
                ? CGPoint(x: 0, y: max(0, document.frame.height - scroll.contentSize.height))
                : CGPoint(x: max(0, document.frame.width - scroll.contentSize.width), y: 0)
            scroll.contentView.scroll(to: endpoint)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        sectionTileIDs[component.id] = section.tiles.map(\.id)
        return sectionLength + pass.spacing
    }
    func configureSectionHost(
        _ document: NSView, id: String, frame: CGRect, scrolling isScrolling: Bool, vertical: Bool
    ) {
        if isScrolling {
            let scroll = scrollViews[id] ?? DockSectionScrollView()
            (scroll as? DockSectionScrollView)?.isVertical = vertical
            if scrollObservers[id] == nil {
                scroll.contentView.postsBoundsChangedNotifications = true
                scrollObservers[id] = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshFrames() }
                }
            }
            scrollViews[id] = scroll
            scroll.drawsBackground = false
            scroll.hasHorizontalScroller = false
            scroll.hasVerticalScroller = false
            scroll.horizontalScrollElasticity = .none
            scroll.verticalScrollElasticity = .none
            if scroll.superview !== self { addSubview(scroll) }
            if scroll.documentView !== document {
                document.removeFromSuperview()
                scroll.documentView = document
            }
            scroll.frame = frame
        } else {
            scrollViews.removeValue(forKey: id)?.removeFromSuperview()
            if let token = scrollObservers.removeValue(forKey: id) {
                NotificationCenter.default.removeObserver(token)
            }
            if document.superview !== self {
                document.removeFromSuperview()
                addSubview(document)
            }
            document.frame = frame
        }

    }
}

@MainActor
struct DockCanvasLayoutPass {
    let controller: DockCanvasController
    let bounds: CGRect
    let components: [DockCanvasComponent]
    let magnification: DockCanvasController.MagnificationPass
    let overflow: DockCanvasScrollSection?
    var vertical: Bool { controller.position.isVertical }
    var spacing: CGFloat { controller.effectiveTileSpacing }
    var padding: CGFloat { controller.effectiveEdgePadding }
    var total: CGFloat {
        components.reduce(0) { $0 + length($1) } + CGFloat(max(0, components.count - 1)) * spacing + padding * 2
    }
    var extra: CGFloat = 0
    var initialOffset: CGFloat = 0
    init(controller: DockCanvasController, bounds: CGRect) {
        self.controller = controller
        self.bounds = bounds
        self.components = controller.layoutComponents
        self.magnification = controller.magnificationPass()
        self.overflow = controller.scrollableSectionLayout(in: CanvasGeometry(size: bounds.size))
        let flexibleCount = controller.displayTiles.filter { $0.content == .flexibleSpacer }.count
        let axis = controller.projected(size: bounds.size)
        extra = flexibleCount > 0 ? max(0, axis - total) / CGFloat(flexibleCount) : 0
        initialOffset = padding + (flexibleCount == 0 ? max(0, (axis - total) / 2) : 0) + magnification.anchorOffset
    }
    func tileSize(_ tile: Tile) -> CGSize {
        controller.magnifiedTileFrame(
            for: tile, iconSize: magnification.iconSizes[tile.id] ?? controller.effectiveTileSize)
    }
    func length(_ component: DockCanvasComponent) -> CGFloat {
        switch component {
        case .divider(let tile): return controller.projected(size: tileSize(tile))
        case .section(let section):
            if overflow?.id == section.id { return overflow?.axisLength ?? 0 }
            return section.tiles.reduce(0) { $0 + controller.projected(size: tileSize($1)) }
                + CGFloat(max(0, section.tiles.count - 1)) * spacing
        }
    }
}
