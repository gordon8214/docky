import AppKit
import Foundation

@MainActor
enum DockBridgeLoader {
    private static var loadedPID: pid_t?
    private static var failedPID: pid_t?
    private static var failureMessage: String?
    private static var loading: Task<Void, Error>?
    private static var loadingPID: pid_t?
    private static var loadingIdentity: UUID?
    private static var activeProcess: Process?

    static func load(into dockPID: pid_t) async throws {
        if loadedPID == dockPID { return }
        if failedPID == dockPID { throw failure(failureMessage ?? "Dock bridge authorization failed") }
        if loadingPID == dockPID, let loading {
            try await loading.value
            return
        }
        loading?.cancel()
        let identity = UUID()
        let task = Task { try await performLoad(into: dockPID) }
        loading = task
        loadingPID = dockPID
        loadingIdentity = identity
        defer {
            if loadingIdentity == identity {
                loading = nil
                loadingPID = nil
                loadingIdentity = nil
            }
        }
        try await task.value
    }

    private static func performLoad(into dockPID: pid_t) async throws {
        try Task.checkCancellation()
        let resources = Bundle.main.resourceURL?.appendingPathComponent("DockBridge")
        guard let resources else { throw failure("Dock bridge resources are missing") }
        let process = Process()
        process.executableURL = resources.appendingPathComponent("DockyDockLoader")
        process.arguments = [resources.appendingPathComponent("DockyDockBridge.dylib").path, String(dockPID)]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
            activeProcess = process
            defer {
                if process.isRunning { process.terminate() }
                if activeProcess === process { activeProcess = nil }
            }
            // The warm path takes about 100 ms. Allow time for macOS's first
            // debugger authorization prompt without blocking the app's UI.
            let deadline = ContinuousClock.now + .seconds(60)
            while process.isRunning {
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else {
                    throw failure("Authorize DockyDockLoader in the macOS prompt, then retry system Dock integration")
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            try Task.checkCancellation()
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                throw failure("Dock-side loader failed: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            loadedPID = dockPID
        } catch {
            if !Task.isCancelled {
                failedPID = dockPID
                failureMessage = error.localizedDescription
            }
            throw error
        }
    }

    static func resetFailure() {
        cancelPendingLoad()
        failedPID = nil
        loadedPID = nil
        failureMessage = nil
    }

    static func cancelPendingLoad() {
        loading?.cancel()
        loading = nil
        loadingPID = nil
        loadingIdentity = nil
        if let activeProcess, activeProcess.isRunning { activeProcess.terminate() }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "DockyDockLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
