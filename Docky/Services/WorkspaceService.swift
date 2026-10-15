//
//  WorkspaceService.swift
//  Docky
//
//  Observes NSWorkspace for live workspace state. First pass: running apps
//  (regular activation policy only, background agents and menu-bar-only
//  apps are filtered out since they don't belong in a dock). Running apps
//  are exposed in a stable order: still-running apps keep their position,
//  newly-launched apps append to the end. Designed to grow: frontmost app,
//  space changes, display changes, etc. can land here as new @Published
//  properties.
//

import AppKit
import ApplicationServices
import Combine
import CoreImage
import CoreMedia
import ScreenCaptureKit
import os

private let previewLogger = Logger(subsystem: "gt.quintero.Docky", category: "WindowPreview")

enum AppFolderTileLayout {
    case leftRight, rightLeft, topBottom, bottomTop, quarters
}

struct RunningApp: Hashable, Identifiable {
    let bundleIdentifier: String
    let localizedName: String
    let processIdentifier: pid_t
    let bundleURL: URL?
    let launchDate: Date?
    let isHidden: Bool

    var id: String { bundleIdentifier }
}

@MainActor
final class WorkspaceService: ObservableObject {
    static let shared = WorkspaceService()

    /// Ordered list: still-running apps keep their position across refreshes,
    /// newly-launched apps append. Terminated apps are removed in place.
    @Published private(set) var runningApps: [RunningApp] = []
    @Published private(set) var minimizedWindows: [AppWindow] = []
    @Published private(set) var minimizedWindowPreviews: [String: NSImage] = [:]
    @Published private(set) var appWindowPreviews: [String: NSImage] = [:]
    /// Bundle identifier of the app that currently owns the system
    /// activation (foreground), or `nil` when nothing is frontmost
    /// (rare, typically transient during space switches).
    @Published private(set) var frontmostBundleIdentifier: String?

    private var runningByBundleID: [String: RunningApp] = [:]

    var runningBundleIdentifiers: Set<String> { Set(runningByBundleID.keys) }

    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    private var attemptedMinimizedWindowPreviewIDs: Set<String> = []
    private var attemptedAppWindowPreviewIDs: Set<String> = []
    private var liveFocusPreviewSession: LiveWindowPreviewSession?
    private var liveFocusPreviewRequest = UUID()
    private let previewContentCache = WindowPreviewContentCache()
    private let windowCaptureQueue = DispatchQueue(label: "gt.quintero.Docky.window-capture", qos: .utility)
    /// The switcher's focused-window preview waits on its captures, so they
    /// don't queue behind background thumbnails.
    private let focusCaptureQueue = DispatchQueue(label: "gt.quintero.Docky.focus-capture", qos: .userInitiated)
    private var capturingWindowPreviewIDs: Set<String> = []

    /// A minimized-window capture can miss on its first try — the genie
    /// animation leaves the offscreen content briefly unavailable. Rather
    /// than mark the window done after one miss (which left it permanently
    /// thumbnail-less), retry a few times with a short delay before giving up.
    private let maxMinimizedPreviewAttempts = 3
    private let minimizedPreviewRetryDelay: Duration = .milliseconds(400)

    /// Delay between focusing a window and grabbing a fresh thumbnail of
    /// it. Long enough for the window to finish coming forward and render
    /// its current content, short enough to land before the user flips
    /// back to the switcher.
    private let postFocusPreviewCaptureDelay: Duration = .milliseconds(250)

    /// Backstop refresh interval for app-window thumbnails. Title changes
    /// handle the common case (browsers, IDEs); this catches content-only
    /// changes (editor scroll, in-page navigation) where the title stays put
    /// but the cached thumb no longer represents the window.
    private let appWindowPreviewTTL: TimeInterval = 120
    private struct PreviewMetadata {
        let capturedAt: Date
        let capturedTitle: String
    }
    private var appWindowPreviewMetadata: [String: PreviewMetadata] = [:]

    /// Pending thumbnail captures. Stale and invalidated thumbnails stay
    /// cached until their replacement arrives, and stale ones refresh a
    /// couple per second at most, so expiry never blanks every thumbnail at
    /// once or bursts captures.
    private var previewRefreshQueue = WindowPreviewRefreshQueue(
        staleInterval: .milliseconds(500),
        minimumRecaptureInterval: .seconds(5)
    )
    private var previewRefreshTask: Task<Void, Never>?
    private var previewRefreshGeneration = 0

    private init() {
        refresh()
        subscribe()
        subscribeToPermissions()
        subscribeToRegistry()
    }

