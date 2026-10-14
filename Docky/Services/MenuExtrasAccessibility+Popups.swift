import ApplicationServices
import Foundation

struct MenuExtraPopupWindow: Sendable {
    let id: CGWindowID
    let ownerPID: pid_t
    let frame: CGRect
}

extension MenuExtrasAccessibility {
    func popupDiagnostics(ownerPIDs: [pid_t]) -> [String] {
        resetPopupDeadline()
        var lines = popupWindows(ownerPIDs: ownerPIDs).map { "CG window \($0.id) pid=\($0.ownerPID) \($0.frame)" }
        for owner in ownerPIDs {
            let app = AXUIElementCreateApplication(owner)
            AXUIElementSetMessagingTimeout(app, 0.15)
            for window in attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
                var settable = DarwinBoolean(false)
                let result = AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &settable)
                lines.append("AX window pid=\(owner) frame=\(String(describing: frame(window))) "
                             + "positionSettable=\(settable.boolValue) result=\(result.rawValue)")
            }
        }
        return lines
    }

    func popupWindows(ownerPIDs: [pid_t]) -> [MenuExtraPopupWindow] {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0)
            as? [[String: Any]] else { return [] }
        return windows.compactMap { window in
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t, ownerPIDs.contains(ownerPID),
                  let identifier = window[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return MenuExtraPopupWindow(id: identifier, ownerPID: ownerPID, frame: rect)
        }
    }

    /// Move only a newly opened, small, AX-settable popup near the original icon.
    /// Existing document windows and visual WindowServer transforms are excluded.
    func relocatePopup(item: MenuExtraSnapshot, ownerPIDs: [pid_t], previous: [MenuExtraPopupWindow],
                       anchor: CGRect, visible: CGRect) async -> String {
        let oldIDs = Set(previous.map(\.id))
        for _ in 0..<8 {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return "Popup experiment canceled" }
            let candidates = popupWindows(ownerPIDs: ownerPIDs).filter {
                !oldIDs.contains($0.id) && $0.frame.width > 40 && $0.frame.width <= visible.width * 2
                    && $0.frame.height > 40 && $0.frame.height <= visible.height * 2
                    && abs($0.frame.minY - item.frame.maxY) < 100
                    && $0.frame.insetBy(dx: -80, dy: 0).contains(CGPoint(x: item.frame.midX, y: $0.frame.midY))
            }
            guard !candidates.isEmpty else { continue }
            return await moveCandidate(candidates, anchor: anchor, visible: visible)
        }
        return popupCapability(ownerPIDs: ownerPIDs, item: item)
            ?? "No movable native popup found; the original menu stays in the menu bar"
    }

    private func popupCapability(ownerPIDs: [pid_t], item: MenuExtraSnapshot) -> String? {
        resetPopupDeadline()
        for owner in ownerPIDs {
            let app = AXUIElementCreateApplication(owner)
            AXUIElementSetMessagingTimeout(app, 0.15)
            for window in attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
                guard let rect = frame(window), rect.width > 40, rect.height > 40,
                      abs(rect.minY - item.frame.maxY) < 100,
                      rect.insetBy(dx: -80, dy: 0).contains(CGPoint(x: item.frame.midX, y: rect.midY)) else { continue }
                var settable = DarwinBoolean(false)
                let result = AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &settable)
                if result != .success || !settable.boolValue {
                    return "Native popup position is read-only; it stays in the menu bar"
                }
                return "Native popup has no independent WindowServer window; placement needs further validation"
            }
        }
        return nil
    }

    private func moveCandidate(_ candidates: [MenuExtraPopupWindow], anchor: CGRect, visible: CGRect) async -> String {
        guard let candidate = candidates.first else { return "No popup found" }
        resetPopupDeadline()
        let app = AXUIElementCreateApplication(candidate.ownerPID)
        AXUIElementSetMessagingTimeout(app, 0.15)
        let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        for window in windows {
            guard let original = frame(window), abs(original.minX - candidate.frame.minX) < 4,
                  abs(original.minY - candidate.frame.minY) < 4,
                  abs(original.width - candidate.frame.width) < 4,
                  abs(original.height - candidate.frame.height) < 4 else { continue }
            var settable = DarwinBoolean(false)
            guard AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &settable) == .success,
                  settable.boolValue else { return "Native popup position is read-only; it stays in the menu bar" }
            let content = readableBounds(of: window, container: original) ?? original
            guard content.width <= visible.width, content.height <= visible.height else {
                return "The native popup is too large to fit above the taskbar"
            }
            var origin = MenuExtraGeometry.windowOrigin(container: original, content: content,
                                                       anchor: anchor, visible: visible)
            guard let value = AXValueCreate(.cgPoint, &origin) else { continue }
            var accepted = false
            defer {
                if !accepted {
                    var previousOrigin = original.origin
                    if let restore = AXValueCreate(.cgPoint, &previousOrigin) {
                        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, restore)
                    }
                }
            }
            let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return "Popup experiment canceled" }
            resetPopupDeadline()
            let physical = popupWindows(ownerPIDs: [candidate.ownerPID]).first { $0.id == candidate.id }?.frame
            guard result == .success, let moved = frame(window),
                  abs(moved.minX - origin.x) < 4, abs(moved.minY - origin.y) < 4,
                  let physical, abs(physical.minX - origin.x) < 4, abs(physical.minY - origin.y) < 4 else {
                return "Native host rejected popup placement (AX \(result.rawValue))"
            }
            accepted = true
            return "Moved the original native popup above the taskbar"
        }
        return "Native popup has no matching Accessibility window; it stays in the menu bar"
    }

    /// Control Center's window includes a large transparent backdrop. Place its
    /// actual controls above the dock while keeping the original window and input handling.
    private func readableBounds(of window: AXUIElement, container: CGRect) -> CGRect? {
        resetPopupDeadline()
        var pending = children(window).map { ($0, 0) }
        var bounds: CGRect?
        var visited = 0
        while let (element, depth) = pending.popLast(), visited < 160 {
            visited += 1
            let role = string(element, kAXRoleAttribute)
            let descendants = children(element)
            if depth < 5 { pending += descendants.map { ($0, depth + 1) } }
            guard role != kAXGroupRole, role != kAXWindowRole,
                  let rect = frame(element), rect.width > 0, rect.height > 0, container.contains(rect) else { continue }
            bounds = bounds.map { $0.union(rect) } ?? rect
        }
        guard let bounds, !bounds.isEmpty else { return nil }
        return bounds.insetBy(dx: -12, dy: -12).intersection(container)
    }
}
