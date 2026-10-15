//
//  WindowRegistry.swift
//  Docky
//
//  Single source of truth for "what windows exist right now" across all
//  running apps, on every Space.
//
//  WindowServer (SkyLight) decides which windows exist, where they are, and
//  whether they're minimized. Its window ID is each window's identity, so a
//  title change, an AX element swap or a Space move never makes a window look
//  new. WindowServer notifications drive updates, including for apps whose
//  Accessibility server is hung.
//
//  Accessibility still provides what WindowServer can't: focus order (MRU),
//  title-change cues and the actions (restore, close, minimize, zoom, resize).
//  AX elements are resolved by window ID in the background, including for
//  windows on other Spaces, which `kAXWindowsAttribute` omits.
//
//  Threading: this class is isolated to the main actor. AX observers and
//  WindowServer notifications are delivered on the main run loop, and
//  `NSWorkspace` notifications on the main queue.
//

import AppKit
import ApplicationServices
import Combine
import os

@MainActor private let axCloseAction = "AXClose" as CFString
private let logger = Logger(subsystem: "gt.quintero.Docky", category: "WindowRegistry")
private let minimumTrackedWindowSize = CGSize(width: 100, height: 100)

/// System helpers whose windows would leak into the switcher / preview if
/// we treated them like regular apps. Most are filtered by activation policy
/// already; this is a defensive belt-and-braces layer for cases where an
/// agent transiently flips to `.regular` (Notification Center has done this
/// in the past).
private let filteredBundleIdentifiers: Set<String> = [
    "com.apple.notificationcenterui",
    "com.apple.WindowManager",
    "com.apple.dock",
]

/// Stable identity for an `AppWindow`: its WindowServer window ID, which
/// lasts for the window's lifetime.
nonisolated struct WindowID: Hashable, Sendable {
    let windowID: CGWindowID

    /// Stable string form for callers that need a string key (preview cache
    /// keys, debug logs). Stable for the window's lifetime.
    nonisolated var stableString: String {
        "wid:\(windowID)"
    }
}

/// A window observed in the registry. Identity is the WindowServer window
/// ID; all other fields are snapshots refreshed as notifications arrive.
struct AppWindow: Identifiable, Hashable {
    nonisolated let cgWindowID: CGWindowID
    nonisolated let bundleIdentifier: String
    nonisolated let processIdentifier: pid_t
    nonisolated let appDisplayName: String
    nonisolated let windowTitle: String
    nonisolated let isMinimized: Bool
    /// Whether the window is on a Space currently shown on some display.
    nonisolated let isOnActiveSpace: Bool
    nonisolated let frame: CGRect?

    nonisolated var id: WindowID { WindowID(windowID: cgWindowID) }

    /// Compatibility alias matching the previous API surface.
    nonisolated var windowIdentifier: String { id.stableString }

    /// Compatibility alias matching the previous API surface.
    nonisolated var screenBounds: CGRect? { frame }

