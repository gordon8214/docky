import AppKit
import Observation

/// The clock runs only while a taskbar status view is attached.
@MainActor
@Observable
final class WindowsTaskbarStatusService {
    static let shared = WindowsTaskbarStatusService()
    private(set) var now = Date()
    @ObservationIgnored private var owners = Set<UUID>()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    func attach(_ owner: UUID) {
        guard owners.insert(owner).inserted, owners.count == 1 else { return }
        refreshClock()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshClock() }
        }
    }

    func detach(_ owner: UUID) {
        owners.remove(owner)
        guard owners.isEmpty else { return }
        timer?.invalidate()
        timer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    private func refreshClock() {
        now = Date()
        timer?.invalidate()
        let next = floor(now.timeIntervalSince1970 / 60) * 60 + 60
        timer = Timer(fire: Date(timeIntervalSince1970: next), interval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
}
