#if DEBUG
    import AppKit
    import Combine
    import Darwin

    /// Exercises real window metadata, native selection, capture cancellation,
    /// the quick-tap path and the ⌘Tab takeover.
    /// Expected duration: 15 seconds. External runtime budget: 45 seconds.
    @MainActor
    enum WindowSwitcherRegression {
        private struct Failure: Error { let message: String }

        static func run() async {
            do {
                try await checkSwitcher()
                print("Window switcher integration regressions passed")
                fflush(stdout)
                exit(0)
            } catch {
                print("Window switcher regression failed: \(error)")
                fflush(stdout)
                exit(1)
            }
        }

        private static func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw Failure(message: message) }
        }

        private static func checkSwitcher() async throws {
            PermissionsService.shared.refresh()
            try check(PermissionsService.shared.accessibility == .granted, "Accessibility permission is required")
            try check(PermissionsService.shared.screenCapture == .granted, "Screen capture permission is required")
            let preferences = DockyPreferences.shared
            let enabled = preferences.enablesWindowSwitcher
            let previews = preferences.showsWindowSwitcherFocusPreview
            let mode = preferences.windowSwitcherPreviewMode
            let replacesCommandTab = preferences.replacesSystemCommandTab
            let keys = ["docky.enablesWindowSwitcher", "docky.showsWindowSwitcherFocusPreview",
                        "docky.windowSwitcherPreviewMode", "docky.windowSwitcherReplacesCommandTab"]
            let stored = keys.map { UserDefaults.standard.object(forKey: $0) }
            let frontmost = NSWorkspace.shared.frontmostApplication
            preferences.replacesSystemCommandTab = false
            let service = WindowSwitcherService.shared
            let browser = WindowSwitcherController()
            let window = NSWindow(contentViewController: browser)
            window.isReleasedWhenClosed = false
            window.setContentSize(CGSize(width: 1000, height: 650))
            defer {
                service.dismiss()
                window.contentViewController = nil
                window.close()
                preferences.enablesWindowSwitcher = enabled
                preferences.showsWindowSwitcherFocusPreview = previews
                preferences.windowSwitcherPreviewMode = mode
                preferences.replacesSystemCommandTab = replacesCommandTab
                SystemCommandTabService.shared.restore()
                for (key, value) in zip(keys, stored) {
                    if let value { UserDefaults.standard.set(value, forKey: key) } else {
                        UserDefaults.standard.removeObject(forKey: key)
                    }
                }
                frontmost?.activate()
            }
            preferences.enablesWindowSwitcher = true
            preferences.showsWindowSwitcherFocusPreview = true
            for previewMode in WindowSwitcherPreviewMode.allCases {
                preferences.windowSwitcherPreviewMode = previewMode
                window.orderFront(nil)
                try await checkPresentation(service, browser: browser, mode: previewMode)
                print("Checked switcher \(previewMode.rawValue)")
                fflush(stdout)
            }
            preferences.windowSwitcherPreviewMode = .inPlace
            try checkKeySwallowing(service)
            try await checkQuickTap(service)
            try await checkCommandTabOverride(preferences)
        }

        private static func checkPresentation(
            _ service: WindowSwitcherService, browser: WindowSwitcherController,
            mode: WindowSwitcherPreviewMode
        ) async throws {
            service.handleHotKeyPress(direction: 1)
            try check(!service.windows.isEmpty, "The desktop must have a switchable window")
            try check(!service.isRevealed, "The switcher must wait before appearing")
            try await Task.sleep(for: .milliseconds(200))
            try check(service.isRevealed, "Holding the shortcut must reveal the switcher")
            guard let selected = service.selectedWindowIdentifier else {
                throw Failure(message: "Switcher must select an initial window")
            }
            var selectionChanges = 0
            let subscription = service.$selectedWindowIdentifier.dropFirst().sink { _ in selectionChanges += 1 }
            defer { subscription.cancel() }
            for _ in 0..<100 {
                browser.refresh()
                service.selectWindow(withIdentifier: selected)
            }
            try await Task.sleep(for: .milliseconds(100))
            try check(selectionChanges == 0, "Reloading or reselecting must not publish new selections")
            try check(
                browser.cardViews[selected]?.isSelected == true,
                "The selected window's card must show the selection frame")
            if mode == .instantFocus, let window = service.windows.first(where: { $0.windowIdentifier == selected }) {
                try check(service.defersSelectionFocus == !window.isOnActiveSpace,
                          "Instant Focus must wait for release only for windows on other Spaces")
            }
            // Let the in-place stream start, then rapidly cancel and replace it.
            if mode == .inPlace {
                try await Task.sleep(for: .seconds(2))
                try check(service.focusedPreview != nil, "Holding a selection must produce a real preview")
            }
            let changes = mode == .instantFocus ? 2 : 30
            for _ in 0..<changes { service.moveSelection(delta: 1) }
            service.dismiss()
            try await Task.sleep(for: .milliseconds(300))
            try check(!service.isPresented && !service.isRevealed && service.focusedPreview == nil,
                      "Dismissed switchers must not receive stale capture frames")
        }

        /// With ⌘ held for ⌘Tab, keys the switcher doesn't use must not reach
        /// Docky's menu.
        private static func checkKeySwallowing(_ service: WindowSwitcherService) throws {
            let commandQ = try keyEvent(keyCode: 12, characters: "q", modifiers: .command)
            try check(!service.consumesKeyDown(commandQ), "Keys pass through while the switcher is closed")
            service.handleHotKeyPress(direction: 1)
            defer { service.dismiss() }
            try check(service.consumesKeyDown(commandQ), "The open switcher must swallow ⌘Q")
            try check(service.isPresented, "An unhandled key must not close the switcher")
        }

        /// Releasing the shortcut before the reveal delay switches without ever
        /// showing the switcher.
        private static func checkQuickTap(_ service: WindowSwitcherService) async throws {
            service.handleHotKeyPress(direction: 1)
            let target = service.windows.first { $0.windowIdentifier == service.selectedWindowIdentifier }
            service.confirmSelection()
            try await Task.sleep(for: .milliseconds(500))
            try check(!service.isPresented && !service.isRevealed, "A quick tap must never reveal the switcher")
            if let target, target.processIdentifier != getpid() {
                try check(
                    NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
                    "A quick tap must switch to the selected window")
            }
        }

        private static func checkCommandTabOverride(_ preferences: DockyPreferences) async throws {
            let bundleID = Bundle.main.bundleIdentifier ?? "gt.quintero.Docky"
            let otherDocky = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .contains { $0.processIdentifier != getpid() }
            let hotKeys = SystemSymbolicHotKey.allCases.map(\.rawValue)
            guard !otherDocky, hotKeys.allSatisfy({ CGSIsSymbolicHotKeyEnabled($0) }) else {
                print("Skipped ⌘Tab takeover check: another Docky or app owns ⌘Tab")
                fflush(stdout)
                return
            }

            let service = SystemCommandTabService.shared
            service.permitsOverride = true
            defer { service.permitsOverride = false }
            preferences.replacesSystemCommandTab = true
            try await Task.sleep(for: .milliseconds(200))
            try check(preferences.effectiveWindowSwitcherShortcut == .commandTab, "The switcher must listen for ⌘Tab")
            try check(SystemCommandTabService.shared.isOverridden, "Replacing ⌘Tab must override the system switcher")
            try check(
                hotKeys.allSatisfy { !CGSIsSymbolicHotKeyEnabled($0) },
                "Replacing ⌘Tab must turn off the system ⌘Tab and ⇧⌘Tab hotkeys")

            preferences.replacesSystemCommandTab = false
            try await Task.sleep(for: .milliseconds(200))
            try check(
                hotKeys.allSatisfy { CGSIsSymbolicHotKeyEnabled($0) },
                "Turning the setting off must give ⌘Tab back to macOS")
            print("Checked ⌘Tab takeover")
            fflush(stdout)
        }

        private static func keyEvent(
            keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags
        ) throws -> NSEvent {
            guard let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: 0, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)
            else {
                throw Failure(message: "Could not build a key event")
            }
            return event
        }
    }
#endif
