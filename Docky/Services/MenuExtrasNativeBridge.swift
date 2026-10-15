import AppKit
import CryptoKit
import Observation
import Security

/// Opt-in native scene hosting. The host retains ownership of rendering and input.
@MainActor
@Observable
final class MenuExtrasNativeBridge {
    struct Placement {
        let item: MenuExtraSnapshot
        let destination: CGRect
    }

    static let shared = MenuExtrasNativeBridge()
    var enabled = ProcessInfo.processInfo.arguments.contains("--native-menu-extras")
        || UserDefaults.standard.bool(forKey: "nativeMenuExtras") {
        didSet { UserDefaults.standard.set(enabled, forKey: "nativeMenuExtras") }
    }
    private(set) var hostedIDs = Set<String>()
    private(set) var message = "Native menu extras are disabled"
    private(set) var isTracking = false
    @ObservationIgnored private var sources: [UUID: () -> [Placement]] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var loaded = Set<String>()
    @ObservationIgnored private var failed = Set<String>()
    @ObservationIgnored private var published = Set<URL>()
    @ObservationIgnored private let session = UUID().uuidString
    @ObservationIgnored private var activation: [String: Any]?
    @ObservationIgnored private var ownerRequests: [URL: (pid_t, [[String: Any]])] = [:]
    @ObservationIgnored private var trackingFiles = Set<URL>()
    @ObservationIgnored private var pendingActivationUntil = Date.distantPast

    /// Accessibility and keyboard activation enter the same native owner event path.
    func activate(_ item: MenuExtraSnapshot) -> Bool {
        guard enabled, hostedIDs.contains(item.id) else { return false }
        activation = ["id": item.id, "sequence": UUID().uuidString, "time": Date().timeIntervalSince1970]
        pendingActivationUntil = Date().addingTimeInterval(1)
        isTracking = true
        for (url, request) in ownerRequests where request.1.contains(where: { $0["id"] as? String == item.id }) {
            try? publish(request.1, to: url, ownerPID: request.0)
        }
        // System scenes render in the agent and retain their original AX action.
        // Publish its owner anchor before dispatching that action.
        if item.id.contains("com.apple.menuextra.") {
            return false
        }
        return true
    }

    func attach(_ owner: UUID, placements: @escaping () -> [Placement]) {
        guard !ProcessInfo.processInfo.arguments.contains("--appkit-ui-regression") else { return }
        sources[owner] = placements
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
    }

    func detach(_ owner: UUID) {
        sources.removeValue(forKey: owner)
        guard sources.isEmpty else { return }
        task?.cancel()
        task = nil
        clear()
    }

    private func clear() {
        for url in published { try? FileManager.default.removeItem(at: url) }
        published.removeAll()
        hostedIDs = []
        activation = nil
        ownerRequests.removeAll()
        trackingFiles.removeAll()
        pendingActivationUntil = .distantPast
        isTracking = false
    }

    private func tick() async {
        guard enabled else { clear(); message = "Native menu extras are disabled"; return }
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 else {
            clear(); message = "Native hosting requires macOS 27"; return
        }
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first
        else { clear(); message = "MenuBarAgent is unavailable"; return }
        let placements = Array(sources.values.flatMap { $0() }.reduce(into: [String: Placement]()) {
            $0[$1.item.id] = $1
        }.values)
        guard !placements.isEmpty else {
            clear(); message = "Native hosting paused while the taskbar is hidden"; return
        }
        isTracking = trackingActive() || placements.contains(where: {
            hostedIDs.contains($0.item.id) && $0.destination.contains(NSEvent.mouseLocation)
        })
        do {
            let directory = try cacheDirectory(for: agent)
            let stateURL = directory.appendingPathComponent("state.json")
            let items = placements.map { placement in
                entry(for: placement)
            }
            try publish(items, to: stateURL)
            try await load(into: agent, directory: directory)
            guard enabled, !Task.isCancelled else { clear(); return }
            let resultURL = directory.appendingPathComponent("result.json")
            guard let data = try? Data(contentsOf: resultURL),
                  let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  result["session"] as? String == session,
                  let expires = result["expires"] as? Double, expires > Date().timeIntervalSince1970,
                  let results = result["items"] as? [[String: Any]] else {
                hostedIDs = []; message = "Waiting for native scene hosts"; return
            }
            let requested = Set(placements.map { $0.item.id })
            hostedIDs = Set(results.compactMap { $0["id"] as? String }).intersection(requested)
            message = "Native menu extras: \(hostedIDs.count) of \(placements.count)"
            let originalAnchors = await updateOwners(placements, results: results, agentPID: agent.processIdentifier)
            if originalAnchors {
                message += "; some owners keep their original popup anchors"
            }
        } catch {
            clear()
            message = "Native hosting unavailable: \(error.localizedDescription)"
        }
    }

