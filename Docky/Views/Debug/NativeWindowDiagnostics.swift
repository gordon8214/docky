import AppKit

extension NativeWindowDiagnosticsController {
    func noPreviewReason(for window: AppWindow) -> String {
        if PermissionsService.shared.screenCapture != .granted {
            return "Screen Recording permission not granted"
        }
        if window.isMinimized {
            // Minimized captures retry up to three times; a miss means
            // every attempt failed or none has run yet.
            return "Minimized — not yet captured"
        }
        // Window must be in the visible filter (non-minimized AND
        // large enough) to enter `refreshAppWindowPreviews`.
        if let frame = window.frame {
            let minimumTrackedSide: CGFloat = 100  // mirrors WindowRegistry
            if frame.width < minimumTrackedSide || frame.height < minimumTrackedSide {
                return "Frame below 100×100 — registry skips it"
            }
        }
        if !WindowRegistry.shared.visible.contains(where: { $0.id == window.id }) {
            return "Not in `visible` snapshot (filtered out)"
        }
        return "Capture pending or skipped (refresh hasn't completed yet)"
    }

    func thumbnailImage(for window: AppWindow) -> NSImage? {
        if window.isMinimized {
            return workspace.minimizedWindowPreviews[window.windowIdentifier]
        }
        return workspace.appWindowPreviews[window.windowIdentifier]
    }

    func cachedPreviewKindLabel(for window: AppWindow) -> String {
        if window.isMinimized {
            return workspace.minimizedWindowPreviews[window.windowIdentifier] != nil
                ? "minimized cache" : "—"
        }
        return workspace.appWindowPreviews[window.windowIdentifier] != nil
            ? "app-window cache" : "—"
    }

    /// Looks up the bounds of `window.cgWindowID` via
    /// `CGWindowListCopyWindowInfo`, independently of the SkyLight
    /// snapshot the registry reads. A mismatch means the registry's
    /// frame is stale.
    func cgWindowFrameDescription(for window: AppWindow) -> String {
        guard let rect = cgWindowFrame(for: window) else { return "(not found)" }
        return formatRect(rect)
    }

    func cgWindowFrame(for window: AppWindow) -> CGRect? {
        let descriptions =
            CGWindowListCopyWindowInfo(
                [.optionIncludingWindow],
                window.cgWindowID
            ) as? [[String: Any]] ?? []
        guard let entry = descriptions.first,
            let boundsDict = entry[kCGWindowBounds as String] as? [String: Any]
        else {
            return nil
        }
        return CGRect(
            x: (boundsDict["X"] as? CGFloat) ?? 0,
            y: (boundsDict["Y"] as? CGFloat) ?? 0,
            width: (boundsDict["Width"] as? CGFloat) ?? 0,
            height: (boundsDict["Height"] as? CGFloat) ?? 0
        )
    }

    func formatRect(_ rect: CGRect) -> String {
        "(\(Int(rect.minX)),\(Int(rect.minY))) \(Int(rect.width))×\(Int(rect.height))"
    }

    /// Native pixel dimensions of the cached image when available
    /// (falls back to point size). Helpful for spotting a captured
    /// thumbnail that's actually the menu bar — a long horizontal
    /// strip rather than a window-shaped rectangle.
    /// Builds a paste-friendly, multi-line dump of every diagnostic
    /// field shown in the row (and a few derived flags like the
    /// no-preview reason or the menu-bar-shape warning) and copies
    /// it to the general pasteboard.
    func copyDebugDescription(for window: AppWindow) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(debugDescription(for: window), forType: .string)
    }

    func debugDescription(for window: AppWindow) -> String {
        var lines: [String] = []
        lines.append("App:           \(window.appDisplayName)")
        lines.append("Bundle:        \(window.bundleIdentifier)")
        lines.append("PID:           \(window.processIdentifier)")
        lines.append("Title:         \(window.windowTitle.isEmpty ? "(no title)" : window.windowTitle)")
        lines.append("Identifier:    \(window.windowIdentifier)")
        lines.append("CGWindowID:    \(window.cgWindowID)")
        lines.append("Active Space:  \(window.isOnActiveSpace ? "yes" : "no")")
        lines.append("Frame (WS):    \(window.frame.map(formatRect) ?? "—")")
        lines.append("Frame (CG):    \(cgWindowFrameDescription(for: window))")
        lines.append("Minimized:     \(window.isMinimized ? "yes" : "no")")
        lines.append("Cache:         \(cachedPreviewKindLabel(for: window))")

        if let image = thumbnailImage(for: window) {
            lines.append("Image size:    \(formatImageSize(image))")
            if let warning = captureShapeWarning(image: image, frame: window.frame) {
                lines.append("Warning:       \(warning)")
            }
        } else {
            lines.append("No-preview:    \(noPreviewReason(for: window))")
        }

        lines.append("Permissions:   screen=\(PermissionsService.shared.screenCapture)")

        return lines.joined(separator: "\n")
    }

    func formatImageSize(_ image: NSImage) -> String {
        if let rep = image.representations.first as? NSBitmapImageRep {
            return "\(rep.pixelsWide)×\(rep.pixelsHigh) px"
        }
        let size = image.size
        return "\(Int(size.width))×\(Int(size.height)) pt (no bitmap rep)"
    }

    /// Heuristic check: if the captured image's aspect ratio differs
    /// dramatically from the window's frame, the capture probably
    /// landed on the wrong target — typically the app's menu bar
    /// (very wide / very short) rather than the content window.
    func captureShapeWarning(image: NSImage, frame: CGRect?) -> String? {
        let pixelSize: CGSize
        if let rep = image.representations.first as? NSBitmapImageRep {
            pixelSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        } else {
            pixelSize = image.size
        }
        guard pixelSize.height > 0 else { return "Zero-height capture" }
        let imageRatio = pixelSize.width / pixelSize.height

        // Independent menu-bar shape detection: anything wider than
        // 8:1 is almost certainly a horizontal strip and not a real
        // window. macOS menu-bar windows are typically ~screen-wide
        // by ~24 pt.
        if imageRatio > 8 || pixelSize.height < 60 {
            return "Looks like a menu-bar capture (\(Int(pixelSize.width))×\(Int(pixelSize.height)))"
        }

        guard let frame, frame.height > 0, frame.width > 0 else { return nil }
        let frameRatio = frame.width / frame.height
        // If the captured aspect ratio is more than 3× off the
        // window's, it's a strong signal the capture is the wrong
        // surface.
        let ratio = imageRatio / frameRatio
        if ratio > 3 || ratio < (1.0 / 3.0) {
            let measured = String(format: "%.2f", imageRatio)
            let expected = String(format: "%.2f", frameRatio)
            return "Aspect mismatch (image \(measured) vs frame \(expected))"
        }
        return nil
    }

}