    isolated deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
    }

    func isRunning(bundleIdentifier: String) -> Bool {
        runningByBundleID[bundleIdentifier] != nil
    }

    func isFrontmost(bundleIdentifier: String) -> Bool {
        frontmostBundleIdentifier == bundleIdentifier
    }

    func isHidden(bundleIdentifier: String) -> Bool {
        runningByBundleID[bundleIdentifier]?.isHidden == true
    }

    func minimizedWindowPreview(for window: AppWindow) -> NSImage? {
        minimizedWindowPreviews[window.windowIdentifier]
    }

    func activateOrOpen(bundleIdentifier: String) {
        guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            // Not running: launch it.
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                openApplication(at: appURL)
            }
            return
        }

        let accessibilityGranted = PermissionsService.shared.accessibility == .granted
        let allWindows = accessibilityGranted ? appWindows(bundleIdentifier: bundleIdentifier) : []
        let visibleWindows = allWindows.filter { !$0.isMinimized }
        let isFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier
            && !runningApp.isHidden

        // The registry lists windows on every Space, but only user windows.
        // Activate rather than reopen when WindowServer still knows a live
        // window the registry filtered out.
        if accessibilityGranted, allWindows.isEmpty {
            if hasUnlistedLiveWindow(pid: runningApp.processIdentifier) {
                runningApp.unhide()
                runningApp.activateTransferringFrontmost(options: [.activateAllWindows])
            } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                openApplication(at: appURL)
            }
            return
        }

        // No visible window on this Space: restore the most-recently-minimized
        // window, preferring one minimized here. When visible windows exist
        // only on other Spaces and nothing here is minimized, activating
        // below switches to them.
        let windowsOnActiveSpace = visibleWindows.filter(\.isOnActiveSpace)
        if accessibilityGranted, windowsOnActiveSpace.isEmpty {
            let minimizedForApp = minimizedWindows.filter { $0.bundleIdentifier == bundleIdentifier }
            if let target = minimizedForApp.last(where: \.isOnActiveSpace)
                ?? (visibleWindows.isEmpty ? minimizedForApp.last : nil) {
                _ = restoreMinimizedWindow(target)
                return
            }
        }

        // Already frontmost with at least one visible window here: apply user
        // preference. Windows on other Spaces are left alone, so cycling and
        // minimizing never act on a desktop the user can't see.
        if isFrontmost, !windowsOnActiveSpace.isEmpty {
            applyFrontmostAppTileClickBehavior(
                runningApp: runningApp,
                visibleWindows: windowsOnActiveSpace
            )
            return
        }

        // Default: bring the app forward.
        runningApp.unhide()
        runningApp.activateTransferringFrontmost(options: [.activateAllWindows])
    }

    /// Whether WindowServer knows a live, ordinary, off-screen window for
    /// `pid` that the registry didn't list (ordered-in filters stale
    /// closed-window entries).
    private func hasUnlistedLiveWindow(pid: pid_t) -> Bool {
        guard let entries = CGWindowListCopyWindowInfo([], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let connection = CGSMainConnectionID()
        return entries.contains { entry in
            guard (entry[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (entry[kCGWindowLayer as String] as? Int) == 0,
                  ((entry[kCGWindowAlpha as String] as? Double) ?? 0) > 0,
                  (entry[kCGWindowIsOnscreen as String] as? Bool) != true,
                  let windowID = entry[kCGWindowNumber as String] as? CGWindowID else {
                return false
            }
            return SLSWindowIsOrderedIn(connection, windowID)
        }
    }

    private func applyFrontmostAppTileClickBehavior(
        runningApp: NSRunningApplication,
        visibleWindows: [AppWindow]
    ) {
        let resolved = DockyPreferences.shared.appTileFrontmostClickBehavior

        switch resolved {
        case .none:
            return
        case .hide:
            runningApp.hide()
        case .cycleWindows:
            cycleFrontmostAppWindows(visibleWindows)
        case .minimizeAll:
            minimizeAllWindows(visibleWindows)
        }
    }

    private func cycleFrontmostAppWindows(_ visibleWindows: [AppWindow]) {
        guard visibleWindows.count > 1, let next = visibleWindows.last else { return }
        _ = focus(window: next)
    }

    private func minimizeAllWindows(_ visibleWindows: [AppWindow]) {
        for window in visibleWindows {
            _ = minimize(window: window)
        }
    }

    func open(fileURLs: [URL], withApplicationBundleIdentifier bundleIdentifier: String) {
        guard !fileURLs.isEmpty,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(fileURLs, withApplicationAt: appURL, configuration: configuration) { _, error in
            guard let error else {
                return
            }

            NSLog("[Docky] Failed to open dropped files with app %@: %@ (%@)", bundleIdentifier, fileURLs.map(\.path).joined(separator: ", "), error.localizedDescription)
        }
    }

    func appWindows(bundleIdentifier: String) -> [AppWindow] {
        WindowRegistry.shared.windows(forBundleIdentifier: bundleIdentifier)
    }

    func switchableWindows(forceRefresh: Bool = false) -> [AppWindow] {
        // Registry is event-driven; the cached snapshot is always fresh, so
        // `forceRefresh` is now a no-op kept for source-compat.
        _ = forceRefresh
        return WindowRegistry.shared.visible
    }

    func appWindowPreview(for window: AppWindow) -> NSImage? {
        appWindowPreviews[window.windowIdentifier]
    }

    func liveFocusPreviewImage(for window: AppWindow) async -> NSImage? {
        guard PermissionsService.shared.screenCapture == .granted else {
            return appWindowPreviews[window.windowIdentifier]
        }

        return await captureFullSizeAppWindowImage(for: window) ?? appWindowPreviews[window.windowIdentifier]
    }

    func startLiveFocusPreview(
        for window: AppWindow,
        onFrame: @escaping @MainActor (NSImage?) -> Void
    ) async -> Bool {
        stopLiveFocusPreview()
        let request = liveFocusPreviewRequest

        // ScreenCaptureKit streams no frames for windows on inactive Spaces or
        // minimized windows; returning false lets the caller poll SkyLight
        // captures instead.
        guard PermissionsService.shared.screenCapture == .granted,
              window.isOnActiveSpace, !window.isMinimized else {
            return false
        }

        do {
            let shareableContent = try await shareableContentIncludingOffscreenWindows()
            guard !Task.isCancelled, request == liveFocusPreviewRequest,
                  let shareableWindow = matchingShareableWindow(for: window, in: shareableContent.windows) else {
                return false
            }

            let session = LiveWindowPreviewSession(
                shareableWindow: shareableWindow,
                captureSize: fullSizeCaptureSize(for: shareableWindow.frame.size, screenBounds: window.screenBounds),
                onFrame: onFrame
            )
            liveFocusPreviewSession = session
            do {
                try await session.start()
            } catch {
                session.stop()
                if request == liveFocusPreviewRequest { liveFocusPreviewSession = nil }
                throw error
            }
            guard !Task.isCancelled, request == liveFocusPreviewRequest else {
                session.stop()
                if request == liveFocusPreviewRequest { liveFocusPreviewSession = nil }
                return false
            }
            return true
        } catch {
            NSLog("[Docky] Live focus preview stream failed for \(window.windowIdentifier): \(error.localizedDescription)")
            return false
        }
    }

    func stopLiveFocusPreview() {
        liveFocusPreviewRequest = UUID()
        liveFocusPreviewSession?.stop()
        liveFocusPreviewSession = nil
    }

    @discardableResult
    func focus(window: AppWindow) -> Bool {
        let didFocus = WindowRegistry.shared.focus(window)
        if didFocus {
            refreshPreviewAfterFocus(for: window)
        }
        return didFocus
    }

    /// Grabs a fresh thumbnail right after a window is focused so the
    /// switcher and hover popover show current content the next time they
    /// open, instead of a stale cached frame. The window is on screen and
    /// frontmost at this point, so this is the best chance for an accurate
    /// capture. Overwrites any cached preview unconditionally.
    private func refreshPreviewAfterFocus(for window: AppWindow) {
        guard PermissionsService.shared.screenCapture == .granted else {
            return
        }

        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.postFocusPreviewCaptureDelay)
            guard let preview = await self.captureAppWindowPreview(for: window) else { return }

            var updatedPreviews = self.appWindowPreviews
            updatedPreviews[window.windowIdentifier] = preview
            self.appWindowPreviews = updatedPreviews
            self.appWindowPreviewMetadata[window.windowIdentifier] = PreviewMetadata(
                capturedAt: Date(),
                capturedTitle: window.windowTitle
            )
            self.previewRefreshQueue.remove(window.windowIdentifier)

            // The window is no longer minimized; drop any stale minimized
            // thumbnail so it doesn't linger once the window is back up.
            if self.minimizedWindowPreviews[window.windowIdentifier] != nil {
                var minimized = self.minimizedWindowPreviews
                minimized.removeValue(forKey: window.windowIdentifier)
                self.minimizedWindowPreviews = minimized
            }
        }
    }

    func focusApplication(bundleIdentifier: String) {
        guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return
        }

        runningApp.unhide()
        runningApp.activateTransferringFrontmost()
    }

    @discardableResult
    func minimize(window: AppWindow) -> Bool {
        WindowRegistry.shared.minimize(window)
    }

    @discardableResult
    func close(window: AppWindow) -> Bool {
        WindowRegistry.shared.close(window)
    }

    // MARK: - Window geometry actions

    @discardableResult
    func zoom(window: AppWindow) -> Bool {
        let ok = WindowRegistry.shared.zoom(window)
        if ok { _ = focus(window: window) }
        return ok
    }

    @discardableResult
    func fill(window: AppWindow) -> Bool {
        guard let screen = currentScreen(for: window) else { return false }
        let ok = resize(window, toNSFrame: screen.visibleFrame)
        if ok { _ = focus(window: window) }
        return ok
    }

    @discardableResult
    func center(window: AppWindow) -> Bool {
        guard let screen = currentScreen(for: window),
              let size = window.frame?.size, size.width > 0, size.height > 0 else {
            return false
        }
        let v = screen.visibleFrame
        let target = CGRect(
            x: v.midX - size.width / 2,
            y: v.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let ok = resize(window, toNSFrame: target)
        if ok { _ = focus(window: window) }
        return ok
    }

    @discardableResult
    func fillLeftHalf(window: AppWindow) -> Bool {
        fillRect(of: window) { v in
            CGRect(x: v.minX, y: v.minY, width: v.width / 2, height: v.height)
        }
    }

    @discardableResult
    func fillRightHalf(window: AppWindow) -> Bool {
        fillRect(of: window) { v in
            CGRect(x: v.midX, y: v.minY, width: v.width / 2, height: v.height)
        }
    }

    @discardableResult
    func fillTopHalf(window: AppWindow) -> Bool {
        // NSScreen Y grows upward; "top half" sits at higher Y.
        fillRect(of: window) { v in
            CGRect(x: v.minX, y: v.midY, width: v.width, height: v.height / 2)
        }
    }

    @discardableResult
    func fillBottomHalf(window: AppWindow) -> Bool {
        fillRect(of: window) { v in
            CGRect(x: v.minX, y: v.minY, width: v.width, height: v.height / 2)
        }
    }

    @discardableResult
    func fillTopLeftQuarter(window: AppWindow) -> Bool {
        fillRect(of: window) { v in
            CGRect(x: v.minX, y: v.midY, width: v.width / 2, height: v.height / 2)
        }
    }

    @discardableResult
    func fillTopRightQuarter(window: AppWindow) -> Bool {
        fillRect(of: window) { v in
            CGRect(x: v.midX, y: v.midY, width: v.width / 2, height: v.height / 2)
        }
    }

    @discardableResult
    func fillBottomLeftQuarter(window: AppWindow) -> Bool {
        fillRect(of: window) { v in
            CGRect(x: v.minX, y: v.minY, width: v.width / 2, height: v.height / 2)
        }
    }

    @discardableResult
    func fillBottomRightQuarter(window: AppWindow) -> Bool {
        fillRect(of: window) { v in
            CGRect(x: v.midX, y: v.minY, width: v.width / 2, height: v.height / 2)
        }
    }

    private func fillRect(of window: AppWindow, _ make: (CGRect) -> CGRect) -> Bool {
        guard let screen = currentScreen(for: window) else { return false }
        let ok = resize(window, toNSFrame: make(screen.visibleFrame))
        if ok { _ = focus(window: window) }
        return ok
    }

    /// Tiles up to four windows on the screen of the first window (the
    /// "anchor"). Order matters: the first window in `windows` takes the
    /// first-named position in the layout (e.g., for `.leftRight`, windows[0]
    /// is the left half). Caller is expected to pass windows in the order
    /// the user understands as "first" (typically WindowRegistry MRU).
    @discardableResult
    func tile(windows: [AppWindow], layout: AppFolderTileLayout) -> Bool {
        guard windows.count >= 2,
              let screen = currentScreen(for: windows[0]) else { return false }
        let v = screen.visibleFrame
        let leftHalf = CGRect(x: v.minX, y: v.minY, width: v.width / 2, height: v.height)
        let rightHalf = CGRect(x: v.midX, y: v.minY, width: v.width / 2, height: v.height)
        let topHalf = CGRect(x: v.minX, y: v.midY, width: v.width, height: v.height / 2)
        let bottomHalf = CGRect(x: v.minX, y: v.minY, width: v.width, height: v.height / 2)
        let quarters: [CGRect] = [
            CGRect(x: v.minX, y: v.midY, width: v.width / 2, height: v.height / 2), // TL
            CGRect(x: v.midX, y: v.midY, width: v.width / 2, height: v.height / 2), // TR
            CGRect(x: v.minX, y: v.minY, width: v.width / 2, height: v.height / 2), // BL
            CGRect(x: v.midX, y: v.minY, width: v.width / 2, height: v.height / 2), // BR
        ]

        let placements: [(AppWindow, CGRect)]
        switch layout {
        case .leftRight:
            placements = [(windows[0], leftHalf), (windows[1], rightHalf)]
        case .rightLeft:
            placements = [(windows[0], rightHalf), (windows[1], leftHalf)]
        case .topBottom:
            placements = [(windows[0], topHalf), (windows[1], bottomHalf)]
        case .bottomTop:
            placements = [(windows[0], bottomHalf), (windows[1], topHalf)]
        case .quarters:
            let n = min(windows.count, 4)
            placements = (0..<n).map { (windows[$0], quarters[$0]) }
        }

        var allOk = true
        for (window, frame) in placements {
            allOk = resize(window, toNSFrame: frame) && allOk
        }
        // Focus in reverse so the first-in-the-layout-name window ends up
        // frontmost / key.
        for (window, _) in placements.reversed() {
            _ = focus(window: window)
        }
        return allOk
    }

    /// Routes an NSScreen-space target rect through the AX-space (Y-flipped
    /// against the primary display) coordinates that `WindowRegistry.resize`
    /// expects. Same flip used by `WindowReservationService`.
    private func resize(_ window: AppWindow, toNSFrame nsFrame: CGRect) -> Bool {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return false }
        let axFrame = CGRect(
            x: nsFrame.minX,
            y: primaryHeight - nsFrame.maxY,
            width: nsFrame.width,
            height: nsFrame.height
        )
        return WindowRegistry.shared.resize(window, to: axFrame)
    }

    /// Picks the NSScreen the window mostly occupies. Falls back to the main
    /// screen when AX has no frame for the window (some apps return zero).
    private func currentScreen(for window: AppWindow) -> NSScreen? {
        guard let axFrame = window.frame,
              let primaryHeight = NSScreen.screens.first?.frame.height else {
            return NSScreen.main
        }
        let nsFrame = CGRect(
            x: axFrame.minX,
            y: primaryHeight - axFrame.maxY,
            width: axFrame.width,
            height: axFrame.height
        )
        var best: (screen: NSScreen, area: CGFloat)?
        for screen in NSScreen.screens {
            let intersection = screen.frame.intersection(nsFrame)
            let area = intersection.width * intersection.height
            if area > 0, area > (best?.area ?? 0) {
                best = (screen, area)
            }
        }
        return best?.screen ?? NSScreen.main
    }

    private func openApplication(at appURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: configuration,
            completionHandler: nil
        )
    }

    func revealApplicationInFinder(bundleIdentifier: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([appURL])
    }

    func showAllWindows(bundleIdentifier: String) {
        guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return
        }

        runningApp.unhide()
        runningApp.activateTransferringFrontmost()
        // The Dock targets App Exposé at whatever app is frontmost when the
        // call arrives. The small delay lets activation land first so Exposé
        // surfaces the correct app's windows.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            CoreDockSendNotification("com.apple.expose.front.awake")
        }
    }

    @discardableResult
    func restoreMinimizedWindow(_ window: AppWindow) -> Bool {
        WindowRegistry.shared.focus(window)
    }

    @discardableResult
    func closeMinimizedWindow(_ window: AppWindow) -> Bool {
        WindowRegistry.shared.close(window)
    }

    func hide(bundleIdentifier: String) {
        guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return
        }

        runningApp.hide()
    }

    func quit(bundleIdentifier: String, force: Bool = false) {
        guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return
        }

        if force {
            runningApp.forceTerminate()
        } else {
            runningApp.terminate()
        }
    }

    func refresh() {
        // Docky is invisible to itself: filtering at this source removes
        // it from every downstream surface (dock tiles, settings pickers,
        // grouped running apps in folders, etc.) without needing per-site
        // exclusions. Matched by bundle ID so debug launches from Xcode
        // are filtered too.
        let dockyBundleID = Bundle.main.bundleIdentifier
        let regular = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != dockyBundleID
        }
        var newMap: [String: RunningApp] = [:]
        for app in regular {
            guard let bundleID = app.bundleIdentifier else { continue }
            newMap[bundleID] = RunningApp(
                bundleIdentifier: bundleID,
                localizedName: app.localizedName ?? bundleID,
                processIdentifier: app.processIdentifier,
                bundleURL: app.bundleURL,
                launchDate: app.launchDate,
                isHidden: app.isHidden
            )
        }

        let ordered = newMap.values.sorted(by: Self.byLaunchDate)

        runningByBundleID = newMap
        if runningApps != ordered {
            runningApps = ordered
        }
        refreshWindowDerivedState()
    }

    /// Oldest → newest. Apps without a launchDate (rare; system apps launched
    /// before our process) are treated as oldest. Bundle identifier is used
    /// as a deterministic tiebreaker.
    nonisolated private static func byLaunchDate(_ lhs: RunningApp, _ rhs: RunningApp) -> Bool {
        switch (lhs.launchDate, rhs.launchDate) {
        case let (l?, r?):
            return l == r
                ? lhs.bundleIdentifier < rhs.bundleIdentifier
                : l < r
        case (nil, _?): return true
        case (_?, nil): return false
        case (nil, nil): return lhs.bundleIdentifier < rhs.bundleIdentifier
        }
    }

    private func subscribe() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in names {
            let token = center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            }
            observers.append(token)
        }

        // Track the frontmost (foreground) app independently of the
        // running-apps list so the "active tile background" can paint
        // under just the focused tile, not every running one.
        let frontmostToken = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.updateFrontmost(app ?? NSWorkspace.shared.frontmostApplication)
            }
        }
        observers.append(frontmostToken)

        // Seed once so the first render after launch already reflects
        // whichever app was foreground when Docky came up.
        updateFrontmost(NSWorkspace.shared.frontmostApplication)
    }

    private func updateFrontmost(_ app: NSRunningApplication?) {
        let next = app?.bundleIdentifier
        guard next != frontmostBundleIdentifier else { return }
        frontmostBundleIdentifier = next
    }

    private func subscribeToPermissions() {
        PermissionsService.shared.$screenCapture
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshWindowDerivedState()
            }
            .store(in: &cancellables)
    }

    /// Mirrors the registry's window list into the published `minimizedWindows`
    /// array and drives preview captures. Called whenever the registry's
    /// snapshot, the running-apps list, or the screen-capture permission
    /// changes.
    ///
    /// Also re-runs the full `refresh()` so the published running-apps list
    /// catches apps whose `activationPolicy` promotes to `.regular` *after*
    /// `didLaunchApplicationNotification` (some apps launch as `.prohibited`
    /// or `.accessory` and only become dock-eligible once their first
    /// window appears). The `runningApps` setter is diff-guarded so this
    /// extra pass costs nothing when no app changed eligibility.
    private func subscribeToRegistry() {
        // The shareable-content cache only goes stale when windows come or
        // go, not on every move.
        var lastWindowIDs = Set<CGWindowID>()
        WindowRegistry.shared.$windows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] windows in
                MainActor.assumeIsolated {
                    let windowIDs = Set(windows.map(\.cgWindowID))
                    if windowIDs != lastWindowIDs {
                        lastWindowIDs = windowIDs
                        self?.previewContentCache.invalidate()
                    }
                    self?.refresh()
                }
            }
            .store(in: &cancellables)

        // Targeted preview invalidations from the registry: resize-aspect
        // changes and the outgoing window on focus switches. Fires more
        // often than the per-window TTL but only for the few windows
        // where the cached image is provably stale.
        WindowRegistry.shared.previewInvalidations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] windowIdentifier in
                self?.invalidateAppWindowPreview(windowIdentifier: windowIdentifier)
            }
            .store(in: &cancellables)
    }

    /// Recaptures one window's thumbnail ahead of stale ones, keeping the
    /// cached image until the new one arrives. Used by registry-driven
    /// invalidations (resize, focus-out), which know more than the TTL does
    /// about when a cached image stopped being representative. Windows
    /// without a thumbnail are already queued.
    private func invalidateAppWindowPreview(windowIdentifier: String) {
        guard PermissionsService.shared.screenCapture == .granted,
              appWindowPreviews[windowIdentifier] != nil else {
            return
        }
        previewRefreshQueue.enqueue(windowIdentifier, .invalidated)
        startPreviewRefreshesIfNeeded()
    }

    /// Debug-only: clear the "already attempted" set so every visible
    /// window is re-considered on the next refresh, then run the
    /// refresh immediately. Useful when the initial post-launch
    /// capture pass missed windows (e.g. permission was granted
    /// after refresh fired) and they're stuck without a thumbnail.
    func forceRefreshWindowPreviews() {
        attemptedAppWindowPreviewIDs.removeAll()
        attemptedMinimizedWindowPreviewIDs.removeAll()
        refreshWindowDerivedState()
    }

    private func refreshWindowDerivedState() {
        let registry = WindowRegistry.shared
        let nextMinimized = registry.minimized
        if nextMinimized != minimizedWindows {
            minimizedWindows = nextMinimized
        }
        refreshMinimizedWindowPreviews(for: nextMinimized)
        // Source set deliberately includes minimized windows so a
        // previously-captured preview survives the minimize event.
        // `refreshAppWindowPreviews` skips capture-attempts for
        // minimized windows but keeps any existing image around, so the
        // switcher / hover popover can show a stale-but-useful thumbnail
        // instead of nothing.
        refreshAppWindowPreviews(for: registry.switchable(includeMinimized: true))
    }

    private func refreshMinimizedWindowPreviews(for windows: [AppWindow]) {
        guard PermissionsService.shared.screenCapture == .granted else {
            if !minimizedWindowPreviews.isEmpty {
                minimizedWindowPreviews = [:]
            }
            attemptedMinimizedWindowPreviewIDs = []
            return
        }

        let activeWindowIdentifiers = Set(windows.map(\.windowIdentifier))
        var updatedPreviews = minimizedWindowPreviews
        var didChange = false

        for windowIdentifier in updatedPreviews.keys where !activeWindowIdentifiers.contains(windowIdentifier) {
            updatedPreviews.removeValue(forKey: windowIdentifier)
            didChange = true
        }

        attemptedMinimizedWindowPreviewIDs = attemptedMinimizedWindowPreviewIDs.intersection(activeWindowIdentifiers)

        for window in windows {
            guard updatedPreviews[window.windowIdentifier] == nil,
                  !attemptedMinimizedWindowPreviewIDs.contains(window.windowIdentifier) else {
                continue
            }

            attemptedMinimizedWindowPreviewIDs.insert(window.windowIdentifier)
            captureMinimizedWindowPreviewIfNeeded(for: window, attempt: 1)
        }

        if didChange {
            minimizedWindowPreviews = updatedPreviews
        }
    }

    private func captureMinimizedWindowPreviewIfNeeded(for window: AppWindow, attempt: Int) {
        Task { [weak self] in
            guard let self else { return }
            let preview = await self.captureMinimizedWindowPreview(for: window)

            // Bail if the window came back on screen while we were
            // capturing; `refreshMinimizedWindowPreviews` has already
            // pruned its id, so a new chain can start cleanly next time.
            guard self.minimizedWindows.contains(where: { $0.windowIdentifier == window.windowIdentifier }) else {
                return
            }

            if let preview {
                guard self.minimizedWindowPreviews[window.windowIdentifier] == nil else { return }
                var updatedPreviews = self.minimizedWindowPreviews
                updatedPreviews[window.windowIdentifier] = preview
                self.minimizedWindowPreviews = updatedPreviews
                return
            }

            // Capture missed (commonly a genie-animation race where the
            // offscreen content isn't ready yet). Retry a bounded number
            // of times before giving up instead of leaving the window
            // permanently thumbnail-less after a single miss.
            guard attempt < self.maxMinimizedPreviewAttempts else { return }
            try? await Task.sleep(for: self.minimizedPreviewRetryDelay)
            guard self.minimizedWindows.contains(where: { $0.windowIdentifier == window.windowIdentifier }),
                  self.minimizedWindowPreviews[window.windowIdentifier] == nil else {
                return
            }
            self.captureMinimizedWindowPreviewIfNeeded(for: window, attempt: attempt + 1)
        }
    }

    private func refreshAppWindowPreviews(for windows: [AppWindow]) {
        // Skip the capture path entirely without screen-recording
        // permission, saving CPU/GPU and avoiding private-API code
        // paths that would have nothing to render into.
        guard PermissionsService.shared.screenCapture == .granted else {
            if !appWindowPreviews.isEmpty {
                appWindowPreviews = [:]
            }
            appWindowPreviewMetadata.removeAll()
            attemptedAppWindowPreviewIDs = []
            previewRefreshQueue.removeAll()
            previewRefreshTask?.cancel()
            previewRefreshTask = nil
            return
        }

        let activeWindowIdentifiers = Set(windows.map(\.windowIdentifier))
        let removed = appWindowPreviews.keys.filter { !activeWindowIdentifiers.contains($0) }
        if !removed.isEmpty {
            var updatedPreviews = appWindowPreviews
            for windowIdentifier in removed {
                updatedPreviews.removeValue(forKey: windowIdentifier)
                appWindowPreviewMetadata.removeValue(forKey: windowIdentifier)
            }
            appWindowPreviews = updatedPreviews
        }
        attemptedAppWindowPreviewIDs = attemptedAppWindowPreviewIDs.intersection(activeWindowIdentifiers)
        previewRefreshQueue.retain(activeWindowIdentifiers)

        let now = Date()
        for window in windows {
            let identifier = window.windowIdentifier
            if appWindowPreviews[identifier] == nil {
                // One attempt per window; a failed capture isn't retried
                // until `forceRefreshWindowPreviews`.
                guard attemptedAppWindowPreviewIDs.insert(identifier).inserted else { continue }
                previewRefreshQueue.enqueue(identifier, .missing)
            } else if !window.isMinimized, let metadata = appWindowPreviewMetadata[identifier],
                      metadata.capturedTitle != window.windowTitle
                        || now.timeIntervalSince(metadata.capturedAt) > appWindowPreviewTTL {
                // Minimized windows keep their last thumbnail; their content
                // rarely changes while minimized.
                previewRefreshQueue.enqueue(identifier, .stale)
            }
        }
        startPreviewRefreshesIfNeeded()
    }

    private func startPreviewRefreshesIfNeeded() {
        guard previewRefreshTask == nil, !previewRefreshQueue.queued.isEmpty else { return }
        previewRefreshGeneration += 1
        let generation = previewRefreshGeneration
        previewRefreshTask = Task { [weak self] in
            await self?.runPreviewRefreshes()
            // A canceled worker must not clear its replacement.
            guard let self, self.previewRefreshGeneration == generation else { return }
            self.previewRefreshTask = nil
        }
    }

    /// Windows whose thumbnails may be captured now, in capture order:
    /// active-Space windows first, each group in MRU order. Windows on other
    /// Spaces wait until they're shown when the switcher and previews only
    /// list the active Space.
    private func previewRefreshCandidates() -> [AppWindow] {
        let windows = WindowRegistry.shared.switchable(includeMinimized: true)
        let onActiveSpace = windows.filter(\.isOnActiveSpace)
        guard DockyPreferences.shared.windowSwitcherSpaceScope == .allSpaces else { return onActiveSpace }
        return onActiveSpace + windows.filter { !$0.isOnActiveSpace }
    }

    /// Captures queued thumbnails one at a time. New thumbnails are published
    /// in batches at most every 250 ms; replacements as soon as they land.
    /// Exits when nothing it may capture is queued.
    private func runPreviewRefreshes() async {
        var captured: [String: NSImage] = [:]
        var lastPublish = ContinuousClock.now
        func publish() {
            guard !captured.isEmpty else { return }
            appWindowPreviews.merge(captured) { _, new in new }
            captured.removeAll()
            lastPublish = .now
        }
        defer { publish() }

        while !Task.isCancelled {
            let candidates = previewRefreshCandidates()
            switch previewRefreshQueue.next(in: candidates.map(\.windowIdentifier), now: .now) {
            case .idle:
                return
            case .wait(let until):
                publish()
                // Short naps, so a newly queued window doesn't wait out a
                // stale window's backoff.
                let nap = min(until, ContinuousClock.now + .milliseconds(250))
                do { try await Task.sleep(until: nap, clock: .continuous) } catch { return }
            case .capture(let identifier, let priority):
                guard let window = candidates.first(where: { $0.windowIdentifier == identifier }),
                      let preview = await captureAppWindowPreview(for: window),
                      WindowRegistry.shared.windows.contains(where: { $0.id == window.id }) else {
                    continue
                }
                captured[identifier] = preview
                appWindowPreviewMetadata[identifier] = PreviewMetadata(
                    capturedAt: Date(),
                    capturedTitle: window.windowTitle
                )
                if priority != .missing || !previewRefreshQueue.hasUrgentWork
                    || lastPublish.duration(to: .now) >= .milliseconds(250) {
                    publish()
                }
            }
        }
    }

    private func captureAppWindowPreview(for window: AppWindow) async -> NSImage? {
        guard PermissionsService.shared.screenCapture == .granted else {
            return nil
        }

        guard !Task.isCancelled,
              capturingWindowPreviewIDs.insert(window.windowIdentifier).inserted else { return nil }
        defer { capturingWindowPreviewIDs.remove(window.windowIdentifier) }

        guard let thumbnail = await captureThumbnail(of: window, maxSize: CGSize(width: 480, height: 300)) else {
            previewLogger.error(
                "App window preview capture failed for \(window.windowIdentifier, privacy: .public) title=\(window.windowTitle, privacy: .private)"
            )
            return nil
        }
        return thumbnail
    }

    private func captureFullSizeAppWindowImage(for window: AppWindow) async -> NSImage? {
        guard PermissionsService.shared.screenCapture == .granted else {
            return nil
        }
        // Backing pixels, capped like the live stream so a 6K window doesn't
        // allocate a full-resolution frame on every poll.
        let limit = fullSizeCaptureSize(
            for: window.frame?.size ?? CGSize(width: 4096, height: 2304),
            screenBounds: window.screenBounds
        )
        guard let cgImage = await captureWindowImage(
                window.cgWindowID, bestResolution: true, fitting: limit, on: focusCaptureQueue
              ) else {
            return nil
        }
        return makeFullSizeImage(from: cgImage)
    }

    private func captureMinimizedWindowPreview(for window: AppWindow) async -> NSImage? {
        guard PermissionsService.shared.screenCapture == .granted else {
            return nil
        }

        guard let thumbnail = await captureThumbnail(of: window, maxSize: CGSize(width: 320, height: 200)) else {
            previewLogger.error(
                "Minimized window preview capture failed for \(window.windowIdentifier, privacy: .public) title=\(window.windowTitle, privacy: .private)"
            )
            return nil
        }
        return thumbnail
    }

    /// A thumbnail at most `maxSize` points, with pixels for the window's
    /// display. Captures in points and scales down on the capture queue, so
    /// the main actor only wraps the result.
    private func captureThumbnail(of window: AppWindow, maxSize: CGSize) async -> NSImage? {
        let scale = backingScaleFactor(for: window.screenBounds)
        let pixelLimit = CGSize(width: maxSize.width * scale, height: maxSize.height * scale)
        guard let cgImage = await captureWindowImage(
                window.cgWindowID, bestResolution: false, fitting: pixelLimit, on: windowCaptureQueue
              ) else {
            return nil
        }
        // Point-resolution captures match the window's frame in points.
        let sourceSize = window.frame?.size ?? CGSize(width: cgImage.width, height: cgImage.height)
        let thumbnail = NSImage(
            cgImage: cgImage,
            size: WindowPreviewCaptureSizing.size(for: sourceSize, maximum: maxSize)
        )
        thumbnail.isTemplate = false
        return thumbnail
    }

    /// Captures a window's backing store through SkyLight on a background
    /// queue, because each capture blocks for tens of milliseconds, and scales
    /// it to fit `limit` pixels there. Unlike ScreenCaptureKit, this works for
    /// windows on inactive Spaces, minimized windows and hidden apps, and
    /// needs no shareable-content enumeration.
    private func captureWindowImage(
        _ windowID: CGWindowID,
        bestResolution: Bool,
        fitting limit: CGSize,
        on queue: DispatchQueue
    ) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async {
                let image = WindowServerWindows.captureImage(of: windowID, bestResolution: bestResolution)
                    .flatMap { WindowPreviewCaptureSizing.downscaled($0, toFit: limit) }
                continuation.resume(returning: image)
            }
        }
    }

    /// The live focus preview still streams through ScreenCaptureKit, which
    /// needs the window's `SCWindow`.
    private func matchingShareableWindow(for window: AppWindow, in windows: [SCWindow]) -> SCWindow? {
        windows.first { $0.windowID == window.cgWindowID }
    }

    private func shareableContentIncludingOffscreenWindows() async throws -> SCShareableContent {
        try await previewContentCache.current()
    }

    private func fullSizeCaptureSize(for sourceSize: CGSize, screenBounds: CGRect?) -> CGSize {
        WindowPreviewCaptureSizing.size(
            for: sourceSize, scale: backingScaleFactor(for: screenBounds),
            maximum: CGSize(width: 4096, height: 2304)
        )
    }

    private func backingScaleFactor(for screenBounds: CGRect?) -> CGFloat {
        guard let screenBounds else {
            return NSScreen.main?.backingScaleFactor ?? 2
        }

        let bestScreen = NSScreen.screens.max { lhs, rhs in
            intersectionArea(lhs.frame, with: screenBounds) < intersectionArea(rhs.frame, with: screenBounds)
        }

        return bestScreen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func intersectionArea(_ lhs: CGRect, with rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else {
            return 0
        }

        return intersection.width * intersection.height
    }

    private func makeFullSizeImage(from cgImage: CGImage) -> NSImage? {
        guard cgImage.width > 0, cgImage.height > 0 else {
            return nil
        }

        let image = NSImage(
            cgImage: cgImage,
            size: CGSize(width: cgImage.width, height: cgImage.height)
        )
        image.isTemplate = false
        return image
    }

}

