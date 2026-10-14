#if DEBUG
import AppKit
import Darwin

@MainActor
enum DockSystemRegression {
    static func run() async {
        let started = ContinuousClock.now
        guard let screen = NSScreen.screens.first,
              let original = NativeDockIntegration.readReservation() else {
            fatalError("A live WindowServer connection is required")
        }
        defer { _ = NativeDockIntegration.publish(original) }
        checkClassification()
        checkCoordinates()
        checkReservedDisplaySelection()
        checkSocketBudget()
        checkPreferenceMigration()
        do {
            try await checkVisibility()
            try await checkDirectProbeRollback(screen: screen)
            try await checkNativeReservation(screen: screen)
            try await checkLiveFullscreen(screen: screen)
        } catch {
            _ = NativeDockIntegration.publish(original)
            fatalError("Native reservation regression failed: \(error)")
        }
        _ = NativeDockIntegration.publish(original)
        print("Dock system regressions passed in \(started.duration(to: .now))")
        fflush(stdout)
        exit(0)
    }

    private static func checkClassification() {
        let identifier = "display-one"
        for type in [0, 2, 4] {
            let displays: [[String: Any]] = [
                ["Display Identifier": "display-two", "Current Space": ["type": 4]],
                ["Display Identifier": identifier, "Current Space": ["type": type]]
            ]
            precondition(DockSystemGeometry.fullscreen(
                displayID: identifier, separateSpaces: true, displays: displays) == (type == 4))
        }
        precondition(DockSystemGeometry.fullscreen(displayID: identifier, separateSpaces: true, displays: []) == nil)
        precondition(DockSystemGeometry.fullscreen(
            displayID: identifier, separateSpaces: false,
            displays: [["Display Identifier": "Main", "Current Space": ["type": 4]]]) == true)
    }

    private static func checkCoordinates() {
        let screen = CGRect(x: -1440, y: -900, width: 1440, height: 900)
        let chrome = CGRect(x: -1440, y: -860, width: 64, height: 700)
        let strip = DockSystemGeometry.strip(screen: screen, chrome: chrome, edge: .left)
        precondition(strip == CGRect(x: -1440, y: -900, width: 64, height: 900))
        let converted = DockSystemGeometry.quartz(strip, primaryMaxY: 967)
        precondition(converted.minY == 967)
        precondition(DockSystemGeometry.quartz(converted, primaryMaxY: 967) == strip)
        let fractional = NativeDockIntegration.Reservation(rect: CGRect(x: 0, y: 0, width: 63.7, height: 900),
                                                         reason: 0, orientation: 3)
        precondition(fractional.rect.width == CGFloat(Float(63.7)))
        let base = CGRect(x: 1440, y: 100, width: 1280, height: 900)
        let window = CGRect(x: 1500, y: 100, width: 800, height: 160)
        let resting = DockSystemGeometry.restingChrome(
            window: window, size: CGSize(width: 600, height: 64), edge: .bottom, edgeGap: 12)
        let occupied = DockSystemGeometry.strip(screen: base, chrome: resting, edge: .bottom)
        precondition(occupied == CGRect(x: 1440, y: 100, width: 1280, height: 76),
                     "Reserve the 64-point chrome and 12-point gap, excluding magnification headroom")
        precondition(DockSystemGeometry.usableFrame(screen: base, strip: occupied, edge: .bottom)
                     == CGRect(x: 1440, y: 176, width: 1280, height: 824))
    }

}

