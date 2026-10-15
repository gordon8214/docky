import AppKit
import ApplicationServices

struct MenuExtraSnapshot: Identifiable, Sendable {
    let id: String
    let label: String
    let ownerPID: pid_t
    let frame: CGRect
    let displayID: CGDirectDisplayID
}

struct MenuExtraDisplay: Sendable {
    let id: CGDirectDisplayID
    let frame: CGRect
}

/// AX references stay on this actor. Busy menu-extra owners cannot block AppKit's run loop.
actor MenuExtrasAccessibility {
    private var elements: [String: AXUIElement] = [:]
    private var groups: [String: AXUIElement] = [:]
    private var deadline = ContinuousClock.now
    private var session: UUID?

    func snapshot(agentPID: pid_t, displays: [MenuExtraDisplay], session: UUID = UUID()) -> [MenuExtraSnapshot] {
        self.session = session
        deadline = .now + .seconds(2)
        let agent = AXUIElementCreateApplication(agentPID)
        AXUIElementSetMessagingTimeout(agent, 0.15)
        var found: [MenuExtraSnapshot] = []
        var nextElements: [String: AXUIElement] = [:]
        var nextGroups: [String: AXUIElement] = [:]
        for window in children(agent) {
            for group in children(window) {
                guard ContinuousClock.now < deadline, let rect = frame(group),
                      let display = displays.first(where: { MenuExtraGeometry.visibleItem(rect, on: $0.frame) }),
                      let target = target(in: group, frame: rect) else { continue }
                var ownerPID: pid_t = 0
                AXUIElementGetPid(target, &ownerPID)
                let identifier = string(target, kAXIdentifierAttribute)
                let title = string(target, kAXDescriptionAttribute) ?? string(target, kAXTitleAttribute)
                let label = title ?? identifier ?? NSRunningApplication(processIdentifier: ownerPID)?.localizedName
                    ?? "Menu extra"
                // Agent navigation and rendering windows expose the same item more than once.
                guard !found.contains(where: {
                    $0.ownerPID == ownerPID && $0.displayID == display.id
                        && abs($0.frame.midX - rect.midX) < 2 && abs($0.frame.midY - rect.midY) < 2
                }) else { continue }
                let base = "\(display.id):\(ownerPID):\(identifier ?? title ?? "item")"
                let occurrence = found.filter { $0.id.hasPrefix(base + ":") }.count
                let id = "\(base):\(occurrence)"
                nextElements[id] = target
                nextGroups[id] = group
                found.append(MenuExtraSnapshot(id: id, label: label, ownerPID: ownerPID,
                                               frame: rect, displayID: display.id))
            }
        }
        elements = nextElements
        groups = nextGroups
        return found.sorted { $0.frame.minX < $1.frame.minX }
    }

    private func target(in group: AXUIElement, frame groupFrame: CGRect) -> AXUIElement? {
        for child in children(group) {
            AXUIElementSetMessagingTimeout(child, 0.15)
            let role = string(child, kAXRoleAttribute)
            if role == kAXApplicationRole,
               let bar = element(attribute(child, kAXExtrasMenuBarAttribute)),
               !children(bar).isEmpty {
                let items = children(bar)
                if items.count == 1 { return items.first }
                if let match = items.first(where: {
                    guard let itemFrame = frame($0) else { return false }
                    return abs(itemFrame.midX - groupFrame.midX) < 2
                        && abs(itemFrame.midY - groupFrame.midY) < 4
                }) { return match }
            }
            if role == kAXMenuBarItemRole || role == kAXButtonRole { return child }
            if let leaf = children(child).first(where: { string($0, kAXRoleAttribute) == kAXMenuBarItemRole }) {
                return leaf
            }
        }
        // Custom status views can have no button role but still support an AX press.
        return children(group).first { child in
            var actions: CFArray?
            AXUIElementCopyActionNames(child, &actions)
            return (actions as? [String])?.contains(kAXPressAction) == true
        }
    }

    func press(item: MenuExtraSnapshot) async -> Int32 {
        guard !Task.isCancelled else { return AXError.invalidUIElement.rawValue }
        guard let target = elements[item.id], let group = groups[item.id] else {
            return AXError.invalidUIElement.rawValue
        }
        deadline = .now + .seconds(1)
        guard let rect = frame(group), MenuExtraGeometry.visibleItem(rect, on: CGDisplayBounds(item.displayID))
        else { return AXError.invalidUIElement.rawValue }
        // Third-party hosted AppKit menus can reject AXPress with cannotComplete.
        // Their MenuBarAgent group is the authoritative physical click target.
        AXUIElementSetMessagingTimeout(target, 0.3)
        let result = item.id.contains("com.apple.menuextra.")
            ? AXUIElementPerformAction(target, kAXPressAction as CFString) : AXError.actionUnsupported
        if result == .success { return result.rawValue }
        // Custom views and owners with multiple extras have ambiguous AX buttons.
        // Only the corresponding agent group supplies their physical hit-test frame.
        deadline = .now + .seconds(1)
        guard result == .actionUnsupported || result == .notImplemented else { return result.rawValue }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard physicalOwnerMatches(at: center, ownerPID: item.ownerPID, group: group) else {
            return AXError.invalidUIElement.rawValue
        }
        guard !Task.isCancelled else { return AXError.invalidUIElement.rawValue }
        guard CGPreflightPostEventAccess() else { return AXError.apiDisabled.rawValue }
        return await postPhysicalClick(at: center)
    }

    private func postPhysicalClick(at center: CGPoint) async -> Int32 {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                                 mouseCursorPosition: center, mouseButton: .left),
              let release = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                               mouseCursorPosition: center, mouseButton: .left) else {
            return AXError.cannotComplete.rawValue
        }
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        release.setIntegerValueField(.mouseEventClickState, value: 1)
        down.flags = []
        release.flags = []
        let previousPosition = CGEvent(source: nil)?.location
        defer {
            release.post(tap: .cghidEventTap)
            if let previousPosition, let current = CGEvent(source: nil)?.location,
               abs(current.x - center.x) < 2, abs(current.y - center.y) < 2 {
                CGWarpMouseCursorPosition(previousPosition)
            }
        }
        down.post(tap: .cghidEventTap)
        // Give the hosted item's event handler time to enter menu tracking before release.
        do { try await Task.sleep(for: .milliseconds(60)) } catch { return AXError.cannotComplete.rawValue }
        return AXError.success.rawValue
    }

    private func physicalOwnerMatches(at point: CGPoint, ownerPID: pid_t, group: AXUIElement) -> Bool {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit)
            == .success, let hit else { return false }
        var hitPID: pid_t = 0
        var groupPID: pid_t = 0
        AXUIElementGetPid(hit, &hitPID)
        AXUIElementGetPid(group, &groupPID)
        // Hosted AXPress can time out without opening a menu. Validate the owner,
        // then use one physical down/up pair instead of issuing two activations.
        return hitPID == ownerPID || hitPID == groupPID
    }

    func clear(session: UUID) {
        guard self.session == session else { return }
        elements.removeAll()
        groups.removeAll()
        self.session = nil
    }

    func resetPopupDeadline() { deadline = .now + .seconds(1) }

    func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        guard ContinuousClock.now < deadline else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    func string(_ element: AXUIElement, _ name: String) -> String? {
        guard let value = attribute(element, name) as? String, !value.isEmpty else { return nil }
        return value
    }

    func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute),
              let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        let pointValue = unsafeDowncast(position, to: AXValue.self)
        let sizeValue = unsafeDowncast(size, to: AXValue.self)
        guard AXValueGetType(pointValue) == .cgPoint, AXValueGetType(sizeValue) == .cgSize else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(pointValue, .cgPoint, &point), AXValueGetValue(sizeValue, .cgSize, &dimensions)
        else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
}
