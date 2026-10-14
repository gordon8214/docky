import AppKit
import CoreAudio
import Network
import Observation

/// Observers are installed only while a taskbar status view is attached.
@MainActor
@Observable
final class WindowsTaskbarStatusService {
    static let shared = WindowsTaskbarStatusService()
    private(set) var networkSymbol = "network-offline"
    private(set) var networkDescription = "Network unavailable"
    private(set) var audioVolume: Float?
    private(set) var audioMuted = false
    private(set) var now = Date()
    @ObservationIgnored private var owners = Set<UUID>()
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private(set) var networkGeneration: UUID?
    private struct AudioObserver {
        let object: AudioObjectID
        var address: AudioObjectPropertyAddress
        let listener: AudioObjectPropertyListenerBlock
    }
    @ObservationIgnored private var audioObservers: [AudioObserver] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var outputDevice: AudioDeviceID = 0
    func attach(_ owner: UUID) {
        guard owners.insert(owner).inserted, owners.count == 1 else { return }
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        let generation = UUID()
        networkGeneration = generation
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let wifi = path.usesInterfaceType(.wifi)
            let symbol = connected ? (wifi ? "network-wifi" : "network-wired") : "network-offline"
            let description =
                connected ? (wifi ? "Wi-Fi connected" : "Network connected") : "Network disconnected"
            Task { @MainActor [weak self] in
                self?.applyNetwork(symbol: symbol, description: description, generation: generation)
            }
        }
        monitor.start(queue: DispatchQueue(label: "gt.quintero.Docky.taskbar-network"))
        watchAudio(
            object: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultOutputDevice)
        refreshAudio()
        refreshClock()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshClock()
                self?.refreshAudio()
            }
        }
    }
    func detach(_ owner: UUID) {
        owners.remove(owner)
        guard owners.isEmpty else { return }
        pathMonitor?.cancel()
        pathMonitor = nil
        networkGeneration = nil
        timer?.invalidate()
        timer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        removeAudioObservers()
        outputDevice = 0
    }
    func applyNetwork(symbol: String, description: String, generation: UUID) {
        guard networkGeneration == generation else { return }
        networkSymbol = symbol
        networkDescription = description
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
    private func watchAudio(object: AudioObjectID, selector: AudioObjectPropertySelector,
                            element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: selector == kAudioHardwarePropertyDefaultOutputDevice
                ? kAudioObjectPropertyScopeGlobal : kAudioDevicePropertyScopeOutput,
            mElement: element)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refreshAudio() }
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, .main, listener) == noErr {
            audioObservers.append(AudioObserver(object: object, address: address, listener: listener))
        }
    }
    private func removeAudioObservers() {
        for observer in audioObservers {
            var address = observer.address
            AudioObjectRemovePropertyListenerBlock(observer.object, &address, .main, observer.listener)
        }
        audioObservers.removeAll()
    }
    func refreshAudio() {
        guard !owners.isEmpty else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
            device != 0
        else {
            audioVolume = nil
            audioMuted = false
            return
        }
        if outputDevice != device {
            removeAudioObservers()
            outputDevice = device
            watchAudio(
                object: AudioObjectID(kAudioObjectSystemObject),
                selector: kAudioHardwarePropertyDefaultOutputDevice)
            for channel: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
                watchAudio(object: device, selector: kAudioDevicePropertyVolumeScalar, element: channel)
            }
            watchAudio(object: device, selector: kAudioDevicePropertyMute)
        }
        var mute = UInt32(0)
        address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        size = UInt32(MemoryLayout<UInt32>.size)
        audioMuted = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &mute) == noErr && mute != 0
        audioVolume = readVolume(device: device)
    }
    private func readVolume(device: AudioDeviceID) -> Float? {
        var levels: [Float] = []
        for channel: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput, mElement: channel)
            var volume = Float(0)
            var size = UInt32(MemoryLayout<Float>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr {
                levels.append(min(1, max(0, volume)))
                if channel == kAudioObjectPropertyElementMain { break }
            }
        }
        return levels.max() // Fixed-volume outputs expose neither main nor channel volume.

    }
    var audioDescription: String {
        if audioMuted { return "Volume muted" }
        if let audioVolume { return "Volume \(Int((audioVolume * 100).rounded())) percent" }
        return "Output volume unavailable"
    }
    static func openSettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