extension DockSystemRegression {
    private static func checkReservedDisplaySelection() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = CGRect(x: -1280, y: 200, width: 1280, height: 800)
        for edge in [ResolvedDockWindowPosition.bottom, .top, .left, .right] {
            let tile: CGRect
            switch edge {
            case .bottom: tile = CGRect(x: -800, y: 200, width: 50, height: 50)
            case .top: tile = CGRect(x: -800, y: 950, width: 50, height: 50)
            case .left: tile = CGRect(x: -1280, y: 500, width: 50, height: 50)
            case .right: tile = CGRect(x: -50, y: 500, width: 50, height: 50)
            }
            let strip = DockSystemGeometry.strip(screen: secondary, chrome: tile, edge: edge)
            let usable = DockSystemGeometry.usableFrame(screen: secondary, strip: strip, edge: edge)
            precondition(!usable.intersects(tile))
            precondition(DockPresentationGeometry.screenIndex(containing: tile, frames: [primary, secondary]) == 1)
        }
    }

    private static func checkDirectProbeRollback(screen: NSScreen) async throws {
        guard let original = NativeDockIntegration.readReservation() else { throw NSError(domain: "Probe", code: 1) }
        let reservation = NativeDockIntegration.Reservation(
            rect: CGRect(x: screen.frame.minX, y: screen.frame.height - 71, width: screen.frame.width, height: 71),
            reason: 0, orientation: 2)
        try WindowReservationService.probeDirectPublication(reservation)
        try ensure(NativeDockIntegration.readReservation() == original, "Direct probe must restore before loading")
        do {
            // Invalid Dock identity fails before task-port authorization, just
            // as a rejected loader must leave the already-restored probe alone.
            try await DockBridgeLoader.load(into: -1)
            throw NSError(domain: "UnexpectedLoaderSuccess", code: 1)
        } catch {
            try ensure((error as NSError).domain != "UnexpectedLoaderSuccess", "Invalid Dock PID was accepted")
        }
        DockBridgeLoader.resetFailure()
        try ensure(NativeDockIntegration.readReservation() == original, "Loader failure left the probe installed")
    }

    private static func checkSocketBudget() {
        let path = "/tmp/docky-connect-\(UUID().uuidString).sock"
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) {
                $0.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strlcpy($0, source, 104) }
            }
        }
        let server = socket(AF_UNIX, SOCK_STREAM, 0)
        precondition(server >= 0)
        defer { close(server); unlink(path) }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        precondition(result == 0 && listen(server, 1) == 0)
        var clients: [Int32] = []
        defer { clients.forEach { close($0) } }
        var rejected = false
        let start = ContinuousClock.now
        for _ in 0..<8 {
            let client = socket(AF_UNIX, SOCK_STREAM, 0)
            precondition(client >= 0)
            clients.append(client)
            do { try DockBridgeTransport.connectWithinBudget(client, address: &address) } catch {
                rejected = true
                break
            }
        }
        precondition(rejected && start.duration(to: .now) < .seconds(2),
                     "A full listener backlog must not block the transport")
    }

    private static func checkPreferenceMigration() {
        let suite = "DockyRegression-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Could not create isolated defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        for key in ["docky.hidesSystemDock", "docky.hidesDuringFullscreen", "docky.maximizedWindowBehavior"] {
            defaults.set(false, forKey: key)
        }
        defaults.set("top", forKey: "docky.windowPosition")
        defaults.set(0.75, forKey: "docky.fullscreenRevealDelay")
        DockLegacyPreferenceMigration.discardOverlapSettings(in: defaults)
        precondition(defaults.object(forKey: "docky.hidesSystemDock") == nil)
        precondition(defaults.object(forKey: "docky.hidesDuringFullscreen") == nil)
        precondition(defaults.object(forKey: "docky.maximizedWindowBehavior") == nil)
        precondition(defaults.string(forKey: "docky.windowPosition") == "top")
        precondition(defaults.double(forKey: "docky.fullscreenRevealDelay") == 0.75)
        do {
            let profile = DockProfile(name: "Legacy import", dateCreated: Date(timeIntervalSinceReferenceDate: 0))
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any] ?? [:]
            object["hidesDuringFullscreen"] = false
            object["hidesSystemDock"] = false
            object["maximizedWindowBehavior"] = "ignore"
            let imported = try JSONSerialization.data(withJSONObject: object)
            let decoded = try JSONDecoder().decode(DockProfile.self, from: imported)
            precondition(decoded == profile, "Imported profiles cannot restore removed overlap settings")
        } catch { fatalError("Profile migration failed: \(error)") }
    }

    private static func checkVisibility() async throws {
        let window = MainWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 100),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        precondition(window.level.rawValue == Int(CGWindowLevelForKey(.dockWindow)))
        precondition(!window.canBecomeKey && !window.canBecomeMain)
        window.orderFront(nil)
        window.didOrderDockWindow()
        try await checkNativeWindowLevel(window)
        window.applyFullscreenState(false, animated: false)
        window.isPointerInsideWindow = true
        let oldHold = window.beginInteraction()
        let profiles = ProfileSwitcherWindowController(mainWindow: window)
        let progress = SmartOrganizeProgressChipWindowController(mainWindow: window)
        let progressToken = SmartOrganizeProgressService.shared.begin()
        defer { SmartOrganizeProgressService.shared.end(progressToken) }
        try await Task.sleep(for: .milliseconds(50))
        DockEditModeService.shared.enter()
        window.applyFullscreenState(true, animated: false)
        precondition(window.visibilityState == .hidden && !window.permitsPassivePresentation)
        precondition(window.activeInteractionCount == 0 && !window.isPointerInsideWindow)
        precondition(!DockEditModeService.shared.isActive)
        precondition(!profiles.window!.isVisible && !progress.window!.isVisible)
        let rejectedHold = window.beginInteraction()
        precondition(window.visibilityState == .hidden && window.activeInteractionCount == 0)
        window.isPointerInsideWindow = true
        window.scheduleFullscreenReveal()
        precondition(window.visibilityState == .hidden, "A pending edge dwell must not reveal immediately")
        window.fullscreenRevealWorkItem?.perform()
        precondition(window.visibilityState == .visible && window.fullscreenRevealAuthorized)
        precondition(progress.window!.isVisible)
        precondition(profiles.window!.isVisible == (!DockyPreferences.shared.hidesProfileStrip
            && ProfileService.shared.profiles.count > 1))
        let currentHold = window.beginInteraction()
        window.endInteraction(oldHold)
        window.endInteraction(rejectedHold)
        precondition(window.activeInteractionCount == 1, "A stale or rejected panel cannot release a newer hold")
        window.endInteraction(currentHold)
        window.endInteraction(currentHold)
        precondition(window.activeInteractionCount == 0, "Duplicate releases must be harmless")
        window.pointerDidExitWindow()
        window.hideWorkItem?.perform()
        precondition(window.visibilityState == .hidden && !window.fullscreenRevealAuthorized)
        precondition(!profiles.window!.isVisible && !progress.window!.isVisible)
    }

    private static func checkNativeWindowLevel(_ window: MainWindow) async throws {
        // AppKit's order/frame transactions can temporarily expose the server's
        // initial level. Wait for the actual level, never substitute AppKit's
        // cached property or accept the provisional level as a pass.
        let expected = Int32(CGWindowLevelForKey(.dockWindow))
        let deadline = ContinuousClock.now + .seconds(1)
        var actual = try nativeWindowLayer(window)
        while actual != expected, ContinuousClock.now < deadline {
            print("Awaiting WindowServer level: server=\(actual) active=\(NSApp.isActive) "
                + "policy=\(NSApp.activationPolicy().rawValue) floating=\(window.isFloatingPanel)")
            try await Task.sleep(for: .milliseconds(50))
            actual = try nativeWindowLayer(window)
        }
        try ensure(actual == expected,
                   "Dock level=\(actual), AppKit=\(window.level.rawValue), frame=\(window.frame), "
                   + "visible=\(window.isVisible), fullscreen=\(window.isFullscreenActive)")
    }

    private static func nativeWindowLayer(_ window: NSWindow) throws -> Int32 {
        // The public window list can omit an off-screen window or a window
        // in an inactive Space. Query its actual server level directly.
        typealias Connection = @convention(c) () -> Int32
        typealias GetLevel = @convention(c) (Int32, UInt32, UnsafeMutablePointer<Int32>) -> Int32
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let connectionAddress = dlsym(handle, "SLSMainConnectionID"),
              let levelAddress = dlsym(handle, "SLSGetWindowLevel") else {
            throw NSError(domain: "DockSystemRegression", code: 1)
        }
        defer { dlclose(handle) }
        let connection = unsafeBitCast(connectionAddress, to: Connection.self)
        let getLevel = unsafeBitCast(levelAddress, to: GetLevel.self)
        var level: Int32 = -1
        try ensure(getLevel(connection(), UInt32(window.windowNumber), &level) == 0, "WindowServer level query failed")
        return level
    }

    private static func checkNativeReservation(screen: NSScreen) async throws {
        let base = NativeDockIntegration.unreservedFrame(screen)
        for edge in [ResolvedDockWindowPosition.bottom, .left, .right, .top] {
            let chrome: CGRect
            switch edge {
            case .bottom: chrome = CGRect(x: base.midX - 200, y: base.minY, width: 400, height: 70)
            case .top: chrome = CGRect(x: base.midX - 200, y: base.maxY - 70, width: 400, height: 70)
            case .left: chrome = CGRect(x: base.minX, y: base.midY - 200, width: 70, height: 400)
            case .right: chrome = CGRect(x: base.maxX - 70, y: base.midY - 200, width: 70, height: 400)
            }
            let strip = DockSystemGeometry.strip(screen: base, chrome: chrome, edge: edge)
            let reservation = NativeDockIntegration.Reservation(
                rect: DockSystemGeometry.quartz(strip, primaryMaxY: screen.frame.maxY), reason: 0,
                orientation: DockSystemGeometry.orientation(edge))
            try ensure(NativeDockIntegration.publish(reservation) == 0, "SkyLight rejected reservation")
            try ensure(NativeDockIntegration.readReservation() == reservation, "SkyLight readback mismatch")
            let frames = try await WindowReservationService.shared.externalVisibleFrames()
            let expected = DockSystemGeometry.usableFrame(screen: base, strip: strip, edge: edge)
            guard let display = NativeDockIntegration.displayID(screen), let actual = frames[String(display)] else {
                throw NSError(domain: "DockSystemRegression", code: 1)
            }
            try ensure(actual == expected, "\(edge): expected \(expected), actual \(actual)")
            print("Verified \(edge) reservation in independent AppKit process: \(actual)")
        }
        let unreserved = NativeDockIntegration.Reservation(rect: .zero, reason: 2, orientation: 2)
        try ensure(NativeDockIntegration.publish(unreserved) == 0, "SkyLight rejected release")
        let frames = try await WindowReservationService.shared.externalVisibleFrames()
        if let display = NativeDockIntegration.displayID(screen) {
            try ensure(frames[String(display)] == base, "Autohide/fullscreen must release the desktop")
        }
    }

}