@MainActor
private final class LiveWindowPreviewSession: NSObject, SCStreamOutput {
    private let stream: SCStream
    private let outputQueue = DispatchQueue(label: "Docky.LiveWindowPreview", qos: .userInteractive)
    nonisolated private let ciContext = CIContext(options: nil)
    private let onFrame: @MainActor (NSImage?) -> Void
    private var isStopped = false
    nonisolated private let frameGate = WindowPreviewFrameGate()

    init(
        shareableWindow: SCWindow,
        captureSize: CGSize,
        onFrame: @escaping @MainActor (NSImage?) -> Void
    ) {
        let configuration = SCStreamConfiguration()
        configuration.width = Int(captureSize.width)
        configuration.height = Int(captureSize.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 3
        configuration.capturesAudio = false
        if FeatureGate.shared.isAvailable(.streamMicrophoneCapture), #available(macOS 15.0, *) {
            configuration.captureMicrophone = false
        }
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true

        self.stream = SCStream(
            filter: SCContentFilter(desktopIndependentWindow: shareableWindow),
            configuration: configuration,
            delegate: nil
        )
        self.onFrame = onFrame

        super.init()
    }

    func start() async throws {
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        try await stream.startCapture()
        if isStopped {
            // stop() may have run while startCapture was suspended.
            try? await stream.stopCapture()
        }
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        frameGate.stop()

        try? stream.removeStreamOutput(self, type: .screen)
        Task {
            try? await stream.stopCapture()
        }
    }

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              attachments.first?[.status] as? Int == SCFrameStatus.complete.rawValue,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer), frameGate.beginFrame() else {
            return
        }

        let cgImage = autoreleasepool {
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let rect = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
            return ciContext.createCGImage(ciImage, from: rect)
        }
        guard let cgImage else {
            frameGate.endFrame()
            return
        }
        let gate = frameGate
        Task { @MainActor [weak self] in
            defer { gate.endFrame() }
            guard let self, !self.isStopped else { return }
            let image = NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
            image.isTemplate = false
            self.onFrame(image)
        }
    }
}
