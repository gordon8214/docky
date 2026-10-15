#if DEBUG
    import AppKit
    import Combine
    import Darwin

    /// Exercises real window metadata, native selection, and capture cancellation.
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
            let layout = preferences.windowSwitcherLayout
            let keys = ["docky.enablesWindowSwitcher", "docky.showsWindowSwitcherFocusPreview",
                        "docky.windowSwitcherPreviewMode", "docky.windowSwitcherLayout"]
            let stored = keys.map { UserDefaults.standard.object(forKey: $0) }
            let frontmost = NSWorkspace.shared.frontmostApplication
            let service = WindowSwitcherService.shared
            let browser = NativeWindowBrowserController(source: .switcher)
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
                preferences.windowSwitcherLayout = layout
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
                for switcherLayout in [WindowSwitcherLayout.thumbnails, .list] {
                    preferences.windowSwitcherLayout = switcherLayout
                    window.orderFront(nil)
                    try await checkPresentation(service, browser: browser, mode: previewMode, layout: switcherLayout)
                    print("Checked switcher \(previewMode.rawValue), \(switcherLayout.rawValue)")
                    fflush(stdout)
                }
            }
        }

        private static func checkPresentation(
            _ service: WindowSwitcherService, browser: NativeWindowBrowserController,
            mode: WindowSwitcherPreviewMode, layout: WindowSwitcherLayout
        ) async throws {
            service.handleHotKeyPress(direction: 1)
            try check(!service.windows.isEmpty, "The desktop must have a switchable window")
            try await Task.sleep(for: .milliseconds(100))
            guard let selected = service.selectedWindowIdentifier else {
                throw Failure(message: "Switcher must select an initial window")
            }
            var selectionChanges = 0
            let subscription = service.$selectedWindowIdentifier.dropFirst().sink { _ in selectionChanges += 1 }
            defer { subscription.cancel() }
            for _ in 0..<100 {
                browser.reload()
                service.selectWindow(withIdentifier: selected)
            }
            try await Task.sleep(for: .milliseconds(100))
            try check(selectionChanges == 0, "Reloading or reselecting must not publish new selections")
            // Let the in-place stream start, then rapidly cancel and replace it.
            if mode == .inPlace, layout == .thumbnails {
                try await Task.sleep(for: .seconds(2))
                try check(service.focusedPreview != nil, "Holding a selection must produce a real preview")
            }
            let changes = mode == .instantFocus ? 2 : 30
            for _ in 0..<changes { service.moveSelection(delta: 1) }
            service.dismiss()
            try await Task.sleep(for: .milliseconds(300))
            try check(!service.isPresented && service.focusedPreview == nil,
                      "Dismissed switchers must not receive stale capture frames")
        }
    }
#endif
