import AppKit
import QuartzCore

/// Hit testing follows animated positions, rather than the model's final destination.
final class WindowsTaskbarDocumentView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        for view in subviews.reversed() where !view.isHidden {
            if let tile = view as? NativeDockTileView {
                let rect = tile.layer?.presentation()?.frame ?? tile.frame
                if rect.contains(local), tile.alphaValue > 0, !tile.isDragPreview { return tile }
            }
        }
        return nil
    }
}

extension DockCanvasView {
    var windowsAppTiles: [Tile] {
        let source = controller.displayTiles
        let start =
            source.first {
                if case .startMenu = $0.content { return true }
                return false
            }
            ?? Tile(id: "windows:start", content: .startMenu(StartMenuTile(identifier: "windows:start")))
        return [start]
            + source.filter {
                if case .app(let app) = $0.content { return app.displayedWidget == nil }
                return false
            }
    }
    var windowsExtraTiles: [Tile] {
        Self.windowsExtraTiles(from: controller.displayTiles)
    }
    static func windowsExtraTiles(from source: [Tile]) -> [Tile] {
        let calendarID = source.first {
            if case .widget(let widget) = $0.content { return widget.kind == .calendar }
            return false
        }?.id
        return source.filter {
            switch $0.content {
            case .app(let app): return app.displayedWidget != nil
            case .startMenu, .divider, .spacer, .flexibleSpacer: return false
            case .widget(let widget):
                return widget.kind != .calendarDate && $0.id != calendarID
            default: return true
            }
        }
    }
    func layoutWindowsTaskbar() {
        groupBackdrops.values.forEach { $0.removeFromSuperview() }
        groupBackdrops.removeAll()
        let apps = windowsAppTiles
        configureWindowsStatus()
        let geometry = WindowsTaskbarGeometry(
            width: bounds.width, appCount: apps.count,
            trayWidth: windowsStatus?.preferredWidth ?? 200)
        let changed = windowsTileIDs != apps.map(\.id)
        let animate = !windowsTileIDs.isEmpty && changed && !WindowsTaskbarStyle.reducesMotion
        let duration =
            apps.count < windowsTileIDs.count
            ? WindowsTaskbarStyle.removalDuration
            : WindowsTaskbarStyle.layoutDuration
        let oldOrigins = Dictionary(
            uniqueKeysWithValues: tiles.map { id, tile in
                (id, convert(tile.layer?.presentation()?.frame ?? tile.frame, from: tile.superview))
            })
        removeWindowsTiles(
            except: Set(apps.map(\.id)), oldOrigins: oldOrigins, animate: animate, duration: duration)
        let sectionID = "windows-apps"
        for key in Array(sectionViews.keys) where key != sectionID {
            sectionViews.removeValue(forKey: key)?.removeFromSuperview()
            scrollViews.removeValue(forKey: key)?.removeFromSuperview()
            if let observer = scrollObservers.removeValue(forKey: key) {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        let document = sectionViews[sectionID] ?? WindowsTaskbarDocumentView()
        document.wantsLayer = true
        sectionViews[sectionID] = document
        // Always host in a clip view so centered-to-overflow changes preserve hierarchy and scroll position.
        configureSectionHost(document, id: sectionID, frame: geometry.apps, scrolling: true, vertical: false)
        document.frame = CGRect(
            x: 0, y: 0, width: max(geometry.apps.width, geometry.contentWidth), height: 48)
        windowsStatus?.frame = geometry.tray
        controller.tileFrames.removeAll(keepingCapacity: true)
        positionWindowsTiles(apps, in: document, oldOrigins: oldOrigins, animate: animate, duration: duration)
        windowsTileIDs = apps.map(\.id)
        refreshFrames(force: true)
        updateDragPreviews()
        if animate { trackWindowsAnimation(duration: duration) }
    }
    private func configureWindowsStatus() {
        if windowsStatus == nil {
            let status = WindowsTaskbarStatusView()
            windowsStatus = status
            addSubview(status)
        }
        windowsStatus?.extraTiles = windowsExtraTiles
        windowsStatus?.calendarTile = controller.displayTiles.first {
            if case .widget(let widget) = $0.content {
                return widget.kind == .calendar
            }
            return false
        }
    }
    private func removeWindowsTiles(
        except keptIDs: Set<String>, oldOrigins: [String: CGRect],
        animate: Bool, duration: TimeInterval
    ) {
        let removedIDs = Set(tiles.keys).subtracting(keptIDs)
        for id in removedIDs {
            guard let tile = tiles.removeValue(forKey: id) else { continue }
            tile.dismissTransientPresentation()
            if animate {
                let button = oldOrigins[id] ?? tile.frame
                let imageFrame = tile.imageView.layer?.presentation()?.frame ?? tile.imageView.frame
                let ghost = NSImageView(frame: imageFrame.offsetBy(dx: button.minX, dy: button.minY))
                ghost.wantsLayer = true
                ghost.image = tile.imageView.image
                ghost.imageScaling = .scaleProportionallyUpOrDown
                ghost.setAccessibilityElement(false)
                addSubview(ghost)
                WindowsTaskbarStyle.animate(ghost.layer, keyPath: "opacity", to: 0, duration: duration)
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak ghost] in
                    ghost?.removeFromSuperview()
                }
            }
            tile.canvas = nil
            tile.removeFromSuperview()
        }
    }
    private func positionWindowsTiles(
        _ apps: [Tile], in document: NSView,
        oldOrigins: [String: CGRect], animate: Bool, duration: TimeInterval
    ) {
        for (index, tile) in apps.enumerated() {
            let existed = tiles[tile.id] != nil
            let tileView = view(for: tile)
            if tileView.superview !== document {
                tileView.removeFromSuperview()
                document.addSubview(tileView)
            }
            let target = CGRect(x: CGFloat(index) * 44 + 2, y: 4, width: 40, height: 40)
            tileView.frame = target
            if animate, existed, let old = oldOrigins[tile.id], let layer = tileView.layer {
                let origin = document.convert(old, from: self)
                let offset = CGPoint(x: origin.midX - target.midX, y: origin.midY - target.midY)
                let motion = WindowsTaskbarStyle.positionAnimation(
                    offset: offset, removing: duration == WindowsTaskbarStyle.removalDuration)
                layer.add(motion, forKey: "taskbar-position")
            }
            tileView.interaction.renderedTileSize = 40
            configure(tileView, tile: tile, magnification: .inactive)
            if animate, !existed {
                let entry = WindowsTaskbarStyle.entryAnimation()
                tileView.imageView.layer?.add(entry, forKey: "taskbar-entry")
            }
        }
    }
    func trackWindowsAnimation(duration: TimeInterval) {
        windowsAnimationTimer?.invalidate()
        let end = CACurrentMediaTime() + duration
        windowsAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.window != nil, WindowsTaskbarStyle.isActive else {
                    self?.windowsAnimationTimer?.invalidate()
                    return
                }
                self.refreshFrames(force: true)
                if let window = self.window {
                    let pointer = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                    for (id, tile) in self.tiles {
                        let hovered = self.controller.visibleTileFrames[id]?.contains(pointer) == true
                        if tile.interaction.isHovering != hovered { tile.hover(hovered) }
                    }
                }
                if CACurrentMediaTime() >= end {
                    self.windowsAnimationTimer?.invalidate()
                    self.windowsAnimationTimer = nil
                }
            }
        }
    }
    func clearWindowsTaskbar() {
        tiles.values.forEach { $0.layer?.removeAnimation(forKey: "taskbar-position") }
        windowsAnimationTimer?.invalidate()
        windowsAnimationTimer = nil
        windowsTileIDs.removeAll()
        windowsStatus?.dismissPopup()
        windowsStatus?.removeFromSuperview()
        windowsStatus = nil
        WindowsTaskbarTooltip.shared.dismiss()
    }
}