    nonisolated func with(frame: CGRect) -> AppWindow {
        AppWindow(
            cgWindowID: cgWindowID,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            appDisplayName: appDisplayName,
            windowTitle: windowTitle,
            isMinimized: isMinimized,
            isOnActiveSpace: isOnActiveSpace,
            frame: frame
        )
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@MainActor
final class WindowRegistry: ObservableObject {
    static let shared = WindowRegistry()

    /// Window list across all tracked apps and Spaces, in per-window MRU
    /// order: focus changes move only the focused window to the front;
    /// updates land in place; new windows are appended.
    @Published private(set) var windows: [AppWindow] = []

    /// Fires when a window's cached preview should be evicted and re-
    /// captured, even though the registry's `$windows` array hasn't
    /// changed shape. Emitted once a resize settles (aspect ratio changed)
    /// and on focus-out (capture the outgoing window while it's still on
    /// top). The associated value is `AppWindow.windowIdentifier`.
    let previewInvalidations = PassthroughSubject<String, Never>()

    /// Per-pid tracking of the AX-focused window so we can name the
    /// outgoing window when focus changes. Only used to drive preview
    /// invalidation; the canonical list ordering still lives in `windows`.
    private var lastFocusedWindowIDByPID: [pid_t: WindowID] = [:]

    /// A window that took focus before the registry listed it. The next
    /// snapshot moves it to the front unless another window takes focus.
    private var pendingFrontWindow: (id: WindowID, pid: pid_t)?

    /// Windows currently minimized, in observation order. Newest minimized
    /// last — `last(where: bundleID:)` gives the most-recently minimized.
    var minimized: [AppWindow] {
        windows.filter(\.isMinimized)
    }

    /// Windows that are visible (non-minimized) and large enough to be
    /// interactable — the natural "switchable" set — on every Space.
    var visible: [AppWindow] {
        windows.filter { window in
            guard !window.isMinimized else { return false }
            return isCapturable(window)
        }
    }

    /// Same as `visible` but optionally folds minimized windows back in
    /// so the switcher / hover preview can present them under a
    /// "(minimized)" badge, and optionally keeps only windows on a Space
    /// currently shown.
    func switchable(
        includeMinimized: Bool,
        spaceScope: WindowSwitcherSpaceScope = .allSpaces
    ) -> [AppWindow] {
        windows.filter { window in
            guard spaceScope.includes(windowOnActiveSpace: window.isOnActiveSpace) else { return false }
            if window.isMinimized {
                return includeMinimized
            }
            return isCapturable(window)
        }
    }

    /// True when the window is large enough to be a real content window
    /// (>= 100x100). Filters out auxiliary overlays and menu-bar strips.
    /// Independent of minimized state — per-tile hover previews legitimately
    /// want minimized windows so long as they're real windows.
    func isCapturable(_ window: AppWindow) -> Bool {
        guard let size = window.frame?.size else { return false }
        return size.width >= minimumTrackedWindowSize.width
            && size.height >= minimumTrackedWindowSize.height
    }

    private var applicationObservers: [pid_t: AXObserver] = [:]
    /// Failed AX observer registrations, retried on later snapshots. A
    /// launching app often doesn't serve AX yet.
    private var observerRetries: [pid_t: (attempts: Int, notBefore: ContinuousClock.Instant)] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var permissionCancellables: Set<AnyCancellable> = []
    private var observationsActive = false
    private var reportedUnavailable = false
    private var refreshScheduled = false
    private var registeredWindowServerEvents = false
    private var requestedNotificationWindowIDs: Set<CGWindowID> = []

    /// Moves and resizes arrive for every frame of a drag. They're applied
    /// at most every 100 ms, and preview invalidations once a resize settles.
    private var pendingFrameWindowIDs: Set<CGWindowID> = []
    private var frameFlushScheduled = false
    private var pendingResizeInvalidations: Set<CGWindowID> = []
    private var resizeInvalidationGeneration = 0

    /// AX elements by window ID. Filled from AX notifications, the background
    /// lookup, and on demand when an action needs one.
    private var accessibilityElements: [CGWindowID: AXUIElement] = [:]
    /// AX titles by window ID. Preferred over WindowServer titles, which are
    /// empty without Screen Recording permission.
    private var accessibilityTitles: [CGWindowID: String] = [:]
    /// JetBrains helper panels, recognized by subrole in the background lookup.
    private var floatingWindowIDs: Set<CGWindowID> = []
    /// Windows already looked up in the background, so windows AX never
    /// exposes (some Java and Electron helpers) aren't rescanned every update.
    private var attemptedAccessibilityLookups: Set<CGWindowID> = []
    private var accessibilityLookupInFlight = false
    private let accessibilityLookupQueue = DispatchQueue(label: "gt.quintero.Docky.window-ax-lookup", qos: .utility)

    private init() {
        PermissionsService.shared.$accessibility
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                if status == .granted {
                    self.startObservingIfNeeded()
                } else {
                    self.stopObserving()
                }
            }
            .store(in: &permissionCancellables)

        // Screen Recording adds WindowServer titles for windows AX doesn't name.
        PermissionsService.shared.$screenCapture
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &permissionCancellables)

        if PermissionsService.shared.accessibility == .granted {
            startObservingIfNeeded()
        }
    }

    isolated deinit {
        stopObserving()
    }

    // MARK: - Lookup

    func windows(forBundleIdentifier bundleIdentifier: String) -> [AppWindow] {
        windows.filter { $0.bundleIdentifier == bundleIdentifier }
    }

    func windowsByRecency(forBundleIdentifier bundleIdentifier: String) -> [AppWindow] {
        // The registry's `windows` array is maintained in per-window MRU
        // order: focus/activation events bump only the actually-focused
        // window to the front (see `bumpWindowToTop`). For this app, the
        // first match is the most recently focused window — its other
        // windows sit wherever they were last seen.
        windows(forBundleIdentifier: bundleIdentifier)
    }

    #if DEBUG
    /// Whether an AX element is cached for the window, for regressions.
    func hasAccessibilityElement(for window: AppWindow) -> Bool {
        accessibilityElements[window.cgWindowID] != nil
    }

    /// Whether every listed window has had its background AX lookup.
    var isAccessibilityLookupIdle: Bool {
        !accessibilityLookupInFlight
            && windows.allSatisfy { attemptedAccessibilityLookups.contains($0.cgWindowID) }
    }
    #endif

    // MARK: - Window operations

