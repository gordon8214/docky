#if DEBUG
import AppKit
import Darwin

@MainActor
enum DockBridgeRegression {
    static func run() async {
        let started = ContinuousClock.now
        let visibility = SystemDockVisibilityService.shared
        guard !visibility.hasSnapshot else { fatalError("Quit the running Docky before testing its Dock bridge") }
        let previousDockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier
        visibility.hide()
        do {
            let dockPID = try await waitForDock(excluding: previousDockPID)
            let tilingProbe = try await DockTilingProbe.start()
            defer { tilingProbe.cleanup() }
            guard let screen = NSScreen.screens.first,
                  let display = NativeDockIntegration.displayID(screen) else { throw failure("No display") }
            let base = NativeDockIntegration.unreservedFrame(screen)
            let chrome = CGRect(x: base.midX - 200, y: base.minY, width: 400, height: 70)
            let strip = DockSystemGeometry.strip(screen: base, chrome: chrome, edge: .bottom)
            let quartz = DockSystemGeometry.quartz(strip, primaryMaxY: screen.frame.maxY)
            try checkDirectProbe(quartz: quartz)
            try await DockBridgeLoader.load(into: dockPID)
            let request = DockBridgeRequest(
                session: visibility.sessionIdentity, revision: 1, display: display,
                rect: [quartz.minX, quartz.minY, quartz.width, quartz.height], reason: 0, orientation: 2)
            let deadline = ContinuousClock.now + .seconds(3)
            while true {
                do {
                    let response = try await DockBridgeTransport.shared.send(request, dockPID: dockPID)
                    print(response.backendDetails ?? "No bridge details")
                    break
                } catch {
                    print("Bridge connection attempt: \(error.localizedDescription)")
                    fflush(stdout)
                    if !error.localizedDescription.contains("not connected") { throw error }
                    guard ContinuousClock.now < deadline else { throw error }
                    try await Task.sleep(for: .milliseconds(100))
                }
            }
            try await checkStaleRequests(request, dockPID: dockPID)
            try await verifyPersistentReservation(display: display, base: base, strip: strip, quartz: quartz)
            try await tilingProbe.verifyAfterPublication()
            print("Dock bridge authenticated IPC, stale-session rejection, and persistent reservation passed")
            try await verifyHelperFailureRelease(display: display, base: base)
            visibility.restore()
            _ = try await waitForDock(excluding: dockPID)
            print("Dock bridge cleanup passed in \(started.duration(to: .now))")
            exit(0)
        } catch {
            visibility.restore()
            fatalError("Dock bridge regression failed: \(error.localizedDescription)")
        }
    }

    private static func checkStaleRequests(_ request: DockBridgeRequest, dockPID: pid_t) async throws {
        try await reject(request, dockPID: dockPID, expected: "Stale revision")
        let wrongSession = DockBridgeRequest(
            session: "stale-session", revision: 2, display: request.display,
            rect: request.rect, reason: 0, orientation: 2)
        try await reject(wrongSession, dockPID: dockPID, expected: "Invalid owner/session")
    }

    private static func checkDirectProbe(quartz: CGRect) throws {
        let probe = NativeDockIntegration.Reservation(rect: quartz, reason: 0, orientation: 2)
        guard let original = NativeDockIntegration.readReservation() else { throw failure("No snapshot") }
        try WindowReservationService.probeDirectPublication(probe)
        guard NativeDockIntegration.readReservation() == original else { throw failure("Probe was not restored") }
    }

    static func runCrashFixture() async {
        let visibility = SystemDockVisibilityService.shared
        guard !visibility.hasSnapshot else { fatalError("Quit Docky before running its lifecycle fixture") }
        let previous = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier
        visibility.hide()
        do {
            _ = try await waitForDock(excluding: previous)
            guard let screen = NSScreen.screens.first else { throw failure("No display") }
            WindowReservationService.shared.start()
            let base = NativeDockIntegration.unreservedFrame(screen)
            WindowReservationService.shared.update(
                screen: screen, chrome: CGRect(x: base.midX - 200, y: base.minY, width: 400, height: 70),
                edge: .bottom, reserves: true)
            let deadline = ContinuousClock.now + .seconds(5)
            while !WindowReservationService.shared.backendStatus.contains("verified") {
                if let error = WindowReservationService.shared.lastError { throw failure(error) }
                guard ContinuousClock.now < deadline else { throw failure("Reservation did not become ready") }
                try await Task.sleep(for: .milliseconds(100))
            }
            print("Dock bridge crash fixture ready")
            fflush(stdout)
            // Stay in AppKit's event loop. The lifecycle script will restart
            // Apple Dock, then SIGKILL this process to exercise both recoveries.
        } catch {
            WindowReservationService.shared.stop()
            visibility.restore()
            fatalError("Dock bridge fixture failed: \(error.localizedDescription)")
        }
    }

    private static func verifyHelperFailureRelease(display: UInt32, base: CGRect) async throws {
        SystemDockVisibilityService.shared.setReservationOwnership(active: false)
        let releaseDeadline = ContinuousClock.now + .seconds(2)
        while NativeDockIntegration.readReservation()?.reason == 0 {
            guard ContinuousClock.now < releaseDeadline else {
                throw failure("Bridge lease did not release ownership")
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        let released = try await WindowReservationService.shared.externalVisibleFrames()
        guard released[String(display)] == base else { throw failure("Helper failure left a desktop reservation") }
        print("Helper-failure ownership release passed while Docky remained running")
    }

    private static func verifyPersistentReservation(display: UInt32, base: CGRect, strip: CGRect,
                                                    quartz: CGRect) async throws {
        // Launching an AppKit process updates Apple's Dock layout. This
        // must neither overwrite the reservation nor leave a stale cache.
        for _ in 0..<3 {
            let frames = try await WindowReservationService.shared.externalVisibleFrames()
            let expected = DockSystemGeometry.usableFrame(screen: base, strip: strip, edge: .bottom)
            guard frames[String(display)] == expected else {
                throw failure("Independent AppKit readback mismatch: "
                    + "expected \(expected); actual \(frames); "
                + "SkyLight \(String(describing: NativeDockIntegration.readReservation()))")
            }
            try await Task.sleep(for: .milliseconds(200))
            guard NativeDockIntegration.readReservation()?.rect == quartz else {
                throw failure("Apple Dock overwrote its intercepted reservation")
            }
        }
    }

    private static func reject(_ request: DockBridgeRequest, dockPID: pid_t, expected: String) async throws {
        do {
            _ = try await DockBridgeTransport.shared.send(request, dockPID: dockPID)
        } catch {
            guard error.localizedDescription.contains(expected) else { throw error }
            return
        }
        throw failure("Invalid bridge request was accepted")
    }

    static func waitForDock(excluding excluded: pid_t? = nil) async throws -> pid_t {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
               dock.isFinishedLaunching, dock.processIdentifier != excluded { return dock.processIdentifier }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw failure("Apple Dock did not finish restarting within five seconds")
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "DockBridgeRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
#endif
