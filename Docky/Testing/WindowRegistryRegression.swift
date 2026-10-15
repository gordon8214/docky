#if DEBUG
    import AppKit
    import Combine
    import Darwin

    /// Checks the SkyLight-backed window registry. Right after its first
    /// build and again after about 10 s of live updates, every user window on
    /// every Space must be listed once, with bounds matching CoreGraphics. The
    /// active-Space flag must match CoreGraphics's on-screen list. Every
    /// switchable window, including minimized windows and windows on other
    /// Spaces, must get a thumbnail, and the remote-token scan must find AX
    /// elements for visible windows on other Spaces. `--watch-registry
    /// <seconds>` then prints each registry change, so WindowServer
    /// notifications can be checked while you move, resize, minimize, or close
    /// a window. Expected duration: under 10 seconds, longer when some window
    /// has no AX element. External runtime budget: 30 seconds plus the watch
    /// time.
    @MainActor
    enum WindowRegistryRegression {
        private struct Failure: Error, CustomStringConvertible { let description: String }

        /// Apps whose windows `WindowRegistry` may drop by app-specific rules.
        private static let discriminatedBundlePrefixes = ["com.valvesoftware.steam", "org.mozilla.", "com.jetbrains."]

        static func run() async {
            do {
                let watchSeconds = try watchDuration()
                try await checkRegistry()
                if let seconds = watchSeconds {
                    await watch(for: seconds)
                }
                print("Window registry regressions passed")
                fflush(stdout)
                exit(0)
            } catch {
                print("Window registry regression failed: \(error)")
                fflush(stdout)
                exit(1)
            }
        }

        private static func check(_ condition: Bool, _ message: @autoclosure () -> String) throws {
            if !condition { throw Failure(description: message()) }
        }

        /// Polls `condition` every 50 ms; returns whether it became true in time.
        @discardableResult
        private static func waitUntil(seconds: Double, _ condition: () -> Bool) async -> Bool {
            let deadline = ContinuousClock.now + .milliseconds(Int(seconds * 1000))
            while ContinuousClock.now < deadline {
                if condition() { return true }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return condition()
        }

        private static func label(_ window: AppWindow) -> String {
            "\(window.appDisplayName) #\(window.cgWindowID)"
        }

        private static func checkRegistry() async throws {
            PermissionsService.shared.refresh()
            try check(PermissionsService.shared.accessibility == .granted, "Accessibility permission is required")
            try check(PermissionsService.shared.screenCapture == .granted, "Screen capture permission is required")
            let registry = WindowRegistry.shared
            let workspace = WorkspaceService.shared
            await waitUntil(seconds: 3) { !registry.windows.isEmpty }
            try check(!registry.windows.isEmpty, "The registry listed no windows; open at least one app window")

            // Listing and bounds right after the registry's own first build.
            let initial = try windowServerMismatches(registry)
            try check(initial.isEmpty, initial.joined(separator: "\n"))

            // Active Space: CoreGraphics's on-screen list is an independent
            // source for which windows are on a shown Space.
            let onScreen = Set((CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] ?? []).compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
            let misplaced = registry.windows.filter {
                !$0.isMinimized && $0.isOnActiveSpace != onScreen.contains($0.cgWindowID)
            }
            try check(misplaced.isEmpty, "Wrong active-Space flag for \(misplaced.map(label))")
            let activeSpace = registry.switchable(includeMinimized: true, spaceScope: .activeSpace)
            try check(activeSpace.allSatisfy(\.isOnActiveSpace),
                      "The Active Space scope must drop windows on other Spaces")
            let otherSpaces = registry.windows.filter { !$0.isOnActiveSpace }
            print("Listed \(registry.windows.count) windows: \(otherSpaces.count) on other Spaces, "
                  + "\(registry.minimized.count) minimized")
            fflush(stdout)

            // Thumbnails: every switchable window on every Space, plus the
            // dock's minimized-window previews. Read live, so a window that
            // closes during the wait isn't reported.
            workspace.forceRefreshWindowPreviews()
            let started = ContinuousClock.now
            func missingPreviews() -> [AppWindow] {
                registry.switchable(includeMinimized: true).filter { workspace.appWindowPreview(for: $0) == nil }
                    + registry.minimized.filter { workspace.minimizedWindowPreview(for: $0) == nil }
            }
            await waitUntil(seconds: 10) { missingPreviews().isEmpty }
            let uncaptured = missingPreviews()
            try check(uncaptured.isEmpty, "No thumbnail for \(uncaptured.map(label))")
            print("Captured \(registry.switchable(includeMinimized: true).count) thumbnails "
                  + "in \(started.duration(to: .now))")
            fflush(stdout)

            // AX elements: the background lookup's remote-token scan reaches
            // visible windows on other Spaces. Minimized windows are left out,
            // because AX's own window list already includes them.
            await waitUntil(seconds: 8) { registry.isAccessibilityLookupIdle }
            let resolved = registry.windows.filter(registry.hasAccessibilityElement)
            let scanned = otherSpaces.filter { !$0.isMinimized }
            let resolvedByScan = scanned.filter(registry.hasAccessibilityElement)
            print("AX elements for \(resolved.count) of \(registry.windows.count) windows, "
                  + "\(resolvedByScan.count) of \(scanned.count) visible on other Spaces")
            let unresolved = registry.windows.filter { !registry.hasAccessibilityElement(for: $0) }
            if !unresolved.isEmpty { print("No AX element: \(unresolved.map(label))") }
            if scanned.isEmpty { print("Not covered: no visible window on another Space") }
            fflush(stdout)
            try check(scanned.isEmpty || !resolvedByScan.isEmpty,
                      "The remote-token scan found no window on another Space")

            // The list stays right after ~10 s of WindowServer and AX updates.
            await waitUntil(seconds: 2) { (try? windowServerMismatches(registry))?.isEmpty == true }
            let later = try windowServerMismatches(registry)
            try check(later.isEmpty, "After updates: " + later.joined(separator: "\n"))
        }

        /// Differences between the registry and a fresh WindowServer read:
        /// windows missing or listed twice, windows WindowServer no longer
        /// lists, and bounds that differ from CoreGraphics.
        private static func windowServerMismatches(_ registry: WindowRegistry) throws -> [String] {
            let applications = NSWorkspace.shared.runningApplications
            let tracked = Set(applications.filter(WindowRegistry.shouldTrack).map(\.processIdentifier))
            let bundles = Dictionary(applications.map { ($0.processIdentifier, $0.bundleIdentifier ?? "") },
                                     uniquingKeysWith: { first, _ in first })
            let snapshot = try unwrap(WindowServerWindows.snapshot(checkingOrderFor: tracked),
                                      "SkyLight window SPI is unavailable")
            let expected = snapshot.windows.filter { $0.isListed && tracked.contains($0.processIdentifier) }
            let expectedIDs = Set(expected.map(\.id))
            let listedIDs = registry.windows.map(\.cgWindowID)
            var problems: [String] = []
            if Set(listedIDs).count != listedIDs.count {
                problems.append("The registry lists a window twice")
            }
            let missing = expected.filter { info in
                let bundle = bundles[info.processIdentifier] ?? ""
                return !listedIDs.contains(info.id)
                    && !discriminatedBundlePrefixes.contains(where: bundle.hasPrefix)
            }
            if !missing.isEmpty { problems.append("Windows missing from the registry: \(missing.map(\.id))") }
            let stale = registry.windows.filter { !expectedIDs.contains($0.cgWindowID) }
            if !stale.isEmpty { problems.append("Registry lists windows WindowServer doesn't: \(stale.map(label))") }
            for window in registry.windows where expectedIDs.contains(window.cgWindowID) {
                let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], window.cgWindowID)
                    as? [[String: Any]] ?? []
                guard let dictionary = info.first?[kCGWindowBounds as String] as? NSDictionary else {
                    problems.append("\(label(window)) vanished from CoreGraphics")
                    continue
                }
                var bounds = CGRect.null
                _ = CGRectMakeWithDictionaryRepresentation(dictionary, &bounds)
                if let frame = window.frame, frame != bounds {
                    problems.append("Registry bounds for \(label(window)) differ from kCGWindowBounds: \(frame) vs \(bounds)")
                }
            }
            return problems
        }

        private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
            guard let value else { throw Failure(description: message) }
            return value
        }

        /// The `--watch-registry` time, or nil without the flag.
        private static func watchDuration() throws -> Double? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "--watch-registry") else { return nil }
            guard index + 1 < arguments.count, let seconds = Double(arguments[index + 1]),
                  seconds.isFinite, seconds > 0 else {
                throw Failure(description: "--watch-registry needs a positive number of seconds")
            }
            return seconds
        }

        /// Prints each change to the registry without window titles.
        private static func watch(for seconds: Double) async {
            print("Watching the registry for \(Int(seconds)) seconds")
            fflush(stdout)
            var previous = Dictionary(WindowRegistry.shared.windows.map { ($0.cgWindowID, $0) },
                                      uniquingKeysWith: { first, _ in first })
            var previousFront = WindowRegistry.shared.windows.first?.cgWindowID
            let started = ContinuousClock.now
            let subscription = WindowRegistry.shared.$windows.dropFirst().sink { windows in
                let elapsed = started.duration(to: .now).formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 2)))
                let current = Dictionary(windows.map { ($0.cgWindowID, $0) }, uniquingKeysWith: { first, _ in first })
                for (id, window) in current where previous[id] == nil {
                    print("\(elapsed) added \(label(window)) minimized=\(window.isMinimized) activeSpace=\(window.isOnActiveSpace)")
                }
                for (id, window) in previous where current[id] == nil {
                    print("\(elapsed) removed \(label(window))")
                }
                for (id, window) in current {
                    guard let old = previous[id], old != window else { continue }
                    var changes: [String] = []
                    if old.frame != window.frame { changes.append("frame \(String(describing: window.frame))") }
                    if old.isMinimized != window.isMinimized { changes.append("minimized=\(window.isMinimized)") }
                    if old.isOnActiveSpace != window.isOnActiveSpace { changes.append("activeSpace=\(window.isOnActiveSpace)") }
                    if old.windowTitle != window.windowTitle { changes.append("title changed") }
                    print("\(elapsed) changed \(label(window)): \(changes.joined(separator: ", "))")
                }
                if let front = windows.first, front.cgWindowID != previousFront {
                    print("\(elapsed) most recent \(label(front))")
                }
                fflush(stdout)
                previous = current
                previousFront = windows.first?.cgWindowID
            }
            try? await Task.sleep(for: .seconds(seconds))
            subscription.cancel()
        }
    }
#endif