    /// Brings `window` to the front, switching Spaces when it lives on
    /// another one. Prefers the SLPS path (private SkyLight) because it
    /// targets a specific window ID — only the picked window comes forward,
    /// instead of every window of the app. Falls back to AX-raise +
    /// `NSRunningApplication.activate()` when SLPS is unavailable.
    @discardableResult
    func focus(_ window: AppWindow) -> Bool {
        guard PermissionsService.shared.accessibility == .granted else {
            PermissionsService.shared.presentPermissionAlert(for: .accessibility, actionTitle: "focus app windows")
            return false
        }

        // Only restoring a minimized window needs AX before SLPS, which
        // targets the window ID. Otherwise use a cached element for the
        // best-effort raise rather than waiting on a token scan.
        let element = window.isMinimized
            ? accessibilityElement(for: window)
            : accessibilityElements[window.cgWindowID]
        let restored: Bool
        if window.isMinimized {
            guard let element else { return false }
            restored = AXUIElementSetAttributeValue(
                element,
                kAXMinimizedAttribute as CFString,
                kCFBooleanFalse
            ) == .success
        } else {
            restored = true
        }

        if focusViaSLPS(pid: window.processIdentifier, cgWindowID: window.cgWindowID, element: element) {
            // SLPS doesn't unhide the app process itself; if it was hidden,
            // surface it now so its windows can actually display.
            if let runningApp = NSRunningApplication(processIdentifier: window.processIdentifier),
               runningApp.isHidden {
                runningApp.unhide()
            }
            return restored
        }

        // Legacy fallback: raise via AX, then activate the whole app. This
        // brings every window of the app forward — what we're trying to avoid
        // — but it's the only thing that works when SLPS fails.
        guard let element = element ?? accessibilityElement(for: window) else { return false }
        let raised = AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success

        if let runningApp = NSRunningApplication(processIdentifier: window.processIdentifier) {
            DispatchQueue.main.async {
                runningApp.unhide()
                runningApp.activateTransferringFrontmost()
            }
        }

        return restored && raised
    }

    private func focusViaSLPS(pid: pid_t, cgWindowID: CGWindowID, element: AXUIElement?) -> Bool {
        var psn = ProcessSerialNumber()
        guard GetProcessForPID(pid, &psn) == noErr else { return false }

        let result = _SLPSSetFrontProcessWithOptions(&psn, cgWindowID, SLPSMode.userGenerated.rawValue)
        guard result == .success else { return false }

        // Synthetic event handshake — without this the window comes up but
        // keyboard input still routes to the previous app.
        slpsMakeKeyWindow(psn: &psn, windowID: cgWindowID)

        // Best-effort: AX raise to confirm Z-order in AX, and mark as main so
        // the app's "main window changed" hooks fire. Failures here don't
        // unwind — the SLPS call already brought the window front.
        if let element {
            _ = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            _ = AXUIElementSetAttributeValue(element, kAXMainWindowAttribute as CFString, kCFBooleanTrue)
        }

        return true
    }

    @discardableResult
    func minimize(_ window: AppWindow) -> Bool {
        guard PermissionsService.shared.accessibility == .granted else {
            PermissionsService.shared.presentPermissionAlert(for: .accessibility, actionTitle: "minimize app windows")
            return false
        }

        guard let element = accessibilityElement(for: window) else {
            return false
        }

        return AXUIElementSetAttributeValue(
            element,
            kAXMinimizedAttribute as CFString,
            kCFBooleanTrue
        ) == .success
    }

    @discardableResult
    func close(_ window: AppWindow) -> Bool {
        guard PermissionsService.shared.accessibility == .granted else {
            PermissionsService.shared.presentPermissionAlert(for: .accessibility, actionTitle: "close app windows")
            return false
        }

        guard let element = accessibilityElement(for: window) else {
            return false
        }
        if AXUIElementPerformAction(element, axCloseAction) == .success {
            return true
        }
        return closeViaButton(element)
    }