extension DockSystemRegression {
    private static func checkLiveFullscreen(screen: NSScreen) async throws {
        let fixture = NSWindow(contentRect: CGRect(x: screen.frame.midX - 300, y: screen.frame.midY - 200,
                                                  width: 600, height: 400),
                               styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        fixture.isReleasedWhenClosed = false
        fixture.title = "Docky Fullscreen Regression"
        fixture.collectionBehavior = [.fullScreenPrimary]
        let dock = MainWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        dock.isReleasedWhenClosed = false
        defer { dock.close(); fixture.close() }
        NSApp.setActivationPolicy(.regular)
        fixture.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        dock.orderFront(nil)
        dock.didOrderDockWindow()
        // Activation, ordering, and the switch from accessory to regular
        // policy are asynchronous. Fullscreen requested before they flush
        // can be rejected without creating a managed Space.
        try await Task.sleep(for: .seconds(1))
        fixture.toggleFullScreen(nil)
        do {
            try await waitForFullscreen(true, screen: screen)
            dock.updateFullscreenStateAndApply(animated: false)
            try ensure(dock.isFullscreenActive && dock.visibilityState == .hidden,
                       "A real managed fullscreen Space must immediately hide Docky")
            fixture.toggleFullScreen(nil)
            try await waitForFullscreen(false, screen: screen)
            dock.updateFullscreenStateAndApply(animated: false)
            try ensure(!dock.isFullscreenActive, "Fullscreen exit must restore normal Dock state")
            print("Verified live managed-Space fullscreen entry and exit without AX queries")
        } catch {
            if fixture.styleMask.contains(.fullScreen) {
                fixture.toggleFullScreen(nil)
                try? await waitForFullscreen(false, screen: screen)
            }
            throw error
        }
    }

    private static func waitForFullscreen(_ expected: Bool, screen: NSScreen) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while NativeDockIntegration.isFullscreen(screen) != expected {
            guard ContinuousClock.now < deadline else {
                throw NSError(domain: "DockSystemRegression", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Fullscreen transition exceeded five seconds"])
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        // The Space changes before AppKit finishes its animation. Let the
        // transition complete before asking the fixture to exit fullscreen.
        try await Task.sleep(for: .milliseconds(600))
    }

    private static func ensure(_ condition: Bool, _ message: String) throws {
        guard condition else {
            throw NSError(domain: "DockSystemRegression", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

}
#endif
