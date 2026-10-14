#if DEBUG
    import AppKit
    import ApplicationServices

    @MainActor
    enum MenuExtrasProbe {
        static func run() async {
            print("Menu extras probe: AX=\(AXIsProcessTrusted()) capture=\(CGPreflightScreenCaptureAccess()) "
                  + "postEvents=\(CGPreflightPostEventAccess())")
            guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent")
                .first else { exit(2) }
            let displays = NSScreen.screens.compactMap { screen -> MenuExtraDisplay? in
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                else { return nil }
                return MenuExtraDisplay(id: number.uint32Value, frame: CGDisplayBounds(number.uint32Value))
            }
            let backend = MenuExtrasAccessibility()
            let items = await backend.snapshot(agentPID: agent.processIdentifier, displays: displays)
            print("Menu extras: \(items.count)")
            for item in items {
                print("\(item.label) pid=\(item.ownerPID) display=\(item.displayID) frame=\(item.frame)")
            }
            if ProcessInfo.processInfo.arguments.contains("--popup-diagnostics") {
                let owners = ["com.apple.controlcenter", "com.apple.MenuBarAgent"].flatMap {
                    NSRunningApplication.runningApplications(withBundleIdentifier: $0).map(\.processIdentifier)
                }
                for line in await backend.popupDiagnostics(ownerPIDs: owners) { print(line) }
            }
            if ProcessInfo.processInfo.arguments.contains("--capture-menu-extras"), let first = items.first {
                let region = items.filter { $0.displayID == first.displayID }.reduce(first.frame) {
                    $0.union($1.frame)
                }
                do {
                    let image = try await MenuExtrasCapture.image(in: region)
                    print("Capture: \(image.width)x\(image.height), region=\(region)")
                } catch {
                    print("Capture failed: \(error)")
                    fflush(stdout)
                    exit(3)
                }
            }
            fflush(stdout)
            exit(items.isEmpty ? 2 : 0)
        }
    }
#endif