    /// Presses the window's green zoom button via AX. Mirrors what the user
    /// would get clicking the title-bar button or selecting Window > Zoom —
    /// macOS handles the toggle between user-set size and visibleFrame fit.
    @discardableResult
    func zoom(_ window: AppWindow) -> Bool {
        guard PermissionsService.shared.accessibility == .granted else {
            PermissionsService.shared.presentPermissionAlert(for: .accessibility, actionTitle: "zoom app windows")
            return false
        }

        guard let element = accessibilityElement(for: window) else { return false }

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                element,
                kAXZoomButtonAttribute as CFString,
                &value
              ) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return false
        }
        let zoomButton = value as! AXUIElement
        return AXUIElementPerformAction(zoomButton, kAXPressAction as CFString) == .success
    }

    /// Resize-and-move via AX. No permission alert: callers (background
    /// services) want a silent failure when permission is missing.
    @discardableResult
    func resize(_ window: AppWindow, to frame: CGRect) -> Bool {
        guard PermissionsService.shared.accessibility == .granted else { return false }

        var origin = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size)
        else { return false }

        guard let element = accessibilityElement(for: window) else { return false }
        let posResult = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        let sizeResult = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        return posResult == .success && sizeResult == .success
    }

    /// Returns a live `AXUIElement` for the window, or nil when AX doesn't
    /// expose it. Uses the cached element when it still answers; otherwise
    /// looks the window up by ID, scanning the app's remote element tokens
    /// when the window is on another Space. The background lookup normally
    /// fills the cache first, so the main-thread scan is kept short.
    private func accessibilityElement(for window: AppWindow) -> AXUIElement? {
        if let element = accessibilityElements[window.cgWindowID], isElementResponsive(element) {
            return element
        }
        let found = WindowServerWindows.accessibilityWindows(
            pid: window.processIdentifier,
            wanted: [window.cgWindowID: window.frame ?? .null],
            budget: .milliseconds(150),
            readsDetails: false
        )
        let element = found[window.cgWindowID]?.element
        accessibilityElements[window.cgWindowID] = element
        return element
    }

    private func isElementResponsive(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &value
        ) == .success
    }

    private func closeViaButton(_ windowElement: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                windowElement,
                kAXCloseButtonAttribute as CFString,
                &value
              ) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return false
        }

        let closeButton = value as! AXUIElement
        return AXUIElementPerformAction(closeButton, kAXPressAction as CFString) == .success
    }

    // MARK: - Observation lifecycle

    private func startObservingIfNeeded() {
        guard !observationsActive else { return }
        guard WindowServerWindows.isAvailable else {
            if !reportedUnavailable {
                reportedUnavailable = true
                logger.error("SkyLight window SPI is unavailable; the window list stays empty")
            }
            return
        }
        observationsActive = true

        registerWindowServerEventsIfNeeded()
        subscribeToWorkspaceLifecycle()
        rebuildSnapshot()
        // Start MRU order from the focused window, not WindowServer order.
        if let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            bumpFocusedWindowToTop(pid: frontmost)
        }
    }

    private func stopObserving() {
        guard observationsActive else { return }
        observationsActive = false

        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        for (_, observer) in applicationObservers {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        applicationObservers.removeAll()
        observerRetries.removeAll()
        accessibilityElements.removeAll()
        accessibilityTitles.removeAll()
        floatingWindowIDs.removeAll()
        attemptedAccessibilityLookups.removeAll()
        lastFocusedWindowIDByPID.removeAll()
        requestedNotificationWindowIDs.removeAll()
        pendingFrameWindowIDs.removeAll()
        pendingResizeInvalidations.removeAll()
        pendingFrontWindow = nil

        if !windows.isEmpty {
            windows = []
        }
    }

    /// WindowServer can't unregister a notification handler, so the handler
    /// is installed once and ignores events while observation is stopped.
    private func registerWindowServerEventsIfNeeded() {
        guard !registeredWindowServerEvents else { return }
        registeredWindowServerEvents = true
        let failed = WindowServerWindows.register(
            WindowServerEvent.allCases,
            callback: windowServerNotificationCallback,
            context: nil
        )
        if !failed.isEmpty {
            logger.error("WindowServer notifications unavailable: \(failed.map(\.rawValue), privacy: .public)")
        }
    }

    private func subscribeToWorkspaceLifecycle() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            // Hidden apps' windows leave the list, matching ⌘H hiding them.
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            // Space switches change which windows are on an active Space.
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        workspaceObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                    .processIdentifier
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if name == NSWorkspace.didTerminateApplicationNotification, let pid {
                        self.removeApplication(pid)
                    }
                    self.scheduleRefresh()
                }
            }
        }
    }

    private func removeApplication(_ pid: pid_t) {
        removeObserver(for: pid)
        observerRetries.removeValue(forKey: pid)
        lastFocusedWindowIDByPID.removeValue(forKey: pid)
        if pendingFrontWindow?.pid == pid {
            pendingFrontWindow = nil
        }
        if windows.contains(where: { $0.processIdentifier == pid }) {
            windows.removeAll { $0.processIdentifier == pid }
        }
    }

    /// Apps the registry observes, hidden or not, so focus order survives
    /// hiding. Only `shouldTrack` apps have their windows listed.
    private func observedApplications() -> [pid_t: NSRunningApplication] {
        var applications: [pid_t: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications where Self.shouldObserve(app) {
            applications[app.processIdentifier] = app
        }
        return applications
    }

    /// Whether the registry observes `app`: regular apps other than Docky
    /// and system helpers.
    static func shouldObserve(_ app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .regular, app.processIdentifier > 0 else { return false }
        if let bundleId = app.bundleIdentifier {
            if filteredBundleIdentifiers.contains(bundleId) { return false }
            // Docky itself is invisible to every Docky-owned surface
            // (dock tiles, window switcher). Excluded by bundle ID so
            // running the app as a debug helper from Xcode is filtered
            // out too.
            if bundleId == Bundle.main.bundleIdentifier { return false }
        }
        return true
    }

    /// Whether the registry lists `app`'s windows: observed apps that
    /// aren't hidden.
    static func shouldTrack(_ app: NSRunningApplication) -> Bool {
        shouldObserve(app) && !app.isHidden
    }

    // MARK: - WindowServer events

    fileprivate func handleWindowServerEvent(_ event: WindowServerEvent, windowID: CGWindowID?) {
        guard observationsActive else { return }
        switch event {
        case .windowMoved, .windowResized:
            guard let windowID, windows.contains(where: { $0.cgWindowID == windowID }) else { return }
            pendingFrameWindowIDs.insert(windowID)
            scheduleFrameFlush()

        case .windowAddedToSpace:
            // Fires for every window on the system, including menus,
            // tooltips and Docky's own panels.
            guard isPotentialUserWindow(windowID) else { return }
            scheduleRefresh()

        case .windowRemovedFromSpace:
            // Only windows the registry follows can leave its list.
            if let windowID, !requestedNotificationWindowIDs.contains(windowID) { return }
            scheduleRefresh()

        case .windowDestroyed, .windowShown, .windowHidden:
            scheduleRefresh()
        }
    }

    /// Whether a window that just joined a Space could be listed: a
    /// top-level, normal-level window of an observed app. Unknown owners or
    /// levels count as potential, so nothing is missed.
    private func isPotentialUserWindow(_ windowID: CGWindowID?) -> Bool {
        guard let windowID, !windows.contains(where: { $0.cgWindowID == windowID }) else { return true }
        if let owner = WindowServerWindows.ownerPID(of: windowID) {
            guard let app = NSRunningApplication(processIdentifier: owner), Self.shouldObserve(app) else {
                return false
            }
        }
        return WindowServerWindows.isTopLevelNormalWindow(windowID) != false
    }

    /// Coalesces bursts of notifications (a window opening fires several)
    /// into one snapshot.
    private func scheduleRefresh() {
        guard observationsActive, !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshScheduled = false
                self.rebuildSnapshot()
            }
        }
    }

    private func scheduleFrameFlush() {
        guard !frameFlushScheduled else { return }
        frameFlushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
            MainActor.assumeIsolated {
                self?.flushFrameUpdates()
            }
        }
    }

    /// Applies every pending move and resize in one publish.
    private func flushFrameUpdates() {
        frameFlushScheduled = false
        let windowIDs = pendingFrameWindowIDs
        pendingFrameWindowIDs.removeAll()
        guard observationsActive else { return }
        var updated = windows
        var changed = false
        for windowID in windowIDs {
            guard let index = updated.firstIndex(where: { $0.cgWindowID == windowID }),
                  let bounds = WindowServerWindows.bounds(of: windowID),
                  bounds != updated[index].frame else { continue }
            if updated[index].frame?.size != bounds.size {
                scheduleResizeInvalidation(for: windowID)
            }
            updated[index] = updated[index].with(frame: bounds)
            changed = true
        }
        if changed {
            windows = updated
        }
    }

    /// Invalidates a resized window's preview once resizing has paused for
    /// 300 ms, so a live resize doesn't recapture on every frame.
    private func scheduleResizeInvalidation(for windowID: CGWindowID) {
        pendingResizeInvalidations.insert(windowID)
        resizeInvalidationGeneration += 1
        let generation = resizeInvalidationGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.resizeInvalidationGeneration else { return }
                let windowIDs = self.pendingResizeInvalidations
                self.pendingResizeInvalidations.removeAll()
                for window in self.windows where windowIDs.contains(window.cgWindowID) {
                    self.previewInvalidations.send(window.windowIdentifier)
                }
            }
        }
    }

    // MARK: - Per-app AX observer

    private func installObserver(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid > 0, applicationObservers[pid] == nil else { return }
        if let retry = observerRetries[pid], retry.attempts >= 5 || ContinuousClock.now < retry.notBefore {
            return
        }

        var observer: AXObserver?
        let createStatus = AXObserverCreate(pid, axObserverCallback, &observer)
        guard createStatus == .success, let observer else {
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        // A launching app may not serve AX yet; don't let it stall the
        // main thread for the global timeout on each registration.
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        let context = Unmanaged.passUnretained(self).toOpaque()

        // Window existence, geometry and minimization come from WindowServer.
        // AX supplies focus order and title changes, which it doesn't report.
        let notifications: [CFString] = [
            kAXWindowCreatedNotification as CFString,
            kAXTitleChangedNotification as CFString,
            kAXFocusedWindowChangedNotification as CFString,
            kAXMainWindowChangedNotification as CFString,
            kAXApplicationActivatedNotification as CFString,
            kAXApplicationShownNotification as CFString,
        ]

        var registered = 0
        for name in notifications {
            let result = AXObserverAddNotification(observer, appElement, name, context)
            if result == .success || result == .notificationAlreadyRegistered {
                registered += 1
            }
        }
        guard registered > 0 else {
            let attempts = (observerRetries[pid]?.attempts ?? 0) + 1
            observerRetries[pid] = (attempts, ContinuousClock.now + .seconds(1))
            return
        }
        observerRetries.removeValue(forKey: pid)
        applicationObservers[pid] = observer

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
    }

    private func removeObserver(for pid: pid_t) {
        guard let observer = applicationObservers.removeValue(forKey: pid) else {
            return
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
    }

    private func pid(for observer: AXObserver) -> pid_t? {
        applicationObservers.first(where: { $0.value === observer })?.key
    }

    fileprivate func handleNotification(
        observer: AXObserver,
        element: AXUIElement,
        notificationName: CFString
    ) {
        guard let pid = pid(for: observer) else { return }
        let name = notificationName as String

        switch name {
        case kAXFocusedWindowChangedNotification,
             kAXMainWindowChangedNotification:
            // Per-window MRU: the notification's element IS the now-focused
            // window. Move just that one to the front; the app's other
            // windows stay where they were in the global list.
            guard let windowID = windowID(of: element, pid: pid) else {
                scheduleRefresh()
                return
            }
            accessibilityElements[windowID] = element
            let newFocusedID = WindowID(windowID: windowID)
            invalidateOutgoingFocusedPreview(pid: pid, newFocusedID: newFocusedID)
            lastFocusedWindowIDByPID[pid] = newFocusedID
            bumpWindowToTop(newFocusedID, pid: pid)

        case kAXApplicationActivatedNotification,
             kAXApplicationShownNotification:
            // App-level signal — query AX for the currently focused window
            // and bump only that one (not the app's whole block).
            bumpFocusedWindowToTop(pid: pid)

        case kAXWindowCreatedNotification:
            if let windowID = windowID(of: element, pid: pid) {
                accessibilityElements[windowID] = element
            }
            scheduleRefresh()

        case kAXTitleChangedNotification:
            updateTitle(of: element, pid: pid)

        default:
            break
        }
    }

    /// Applies a window's new AX title in place. Title-changed also fires for
    /// controls inside windows, so the element must be the window itself.
    private func updateTitle(of element: AXUIElement, pid: pid_t) {
        let cached = accessibilityElements.first(where: { CFEqual($0.value, element) })?.key
        guard let windowID = cached ?? windowID(of: element),
              let index = windows.firstIndex(where: { $0.cgWindowID == windowID }),
              cached != nil || stringAttribute(kAXRoleAttribute as CFString, of: element) == kAXWindowRole as String,
              let title = stringAttribute(kAXTitleAttribute as CFString, of: element) else { return }
        accessibilityTitles[windowID] = title
        let existing = windows[index]
        let resolved = displayTitle(title, appDisplayName: existing.appDisplayName)
        guard resolved != existing.windowTitle else { return }
        windows[index] = AppWindow(
            cgWindowID: existing.cgWindowID,
            bundleIdentifier: existing.bundleIdentifier,
            processIdentifier: existing.processIdentifier,
            appDisplayName: existing.appDisplayName,
            windowTitle: resolved,
            isMinimized: existing.isMinimized,
            isOnActiveSpace: existing.isOnActiveSpace,
            frame: existing.frame
        )
    }

    private func windowID(of element: AXUIElement) -> CGWindowID? {
        var windowID: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &windowID) == .success, windowID != 0 else { return nil }
        return windowID
    }

    /// The element's window ID, or for apps whose AX elements don't report
    /// one, the listed window of `pid` with the same frame.
    private func windowID(of element: AXUIElement, pid: pid_t) -> CGWindowID? {
        if let windowID = windowID(of: element) { return windowID }
        guard let frame = frameAttribute(of: element) else { return nil }
        return windows.first { window in
            window.processIdentifier == pid && window.frame.map { $0.isApproximately(frame) } == true
        }?.cgWindowID
    }

    private func displayTitle(_ title: String, appDisplayName: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appDisplayName : trimmed
    }

    // MARK: - Snapshot mutation

    private func rebuildSnapshot() {
        guard observationsActive else { return }
        let applications = observedApplications()
        let listedPIDs = Set(applications.filter { !$0.value.isHidden }.keys)
        guard let snapshot = WindowServerWindows.snapshot(checkingOrderFor: listedPIDs) else { return }
        let liveWindows = snapshot.windows.filter { applications[$0.processIdentifier] != nil }
        let listed = liveWindows.filter { listedPIDs.contains($0.processIdentifier) && $0.isListed }
        // WindowServer titles fill in only where AX hasn't named the window.
        let serverTitles = WindowServerWindows.titles(
            for: listed.filter { accessibilityTitles[$0.id] == nil }.map(\.id)
        )

        var collected: [AppWindow] = []
        for info in listed {
            guard let app = applications[info.processIdentifier] else { continue }
            let bundleID = app.bundleIdentifier ?? "pid:\(info.processIdentifier)"
            let displayName = app.localizedName ?? bundleID
            let window = AppWindow(
                cgWindowID: info.id,
                bundleIdentifier: bundleID,
                processIdentifier: info.processIdentifier,
                appDisplayName: displayName,
                windowTitle: displayTitle(
                    accessibilityTitles[info.id] ?? serverTitles[info.id] ?? "",
                    appDisplayName: displayName
                ),
                isMinimized: info.isMinimized,
                isOnActiveSpace: !info.spaceIDs.isDisjoint(with: snapshot.activeSpaceIDs),
                frame: info.bounds
            )
            guard passesAppDiscriminator(window: window) else { continue }
            collected.append(window)
        }

        let previous = Dictionary(windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for window in collected {
            if let old = previous[window.id], old.frame?.size != window.frame?.size {
                scheduleResizeInvalidation(for: window.cgWindowID)
            }
        }
        applyOrdered(collected)

        // Listed windows first, so they keep their events if WindowServer's
        // per-connection limit is ever reached.
        let listedIDs = collected.map(\.cgWindowID)
        let listedIDSet = Set(listedIDs)
        let notificationIDs = listedIDs + liveWindows.map(\.id).filter { !listedIDSet.contains($0) }
        if Set(notificationIDs) != requestedNotificationWindowIDs {
            requestedNotificationWindowIDs = Set(notificationIDs)
            WindowServerWindows.requestNotifications(for: notificationIDs)
        }

        // Caches follow every live window, including hidden apps' windows and
        // windows a filter dropped, so neither is looked up again.
        let liveIDs = Set(liveWindows.map(\.id))
        accessibilityElements = accessibilityElements.filter { liveIDs.contains($0.key) }
        accessibilityTitles = accessibilityTitles.filter { liveIDs.contains($0.key) }
        floatingWindowIDs.formIntersection(liveIDs)
        attemptedAccessibilityLookups.formIntersection(liveIDs)
        for (pid, app) in applications where applicationObservers[pid] == nil {
            installObserver(for: app)
        }
        for pid in applicationObservers.keys where applications[pid] == nil {
            removeObserver(for: pid)
        }
        resolveMissingAccessibilityElements()
    }

    /// Looks up AX elements, titles and subroles for newly listed windows off
    /// the main actor, so actions on windows in other Spaces don't wait for a
    /// token scan and no AX attribute is read on the main thread per update.
    private func resolveMissingAccessibilityElements() {
        guard !accessibilityLookupInFlight else { return }
        var wanted: [pid_t: [CGWindowID: CGRect]] = [:]
        for window in windows where !attemptedAccessibilityLookups.contains(window.cgWindowID) {
            wanted[window.processIdentifier, default: [:]][window.cgWindowID] = window.frame ?? .null
            attemptedAccessibilityLookups.insert(window.cgWindowID)
        }
        guard !wanted.isEmpty else { return }
        accessibilityLookupInFlight = true
        let request = wanted
        accessibilityLookupQueue.async {
            var found: [CGWindowID: AccessibilityWindowElement] = [:]
            for (pid, windows) in request {
                let elements = WindowServerWindows.accessibilityWindows(
                    pid: pid,
                    wanted: windows,
                    budget: .milliseconds(400),
                    readsDetails: true
                )
                found.merge(elements) { _, new in new }
            }
            let result = found
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    WindowRegistry.shared.finishAccessibilityLookup(result)
                }
            }
        }
    }

    private func finishAccessibilityLookup(_ found: [CGWindowID: AccessibilityWindowElement]) {
        accessibilityLookupInFlight = false
        guard observationsActive else { return }
        let listed = Dictionary(windows.map { ($0.cgWindowID, $0) }, uniquingKeysWith: { first, _ in first })
        var needsRefresh = false
        for (windowID, handle) in found {
            guard let window = listed[windowID] else { continue }
            if accessibilityElements[windowID] == nil {
                accessibilityElements[windowID] = handle.element
            }
            if let title = handle.title {
                accessibilityTitles[windowID] = title
                if displayTitle(title, appDisplayName: window.appDisplayName) != window.windowTitle {
                    needsRefresh = true
                }
            }
            if let subrole = handle.subrole,
               window.bundleIdentifier.hasPrefix("com.jetbrains."),
               subrole == kAXFloatingWindowSubrole as String || subrole == kAXSystemFloatingWindowSubrole as String {
                floatingWindowIDs.insert(windowID)
                needsRefresh = true
            }
        }
        if needsRefresh { scheduleRefresh() }
        resolveMissingAccessibilityElements()
    }

    /// Moves a single window to the front of the registry. When the window
    /// isn't listed yet (focus raced its creation), the next snapshot moves
    /// it. Bypasses `applyOrdered`'s order preservation — this is the only
    /// mutation path that actually changes ordering.
    private func bumpWindowToTop(_ windowID: WindowID, pid: pid_t) {
        guard let index = windows.firstIndex(where: { $0.id == windowID }) else {
            pendingFrontWindow = (windowID, pid)
            scheduleRefresh()
            return
        }
        // A later focus wins over a window still waiting to be listed.
        pendingFrontWindow = nil
        // Already at the top — skip the mutation so we don't fire a
        // spurious @Published update.
        guard index != 0 else { return }
        // Reorder a copy so subscribers see one change, not a removal
        // followed by an insertion.
        var reordered = windows
        reordered.insert(reordered.remove(at: index), at: 0)
        windows = reordered
    }

    /// Looks up the app's currently focused window via AX and bumps just
    /// that one to the front. Used when the notification carries the app
    /// element rather than a window element.
    private func bumpFocusedWindowToTop(pid: pid_t) {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedWindowAttribute as CFString,
                &value
              ) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            // No focused window reported — refresh so we at least pick up
            // state changes (hide/unhide, fresh windows).
            scheduleRefresh()
            return
        }

        let focusedElement = value as! AXUIElement
        guard let windowID = windowID(of: focusedElement, pid: pid) else { return }
        accessibilityElements[windowID] = focusedElement
        bumpWindowToTop(WindowID(windowID: windowID), pid: pid)
    }

    /// Per-bundle filters that strip windows known to be false
    /// positives for specific apps — menu-bar shadows, scratch popups,
    /// invisible launcher panels. The whitelist is kept narrow on
    /// purpose: each rule should be backed by a real, repeatable bug.
    /// Returns `true` when the candidate looks legit for that app.
    private func passesAppDiscriminator(window: AppWindow) -> Bool {
        let trimmedTitle = window.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleID = window.bundleIdentifier
        let frame = window.frame

        // Steam emits windows for its in-app overlay shadows that
        // carry no title and dwarf the actual game window. The real
        // game/library windows always have a title.
        if bundleID == "com.valvesoftware.steam" {
            if trimmedTitle.isEmpty || trimmedTitle == window.appDisplayName {
                return false
            }
        }

        // Firefox briefly exposes a thin panel under the main window
        // when popovers open; height is the easiest reliable signal.
        if bundleID == "org.mozilla.firefox" || bundleID.hasPrefix("org.mozilla.") {
            if let frame, frame.height < 300 {
                return false
            }
        }

        // JetBrains IDEs back floating helper panels with real windows
        // (find-in-files, scratch tool windows). The main editor window
        // has no AX subrole; helpers carry `AXFloatingWindow` or
        // `AXSystemFloatingWindow`, read by the background lookup.
        if bundleID.hasPrefix("com.jetbrains."), floatingWindowIDs.contains(window.cgWindowID) {
            return false
        }

        return true
    }

    /// Emits a preview-invalidation for the window that just lost focus
    /// (the previous focused window of `pid`), so WorkspaceService can
    /// drop its stale capture and grab a fresh one while the window is
    /// still on top. No-op when the previous and new focused windows
    /// are the same, or when we have no prior record for this pid.
    private func invalidateOutgoingFocusedPreview(pid: pid_t, newFocusedID: WindowID) {
        guard let previousID = lastFocusedWindowIDByPID[pid],
              previousID != newFocusedID,
              let outgoing = windows.first(where: { $0.id == previousID }) else {
            return
        }
        previewInvalidations.send(outgoing.windowIdentifier)
    }

    /// Preserves existing order: existing windows keep their slot and pick
    /// up the latest fields from the snapshot. Newly observed windows are
    /// appended, those on an active Space first, in WindowServer order. A
    /// window that took focus before it was listed goes first, in the same
    /// publish.
    private func applyOrdered(_ snapshot: [AppWindow]) {
        let snapshotByID = Dictionary(snapshot.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var orderedExisting: [AppWindow] = []
        var seen = Set<WindowID>()
        for window in windows {
            guard let updated = snapshotByID[window.id], seen.insert(window.id).inserted else { continue }
            orderedExisting.append(updated)
        }
        let newcomers = snapshot.filter { seen.insert($0.id).inserted }
        var next = orderedExisting
            + newcomers.filter(\.isOnActiveSpace)
            + newcomers.filter { !$0.isOnActiveSpace }
        if let pending = pendingFrontWindow, let index = next.firstIndex(where: { $0.id == pending.id }) {
            pendingFrontWindow = nil
            next.insert(next.remove(at: index), at: 0)
        }
        if next != windows {
            windows = next
        }
    }

    // MARK: - AX attribute helpers

    private func stringAttribute(_ attribute: CFString, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func frameAttribute(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else {
            return nil
        }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}

// AXObserver requires a free C function — bounce into the registry singleton.
private func axObserverCallback(
    observer: AXObserver,
    element: AXUIElement,
    notificationName: CFString,
    context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let registry = Unmanaged<WindowRegistry>.fromOpaque(context).takeUnretainedValue()
    // Every AX observer source is installed on the main run loop.
    // These borrowed CF handles stay on that executor; they are never sent
    // to an asynchronous task or accessed from another thread.
    nonisolated(unsafe) let callbackObserver = observer
    nonisolated(unsafe) let callbackElement = element
    let name = notificationName as String
    MainActor.assumeIsolated {
        registry.handleNotification(
            observer: callbackObserver,
            element: callbackElement,
            notificationName: name as CFString
        )
    }
}

// WindowServer requires a free C function. The packet is only valid during
// the callback, so the window ID is read first. The handler always runs on a
// later main-queue turn, never inside SkyLight's dispatch, so it can't
// re-enter SkyLight or the registry's initialization.
private func windowServerNotificationCallback(
    type: UInt32,
    data: UnsafeMutableRawPointer?,
    length: UInt32,
    context: UnsafeMutableRawPointer?,
    connection: Int32
) {
    guard let event = WindowServerEvent(rawValue: type) else { return }
    let packet = UnsafeRawBufferPointer(start: data, count: data == nil ? 0 : Int(length))
    let windowID = event.windowID(in: packet)
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            WindowRegistry.shared.handleWindowServerEvent(event, windowID: windowID)
        }
    }
}
