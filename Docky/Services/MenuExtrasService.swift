import AppKit
import ApplicationServices
import Observation

struct MenuExtra: Identifiable {
    let snapshot: MenuExtraSnapshot
    let image: NSImage
    var id: String { snapshot.id }
}

@MainActor
@Observable
final class MenuExtrasService {
    static let shared = MenuExtrasService()
    private(set) var items: [MenuExtra] = []
    private(set) var message = "Loading menu extras"
    private(set) var lastActivation = ""
    @ObservationIgnored let backend = MenuExtrasAccessibility()
    @ObservationIgnored private let captureSession = MenuExtrasLiveCapture()
    @ObservationIgnored private var owners = Set<UUID>()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var activationTask: Task<Void, Never>?
    @ObservationIgnored private var activationIdentity: UUID?
    @ObservationIgnored private var generation = UUID()

    func attach(_ owner: UUID) {
        guard owners.insert(owner).inserted, owners.count == 1,
              !ProcessInfo.processInfo.arguments.contains("--appkit-ui-regression") else { return }
        let identity = UUID()
        generation = identity
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == identity else { return }
                await self.refresh(identity: identity)
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
            }
        }
    }

    func detach(_ owner: UUID) {
        owners.remove(owner)
        guard owners.isEmpty else { return }
        let previous = generation
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        activationTask?.cancel()
        activationTask = nil
        activationIdentity = nil
        items.removeAll()
        captureSession.stop()
        Task { await backend.clear(session: previous) }
    }

    private func refresh(identity: UUID) async {
        guard AXIsProcessTrusted(), CGPreflightScreenCaptureAccess() else {
            captureSession.stop()
            items = []
            let missing = [AXIsProcessTrusted() ? nil : "Accessibility",
                           CGPreflightScreenCaptureAccess() ? nil : "Screen Recording"].compactMap { $0 }
            message = "Menu extras require " + missing.joined(separator: " and ")
            return
        }
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent")
            .first else {
            items = []
            message = "The macOS menu bar is unavailable"
            return
        }
        let displays = NSScreen.screens.compactMap { screen -> MenuExtraDisplay? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            let identifier = number.uint32Value
            return MenuExtraDisplay(id: identifier, frame: CGDisplayBounds(identifier))
        }
        var snapshots = await backend.snapshot(agentPID: agent.processIdentifier, displays: displays, session: identity)
        guard generation == identity, !Task.isCancelled else { return }
        var captured: [MenuExtra] = []
        for display in displays {
            let extras = snapshots.filter { $0.displayID == display.id }
            captured += await capture(extras)
        }
        let settled = await backend.snapshot(agentPID: agent.processIdentifier, displays: displays, session: identity)
        guard generation == identity, !Task.isCancelled else { return }
        if settled.map(\.frame) != snapshots.map(\.frame) || settled.map(\.id) != snapshots.map(\.id) {
            // Starting capture adds the system recording indicator and can reflow the bar.
            // Reuse the continuing stream with the settled geometry before publishing icons.
            snapshots = settled
            captured.removeAll()
            for display in displays {
                captured += await capture(snapshots.filter { $0.displayID == display.id })
            }
        }
        guard generation == identity, !Task.isCancelled else { return }
        items = captured
        message = items.isEmpty ? "No visible menu extras" : "macOS menu extras"
    }

    private func capture(_ extras: [MenuExtraSnapshot]) async -> [MenuExtra] {
        guard let first = extras.first else { return [] }
        let region = extras.dropFirst().reduce(first.frame) { $0.union($1.frame) }
        do {
            let image = try await captureSession.image(in: region, displayID: first.displayID)
            let pixels = CGSize(width: image.width, height: image.height)
            return extras.compactMap { extra in
                guard let crop = MenuExtraGeometry.crop(frame: extra.frame, region: region, pixels: pixels),
                      let icon = image.cropping(to: crop) else { return nil }
                return MenuExtra(snapshot: extra, image: MenuExtraImage.make(icon, size: extra.frame.size))
            }
        } catch {
            NSLog("Menu extras capture failed: %@", error.localizedDescription)
            let identifiers = Set(extras.map(\.id))
            return items.filter { identifiers.contains($0.id) }
        }
    }

    func activate(_ item: MenuExtraSnapshot, anchor: CGRect, visible: CGRect, relocate: Bool = false) {
        guard activationTask == nil else { return }
        let identity = generation
        let request = UUID()
        activationIdentity = request
        var popupOwners = [item.ownerPID]
        if item.id.contains("com.apple.menuextra.") {
            popupOwners += ["com.apple.controlcenter", "com.apple.systemuiserver"].flatMap { identifier in
                NSRunningApplication.runningApplications(withBundleIdentifier: identifier).map(\.processIdentifier)
            }
        }
        let owners = popupOwners
        activationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.activationIdentity == request {
                    self.activationTask = nil
                    self.activationIdentity = nil
                }
            }
            let before = relocate ? await self.backend.popupWindows(ownerPIDs: owners) : []
            guard self.generation == identity, !Task.isCancelled else { return }
            let result = await self.backend.press(item: item)
            guard self.generation == identity, !Task.isCancelled else { return }
            if result != AXError.success.rawValue {
                self.lastActivation = "The menu extra could not be activated (AX \(result))"
                NSLog("Menu extras: %@", self.lastActivation)
                return
            }
            self.lastActivation = "Activated \(item.label) at its original menu bar icon"
            if relocate {
                self.lastActivation = await self.backend.relocatePopup(
                    item: item, ownerPIDs: owners, previous: before, anchor: anchor, visible: visible)
            }
            NSLog("Menu extras: %@", self.lastActivation)
        }
    }
}
