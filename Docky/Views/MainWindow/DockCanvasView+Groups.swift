import AppKit

extension DockCanvasView {
    func updateGroupBackdrops() {
        var frames: [String: CGRect] = [:]
        if controller.preferences.showsGroupedOpenedAppsBackdrop {
            for (identifier, frame) in controller.tileFrames {
                if let group = controller.groupedOpenedAppFolderID(for: identifier) {
                    frames[group] = frames[group].map { $0.union(frame) } ?? frame
                }
            }
        }
        for identifier in Array(groupBackdrops.keys) where frames[identifier] == nil {
            groupBackdrops.removeValue(forKey: identifier)?.removeFromSuperview()
        }
        for (identifier, frame) in frames {
            let backdrop = groupBackdrops[identifier] ?? NSView()
            groupBackdrops[identifier] = backdrop
            if backdrop.superview == nil { addSubview(backdrop, positioned: .below, relativeTo: subviews.first) }
            backdrop.frame = frame
            backdrop.wantsLayer = true
            backdrop.setAccessibilityElement(false)
            backdrop.layer?.backgroundColor = NSColor.secondarySystemFill.cgColor
            backdrop.layer?.cornerRadius = 10
        }
    }
}
