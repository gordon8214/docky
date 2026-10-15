import AppKit
import ApplicationServices
import Observation

struct MenuExtra: Identifiable {
    let snapshot: MenuExtraSnapshot
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
    @ObservationIgnored private var owners = Set<UUID>()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var activationTask: Task<Void, Never>?
    @ObservationIgnored private var activationIdentity: UUID?
    @ObservationIgnored private var generation = UUID()

    func attach(_ owner: UUID) {
        guard owners.insert(owner).inserted, owners.count == 1,
              !ProcessInfo.processInfo.arguments.contains("--appkit-ui-regression") else { return }
        updateEnabledState()
    }

    func detach(_ owner: UUID) {
        owners.remove(owner)
        if owners.isEmpty { stop() }
    }

    func updateEnabledState() {
        stop()
        guard MenuExtrasNativeBridge.shared.enabled, !owners.isEmpty,
              !ProcessInfo.processInfo.arguments.contains("--appkit-ui-regression") else {
            message = "Menu extras are off"
            return
        }
        message = "Loading native menu extras"
        let identity = generation
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == identity else { return }
                await self.refresh(identity: identity)
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
            }
        }
    }

    private func stop() {
        let previous = generation
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        activationTask?.cancel()
        activationTask = nil
        activationIdentity = nil
        items.removeAll()
        Task { await backend.clear(session: previous) }
    }

    private func refresh(identity: UUID) async {
        guard MenuExtrasNativeBridge.shared.enabled else { return }
        guard AXIsProcessTrusted() else {
            items = []
            message = "Menu extras require Accessibility access"
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
        snapshots = retainingNativeItems(in: snapshots, agentPID: agent.processIdentifier, displays: displays)
        guard generation == identity, !Task.isCancelled else { return }
        items = snapshots.map { MenuExtra(snapshot: $0) }
        message = items.isEmpty ? "No visible menu extras" : "Native macOS menu extras"
    }

    private func retainingNativeItems(in snapshots: [MenuExtraSnapshot], agentPID: pid_t,
                                      displays: [MenuExtraDisplay]) -> [MenuExtraSnapshot] {
        let found = Set(snapshots.map(\.id))
        let retained = items.map(\.snapshot).filter { extra in
            MenuExtrasNativeBridge.shared.hostedIDs.contains(extra.id) && !found.contains(extra.id)
                && !snapshots.contains(where: {
                    $0.ownerPID == extra.ownerPID && $0.displayID == extra.displayID
                        && abs($0.frame.midX - extra.frame.midX) < 2 && abs($0.frame.midY - extra.frame.midY) < 2
                })
                && displays.contains(where: { $0.id == extra.displayID })
                && (!extra.id.contains("com.apple.menuextra.") || extra.ownerPID == agentPID)
        }
        return (snapshots + retained).sorted { $0.frame.minX < $1.frame.minX }
    }

    func activate(_ item: MenuExtraSnapshot) {
        guard MenuExtrasNativeBridge.shared.enabled,
              MenuExtrasNativeBridge.shared.hostedIDs.contains(item.id), activationTask == nil else { return }
        let identity = generation
        let request = UUID()
        activationIdentity = request
        activationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.activationIdentity == request {
                    self.activationTask = nil
                    self.activationIdentity = nil
                }
            }
            let result = await self.backend.press(item: item)
            guard self.generation == identity, !Task.isCancelled else { return }
            if result != AXError.success.rawValue {
                self.lastActivation = "The menu extra could not be activated (AX \(result))"
                return
            }
            self.lastActivation = "Opened \(item.label)"
        }
    }
}
