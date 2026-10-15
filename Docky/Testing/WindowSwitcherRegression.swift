#if DEBUG
    import AppKit
    import Carbon
    import Combine
    import Darwin

    /// Exercises real window metadata, native selection, capture cancellation,
    /// the key above Tab, the quick-tap path, holding the shortcut to repeat
    /// and the ⌘Tab takeover.
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
            let shortcut = preferences.windowSwitcherShortcut
            let keys = ["docky.enablesWindowSwitcher", "docky.showsWindowSwitcherFocusPreview",
                        "docky.windowSwitcherPreviewMode", "docky.windowSwitcherReplacesCommandTab",
                        "docky.windowSwitcherShortcut"]
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
                preferences.windowSwitcherShortcut = shortcut
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
            // The default ⌥Tab, so a cleared or unusual saved shortcut can't skew the key checks.
            preferences.windowSwitcherShortcut = KeyboardShortcut(keyCode: 48, modifierFlags: [.option])
            for previewMode in WindowSwitcherPreviewMode.allCases {
                preferences.windowSwitcherPreviewMode = previewMode
                window.orderFront(nil)
                try await checkPresentation(service, browser: browser, mode: previewMode)
                print("Checked switcher \(previewMode.rawValue)")
                fflush(stdout)
            }
            preferences.windowSwitcherPreviewMode = .inPlace
            try checkKeySwallowing(service)
            try checkGraveKey(service)
            try await checkQuickTap(service)
            try await checkKeyRepeat(service)
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

        /// As in macOS's ⌘Tab, the grave key (`` ` ``) moves back and ⇧ flips
        /// it. The switcher claims the key only while it is open.
        private static func checkGraveKey(_ service: WindowSwitcherService) throws {
            let preferences = DockyPreferences.shared
            let shortcut = preferences.effectiveWindowSwitcherShortcut
            let flags = shortcut.carbonModifierFlags
            let actionKeys = [
                preferences.switcherMinimizeKeyCode, preferences.switcherCloseKeyCode, preferences.switcherZoomKeyCode
            ]
            service.handleHotKeyPress(direction: 1)
            defer { service.dismiss() }
            let identifiers = service.windows.map(\.windowIdentifier)
            guard identifiers.count >= 2, !actionKeys.contains(UInt16(kVK_ANSI_Grave)) else {
                print("Skipped ` check: it needs two windows and no action key on `")
                fflush(stdout)
                return
            }
            func selectedIndex() -> Int? {
                service.selectedWindowIdentifier.flatMap { identifiers.firstIndex(of: $0) }
            }

            try check(selectedIndex() == 1, "Opening forward must select the second window")
            service.handleGraveKeyPress(shifted: false)
            try check(selectedIndex() == 0, "` must move back")
            service.handleGraveKeyPress(shifted: false)
            try check(selectedIndex() == identifiers.count - 1, "` must wrap around to the last window")
            service.handleGraveKeyPress(shifted: true)
            try check(selectedIndex() == 0, "⇧` must move forward")
            let grave = try keyEvent(
                keyCode: UInt16(kVK_ANSI_Grave), characters: "`",
                modifiers: shortcut.modifierFlags.subtracting(.shift))
            try check(service.consumesKeyDown(grave), "The open switcher must swallow `")
            try check(selectedIndex() == identifiers.count - 1, "` reaching the switcher as a key press must move back")
            try check(!canRegisterGraveHotKey(modifiers: flags), "The open switcher must hold the ` hotkey")
            try check(!canRegisterGraveHotKey(modifiers: flags | UInt32(shiftKey)),
                      "The open switcher must hold the ⇧` hotkey")

            service.dismiss()
            service.handleGraveKeyPress(shifted: false)
            try check(!service.isPresented && service.selectedWindowIdentifier == nil,
                      "A ` press queued behind the release must not touch the closed switcher")
            try check(canRegisterGraveHotKey(modifiers: flags), "A closed switcher must leave ` to other apps")
            try check(canRegisterGraveHotKey(modifiers: flags | UInt32(shiftKey)),
                      "A closed switcher must leave ⇧` to other apps")
            print("Checked the grave key")
            fflush(stdout)
        }

        /// Carbon refuses a hotkey that is already registered, so this reports
        /// whether the switcher currently holds the grave key.
        private static func canRegisterGraveHotKey(modifiers: UInt32) -> Bool {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(kVK_ANSI_Grave), modifiers, EventHotKeyID(signature: OSType(0x444B5954), id: 1),
                GetApplicationEventTarget(), 0, &ref)
            if let ref { UnregisterEventHotKey(ref) }
            return status == noErr
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

        /// As in macOS's ⌘Tab, holding the shortcut keeps moving the selection
        /// after the system's key repeat delay until the key comes up. Real key
        /// events cover the Carbon hotkey's release, and ⌃⌥⌘Tab keeps a press
        /// the hotkey misses from typing into another app. The keys are down
        /// for about two seconds, so typing then can flip or add moves.
        private static func checkKeyRepeat(_ service: WindowSwitcherService) async throws {
            let delay = NSEvent.keyRepeatDelay
            let interval = NSEvent.keyRepeatInterval
            service.handleHotKeyPress(direction: 1)
            let windowCount = service.windows.count
            service.dismiss()
            guard windowCount >= 2, delay <= 2, interval <= 0.25 else {
                print("Skipped key repeat check: it needs two windows and key repeat turned on")
                fflush(stdout)
                return
            }

            let preferences = DockyPreferences.shared
            let shortcut = preferences.windowSwitcherShortcut
            preferences.windowSwitcherShortcut = KeyboardShortcut(keyCode: 48, modifierFlags: [.control, .option, .command])
            defer { preferences.windowSwitcherShortcut = shortcut }
            try await Task.sleep(for: .milliseconds(100))

            let modifiers: [(Int, CGEventFlags)] = [
                (kVK_Control, .maskControl), (kVK_Option, .maskAlternate), (kVK_Command, .maskCommand)
            ]
            var heldFlags: CGEventFlags = []
            var tabIsDown = false
            // Synthetic keys stay down until released, even after a failed check.
            func releaseKeys() {
                if tabIsDown { postKey(kVK_Tab, down: false, flags: heldFlags) }
                tabIsDown = false
                for (keyCode, flag) in modifiers.reversed() where heldFlags.contains(flag) {
                    heldFlags.remove(flag)
                    postKey(keyCode, down: false, flags: heldFlags)
                }
            }
            defer { releaseKeys() }
            for (keyCode, flag) in modifiers {
                heldFlags.insert(flag)
                postKey(keyCode, down: true, flags: heldFlags)
            }
            postKey(kVK_Tab, down: true, flags: heldFlags)
            tabIsDown = true

            // A busy Mac can take a moment to deliver the hotkey, and the
            // repeat delay starts once it arrives.
            let deadline = ContinuousClock.now + .seconds(1)
            while !service.isPresented, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            try check(service.isPresented, "Holding the shortcut must open the switcher")
            let identifiers = service.windows.map(\.windowIdentifier)
            func selectedIndex() -> Int? {
                service.selectedWindowIdentifier.flatMap { identifiers.firstIndex(of: $0) }
            }
            var moves = 0
            let subscription = service.$selectedWindowIdentifier.dropFirst().sink { _ in moves += 1 }
            defer { subscription.cancel() }

            try await Task.sleep(for: .seconds(delay / 2))
            try check(moves == 0 && selectedIndex() == 1, "Holding the shortcut must wait for the key repeat delay")
            try await Task.sleep(for: .seconds(delay / 2 + interval * 4))
            try check(moves >= 2, "Holding the shortcut must keep moving the selection")
            postKey(kVK_Tab, down: false, flags: heldFlags)
            tabIsDown = false
            try await Task.sleep(for: .seconds(max(interval * 3, 0.3)))
            let forward = moves
            try check(
                selectedIndex() == (1 + forward) % identifiers.count,
                "Holding the shortcut must move forward (\(forward) moves to \(String(describing: selectedIndex())) "
                    + "of \(identifiers.count))")
            try await Task.sleep(for: .seconds(interval * 4))
            try check(moves == forward, "Releasing the key must stop the repeat")
            try check(service.isPresented, "Releasing the key alone must keep the switcher open")

            // The grave key repeats backward, and releasing Tab after ` took
            // over leaves the grave key repeating. The modifiers stay down, so
            // a stray modifier event can't close the switcher meanwhile.
            service.beginKeyRepeat(for: .grave)
            try await Task.sleep(for: .seconds(delay + interval))
            service.endKeyRepeat(for: .shortcut)
            let beforeTabRelease = moves
            try await Task.sleep(for: .seconds(interval * 3))
            service.endKeyRepeat(for: .grave)
            try check(moves > beforeTabRelease, "Releasing Tab after ` took over must leave ` repeating")
            let back = moves - forward
            try check(
                selectedIndex() == ((1 + forward - back) % identifiers.count + identifiers.count) % identifiers.count,
                "Holding ` must move back")

            releaseKeys()
            try await Task.sleep(for: .milliseconds(300))
            try check(!service.isPresented, "Releasing the modifiers must close the switcher")
            print("Checked key repeat (\(forward) forward, \(back) back)")
            fflush(stdout)
        }

        private static func postKey(_ keyCode: Int, down: Bool, flags: CGEventFlags) {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
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
