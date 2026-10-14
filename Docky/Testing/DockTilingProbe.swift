#if DEBUG
import AppKit

/// Start before publication, then exercise native window actions afterward.
/// This verifies existing clients, rather than only freshly launched clients.
@MainActor
final class DockTilingProbe {
    private let process = Process()
    private let output = Pipe()
    private let signal = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("DockyTiling-\(UUID().uuidString)")

    static func start() async throws -> DockTilingProbe {
        let probe = DockTilingProbe()
        probe.process.executableURL = Bundle.main.bundleURL.appendingPathComponent(
            "Contents/Library/LoginItems/DockyDockWatchdog.app/Contents/MacOS/DockyDockWatchdog")
        probe.process.arguments = ["--window-behavior-probe", "--reservation-signal", probe.signal.path,
                                   "-ApplePersistenceIgnoreState", "YES"]
        probe.process.standardOutput = probe.output
        probe.process.standardError = probe.output
        try probe.process.run()
        do {
            let deadline = ContinuousClock.now + .seconds(5)
            while !FileManager.default.fileExists(atPath: probe.signal.appendingPathExtension("ready").path) {
                guard probe.process.isRunning, ContinuousClock.now < deadline else {
                    throw probe.failure("Native tiling fixture did not become ready within five seconds")
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            return probe
        } catch { probe.cleanup(); throw error }
    }

    func verifyAfterPublication() async throws {
        defer { cleanup() }
        try Data().write(to: signal, options: .atomic)
        let deadline = ContinuousClock.now + .seconds(5)
        while process.isRunning {
            guard ContinuousClock.now < deadline else { throw failure("Native tiling exceeded five seconds") }
            try await Task.sleep(for: .milliseconds(50))
        }
        let details = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        print(details)
        guard process.terminationStatus == 0 else { throw failure("Existing-client native tiling failed: \(details)") }
    }

    func cleanup() {
        if process.isRunning { process.terminate() }
        try? FileManager.default.removeItem(at: signal)
        try? FileManager.default.removeItem(at: signal.appendingPathExtension("ready"))
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "DockTilingProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
#endif