    private func updateOwners(_ placements: [Placement], results: [[String: Any]], agentPID: pid_t) async -> Bool {
        var originalAnchors = false
        let identifiers = results.reduce(into: [String: String]()) { values, result in
            if let key = result["id"] as? String, let persistent = result["persistentID"] as? String {
                values[key] = persistent
            }
        }
        let systemOwner = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter")
            .first?.processIdentifier
        let groups = Dictionary(grouping: placements, by: {
            $0.item.ownerPID == agentPID ? (systemOwner ?? agentPID) : $0.item.ownerPID
        })
        for (pid, group) in groups {
            guard let owner = NSRunningApplication(processIdentifier: pid), owner.bundleIdentifier != nil
            else { continue }
            if failed.contains(processIdentity(owner)) { originalAnchors = true; continue }
            do {
                let directory = try cacheDirectory(for: owner)
                let items = group.compactMap { placement -> [String: Any]? in
                    guard let identifier = identifiers[placement.item.id], !identifier.isEmpty else { return nil }
                    var value = entry(for: placement)
                    value["persistentID"] = identifier
                    return value
                }
                guard !items.isEmpty else { continue }
                let requestURL = directory.appendingPathComponent("owner-\(pid).json")
                ownerRequests[requestURL] = (pid, items)
                try publish(items, to: requestURL, ownerPID: pid)
                trackingFiles.insert(directory.appendingPathComponent("tracking-\(pid).json"))
                try await load(into: owner, directory: directory)
            } catch {
                // A rejected owner retains its original menu anchor.
                failed.insert(processIdentity(owner))
                originalAnchors = true
                NSLog("Native menu owner %d: %@", pid, error.localizedDescription)
            }
        }
        return originalAnchors
    }

    private func trackingActive() -> Bool {
        pendingActivationUntil > Date() || trackingFiles.contains { url in
            guard let data = try? Data(contentsOf: url),
                  let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  state["session"] as? String == session,
                  let expires = state["expires"] as? Double else { return false }
            return expires > Date().timeIntervalSince1970 && expires < Date().timeIntervalSince1970 + 2
        }
    }

    private func processIdentity(_ owner: NSRunningApplication) -> String {
        "\(owner.processIdentifier):\(owner.launchDate?.timeIntervalSince1970 ?? 0)"
    }

    private func entry(for placement: Placement) -> [String: Any] {
        let item = placement.item
        let identifier = item.id.split(separator: ":").dropFirst(2).dropLast().joined(separator: ":")
        return ["id": item.id, "identifier": identifier, "ownerPID": item.ownerPID, "source": components(item.frame),
                "destination": components(placement.destination), "system": item.id.contains("com.apple.menuextra."),
                "eventTag": eventTag(for: item.id)]
    }

    private func eventTag(for identifier: String) -> Int {
        let digest = SHA256.hash(data: Data(identifier.utf8))
        let suffix = digest.prefix(3).reduce(0) { ($0 << 8) | Int($1) }
        return 0x4400_0000 | suffix
    }

    private func components(_ rect: CGRect) -> [Double] {
        [rect.origin.x, rect.origin.y, rect.width, rect.height].map(Double.init)
    }

    private func publish(_ items: [[String: Any]], to url: URL, ownerPID: pid_t? = nil) throws {
        var state: [String: Any] = ["version": 1, "pid": ProcessInfo.processInfo.processIdentifier,
                                    "session": session, "expires": Date().timeIntervalSince1970 + 3,
                                    "items": items,
                                    "dark": NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua]
        if let ownerPID { state["ownerPID"] = ownerPID }
        if let activation { state["activation"] = activation }
        let data = try JSONSerialization.data(withJSONObject: state)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        published.insert(url)
    }

    private func cacheDirectory(for app: NSRunningApplication) throws -> URL {
        guard let identifier = app.bundleIdentifier else { throw failure("The owner has no bundle identifier") }
        var code: SecCode?
        var info: CFDictionary?
        var staticCode: SecStaticCode?
        let attributes = [kSecGuestAttributePid as String: app.processIdentifier] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
                == errSecSuccess
        else { throw failure("Cannot inspect the menu-extra owner's signature") }
        let signing = info as? [String: Any]
        let entitlements = signing?[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        var home = FileManager.default.homeDirectoryForCurrentUser
        if entitlements?["com.apple.security.app-sandbox"] as? Bool == true {
            home.appendPathComponent("Library/Containers/\(identifier)/Data", isDirectory: true)
        }
        let directory = home.appendingPathComponent("Library/Caches/DockyNativeMenuBridge", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        return directory
    }

    private func load(into owner: NSRunningApplication, directory: URL) async throws {
        let identity = processIdentity(owner)
        if loaded.contains(identity) { return }
        guard !failed.contains(identity) else { throw failure("The native loader rejected this owner") }
        guard let resources = Bundle.main.resourceURL?.appendingPathComponent("MenuBridge"),
              let bundle = owner.bundleIdentifier else { throw failure("Native menu resources are missing") }
        let data = try Data(contentsOf: resources.appendingPathComponent("DockyMenuBridge.dylib"))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let image = directory.appendingPathComponent("DockyMenuBridge-\(digest).dylib")
        if !FileManager.default.fileExists(atPath: image.path) { try data.write(to: image, options: .atomic) }
        let process = Process()
        process.executableURL = resources.appendingPathComponent("DockyMenuLoader")
        process.arguments = [image.path, String(owner.processIdentifier), bundle]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
            defer { if process.isRunning { process.terminate() } }
            let deadline = ContinuousClock.now + .seconds(5)
            while process.isRunning {
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else { throw failure("Native menu loader timed out") }
                try await Task.sleep(for: .milliseconds(25))
            }
            try Task.checkCancellation()
            let output = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                throw failure(output.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            loaded.insert(identity)
        } catch {
            if !Task.isCancelled { failed.insert(identity) }
            throw error
        }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "DockyNativeMenus", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
