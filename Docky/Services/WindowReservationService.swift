import AppKit
import Combine
import Foundation
import Observation

/// Publishes usable desktop geometry to WindowServer. Never resizes another
/// application's windows. A separate AppKit process confirms visibleFrame.
@MainActor
@Observable
final class WindowReservationService {
    static let shared = WindowReservationService()
    private(set) var backendStatus = "Not started"
    private(set) var lastError: String?
    private(set) var backendDetails: String?
    private var started = false
    private var timer: Timer?
    private var wanted: NativeDockIntegration.Reservation?
    private var expectedVisibleFrame: CGRect?
    private var expectedDisplay: CGDirectDisplayID?
    private var verification: Task<Void, Never>?
    private var generation = 0
    private var injectedDockPID: pid_t?
    private var attemptedDockPID: pid_t?
    private var subscriptions = Set<AnyCancellable>()

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        // Also detects Dock relaunch and compositor transitions that do not
        // produce an AX resize or an application activation notification.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reconcile() }
            .store(in: &subscriptions)
    }

    func update(screen: NSScreen, chrome: CGRect, edge: ResolvedDockWindowPosition, reserves: Bool) {
        guard started, SystemDockVisibilityService.shared.ownsSession, let primary = NSScreen.screens.first,
              let display = NativeDockIntegration.displayID(screen) else { return }
        let base = NativeDockIntegration.unreservedFrame(screen)
        let strip = reserves ? DockSystemGeometry.strip(screen: base, chrome: chrome, edge: edge) : .zero
        let next = NativeDockIntegration.Reservation(
            rect: reserves ? DockSystemGeometry.quartz(strip, primaryMaxY: primary.frame.maxY) : .zero,
            reason: reserves ? 0 : 2, orientation: DockSystemGeometry.orientation(edge))
        let visible = reserves ? DockSystemGeometry.usableFrame(screen: base, strip: strip, edge: edge) : base
        guard wanted != next || expectedDisplay != display || expectedVisibleFrame != visible else { return }
        wanted = next
        expectedDisplay = display
        expectedVisibleFrame = visible
        publishAndVerify()
    }

    func stop() {
        started = false
        timer?.invalidate()
        timer = nil
        verification?.cancel()
        DockBridgeLoader.cancelPendingLoad()
        subscriptions.removeAll()
        SystemDockVisibilityService.shared.setReservationOwnership(active: false)
        if let wanted {
            _ = NativeDockIntegration.publish(.init(rect: .zero, reason: 2, orientation: wanted.orientation))
        }
        wanted = nil
        backendStatus = "Stopped"
    }

    private func reconcile() {
        guard started else { return }
        guard SystemDockVisibilityService.shared.ownsSession else {
            verification?.cancel()
            wanted = nil
            backendStatus = "Reservation ownership released"
            return
        }
        let window = NSApp.windows.compactMap { $0 as? MainWindow }.first
        window?.refreshSystemIntegration()
        let currentDockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier
        guard let wanted else { return }
        // A failed probe releases the Dock-side lease. Do not immediately
        // reclaim it in this polling loop; retry on a new Dock or explicit
        // request, or when the requested layout changes.
        if currentDockPID == attemptedDockPID, lastError != nil { return }
        if currentDockPID != injectedDockPID {
            if currentDockPID != attemptedDockPID { lastError = nil }
            guard verification == nil, lastError == nil else { return }
            publishAndVerify()
        } else if NativeDockIntegration.readReservation() != wanted {
            publishAndVerify()
        }

    }

    func retryIntegration() {
        DockBridgeLoader.resetFailure()
        injectedDockPID = nil
        publishAndVerify()
    }

    private func publishAndVerify() {
        guard let wanted, let display = expectedDisplay else { return }
        generation += 1
        let currentGeneration = generation
        verification?.cancel()
        SystemDockVisibilityService.shared.setReservationOwnership(active: true)
        // Probe the direct API before installing the Dock-side publisher.
        // On current macOS, direct geometry can be read by new clients, but
        // Dock overwrites it and only Dock-origin notifications update old
        // clients. Its WindowManager tiling cache also needs the bridge.
        if injectedDockPID == nil {
            do { try Self.probeDirectPublication(wanted) } catch {
                fail(error.localizedDescription)
                return
            }
        }
        backendStatus = "Connecting Dock-side publisher"
        let request = DockBridgeRequest(
            session: SystemDockVisibilityService.shared.sessionIdentity, revision: UInt64(currentGeneration),
            display: display, rect: [wanted.rect.minX, wanted.rect.minY, wanted.rect.width, wanted.rect.height],
            reason: wanted.reason, orientation: wanted.orientation)
        verification = Task { [weak self] in
            guard let self else { return }
            do { try await self.connectAndVerify(request, wanted: wanted, generation: currentGeneration) } catch {
                guard !Task.isCancelled, currentGeneration == self.generation else { return }
                if error.localizedDescription.contains("restarting")
                    || error.localizedDescription.contains("changed during bridge initialization") {
                    // Workspace may briefly report the old Dock while the
                    // loader sees its replacement. This is a restart race,
                    // not a rejected debugger authorization.
                    self.attemptedDockPID = nil
                    self.injectedDockPID = nil
                    DockBridgeLoader.resetFailure()
                }
                self.fail(error.localizedDescription)
            }
        }
    }

    private func connectAndVerify(_ request: DockBridgeRequest, wanted: NativeDockIntegration.Reservation,
                                  generation currentGeneration: Int) async throws {
        let display = request.display
        guard let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first(where: { $0.isFinishedLaunching && !$0.isTerminated })?.processIdentifier else {
            throw self.integrationError("Apple's Dock is restarting")
        }
        self.attemptedDockPID = dockPID
        try await DockBridgeLoader.load(into: dockPID)
        try Task.checkCancellation()
        try await sendToBridge(request, dockPID: dockPID)
        guard !Task.isCancelled, currentGeneration == self.generation else { return }
        guard NativeDockIntegration.readReservation() == wanted else {
            throw self.integrationError("Dock-side SkyLight readback mismatch")
        }
        self.injectedDockPID = dockPID
        let frames = try await self.externalVisibleFrames()
        guard !Task.isCancelled, currentGeneration == self.generation else { return }
        guard let expected = self.expectedVisibleFrame,
              let actual = frames[String(display)], self.matches(actual, expected) else {
            throw self.integrationError("Independent AppKit visibleFrame mismatch: "
                + "expected \(String(describing: self.expectedVisibleFrame)); actual \(frames)")
        }
        self.backendStatus = "Dock-side publisher; independent AppKit readback verified"
        self.lastError = nil
        self.verification = nil
        #if DEBUG
        NSLog("[Docky] Native Dock reservation verified: \(expected)")
        #endif
    }

    private func sendToBridge(_ request: DockBridgeRequest, dockPID: pid_t) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while true {
            try Task.checkCancellation()
            do {
                let response = try await DockBridgeTransport.shared.send(request, dockPID: dockPID)
                backendDetails = response.backendDetails
                break
            } catch {
                guard error.localizedDescription.contains("not connected"),
                      ContinuousClock.now < deadline else { throw error }
                try await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func integrationError(_ message: String) -> NSError {
        NSError(domain: "DockyReservation", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func probeDirectPublication(_ reservation: NativeDockIntegration.Reservation) throws {
        guard let original = NativeDockIntegration.readReservation() else {
            throw NSError(domain: "DockyReservation", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not snapshot Apple's Dock reservation"])
        }
        // Restore before any suspension or injection. The payload must capture
        // Apple's geometry, and denied loader authorization must leave no probe.
        let publication = NativeDockIntegration.publish(reservation)
        let readback = NativeDockIntegration.readReservation()
        let restoration = NativeDockIntegration.publish(original)
        guard restoration == 0, NativeDockIntegration.readReservation() == original else {
            throw NSError(domain: "DockyReservation", code: Int(restoration),
                          userInfo: [NSLocalizedDescriptionKey: "Could not restore the direct reservation probe"])
        }
        // A rejected direct publication still permits the authorized Dock-side
        // backend. Record the probe result without accepting it as verification.
        if publication != 0 || readback != reservation {
            NSLog("[Docky] Direct reservation probe rejected; trying Dock-side publisher")
        }
    }

    private func fail(_ message: String) {
        verification = nil
        // The Dock-side lease observes this independently, even when its IPC
        // channel has failed. Keep the watchdog's preference snapshot intact.
        SystemDockVisibilityService.shared.setReservationOwnership(active: false)
        backendStatus = "Reservation unavailable"
        if lastError != message { NSLog("[Docky] \(message)") }
        lastError = message
    }

    private func matches(_ actual: CGRect, _ expected: CGRect) -> Bool {
        abs(actual.minX - expected.minX) < 1 && abs(actual.minY - expected.minY) < 1
            && abs(actual.width - expected.width) < 1 && abs(actual.height - expected.height) < 1
    }

    func externalVisibleFrames() async throws -> [String: CGRect] {
        let executable = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems")
            .appendingPathComponent("DockyDockWatchdog.app/Contents/MacOS/DockyDockWatchdog")
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--visible-frame-probe"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        let deadline = ContinuousClock.now + .seconds(5)
        while process.isRunning {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else {
                throw NSError(domain: "DockyReservation", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "AppKit probe exceeded its five-second budget"])
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard process.terminationStatus == 0,
              let frames = try JSONSerialization.jsonObject(with: output.fileHandleForReading.readDataToEndOfFile())
                as? [String: String] else {
            throw NSError(domain: "DockyReservation", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "AppKit probe returned invalid output"])
        }
        return frames.mapValues { NSRectFromString($0) }
    }
}
