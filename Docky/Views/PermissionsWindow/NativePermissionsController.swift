import AVFoundation
import AppKit
import Combine

final class NativePermissionsController: NSViewController {
    let steps: [Permission]
    var onComplete: (() -> Void)?
    private var index = 0
    private let stack = NSStackView()
    private let video = NativeLoopingPlayerView(frame: .zero)
    private var subscriptions = Set<AnyCancellable>()
    private var request: Task<Void, Never>?
    private var polling: AnyCancellable?
    private var continueButton: NSButton?
    init(steps: [Permission]) {
        self.steps = steps
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }
    override func loadView() {
        view = NSView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        view.addSubview(stack)
        video.heightAnchor.constraint(equalToConstant: 240).isActive = true
        renderStep()
    }
    override func viewDidAppear() {
        super.viewDidAppear()
        subscriptions.removeAll()
        PermissionsService.shared.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.refresh() } }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).sink { _ in
            PermissionsService.shared.refresh()
        }.store(in: &subscriptions)
        renderStep()
        polling = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard self?.view.window?.isVisible == true else { return }
            PermissionsService.shared.refresh()
        }
    }
    override func viewDidDisappear() {
        super.viewDidDisappear()
        request?.cancel()
        polling?.cancel()
        polling = nil
        video.configure(url: nil)
        subscriptions.removeAll()
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        stack.frame = view.bounds.insetBy(dx: 32, dy: 28)
    }
    private func renderStep() {
        for child in stack.arrangedSubviews {
            stack.removeArrangedSubview(child)
            child.removeFromSuperview()
        }
        guard steps.indices.contains(index) else {
            onComplete?()
            return
        }
        let permission = steps[index]
        stack.addArrangedSubview(nativeLabel(permission.title, size: 28, weight: .semibold))
        stack.addArrangedSubview(nativeLabel(permission.explanation))
        let resource: String?
        switch permission {
        case .userFolders: resource = "folder-preview"
        case .finderAutomation: resource = "trash"
        case .accessibility, .screenCapture: resource = "window-switching"
        case .systemEventsAutomation: resource = "automation"
        default: resource = nil
        }
        video.configure(url: resource.flatMap { Bundle.main.url(forResource: $0, withExtension: "mp4") })
        stack.addArrangedSubview(video)
        stack.addArrangedSubview(
            NativeActionButton(String(localized: "Grant Access")) { [weak self] in
                self?.request?.cancel()
                self?.request = Task { [weak self] in
                    _ = await PermissionsService.shared.requestPermission(for: permission)
                    self?.refresh()
                }
            })
        stack.addArrangedSubview(
            NativeActionButton(String(localized: "Open System Settings")) {
                PermissionsService.shared.openSystemSettings(for: permission)
            })
        addNavigation(for: permission)
        stack.addArrangedSubview(nativeLabel("\(index + 1) of \(steps.count)", size: 11, color: .secondaryLabelColor))
        view.needsLayout = true
    }
    private func addNavigation(for permission: Permission) {
        let next = NativeActionButton(String(localized: "Continue")) { [weak self] in self?.advance() }
        next.isEnabled = PermissionsService.shared.status(for: permission) == .granted
        continueButton = next
        let navigation = nativeStack(
            [
                NativeActionButton(String(localized: "Back")) { [weak self] in
                    guard let self, self.index > 0 else { return }
                    self.index -= 1
                    self.renderStep()
                },
                NativeActionButton(String(localized: "Skip")) { [weak self] in
                    PermissionsService.shared.markPermissionSkipped(permission)
                    self?.advance()
                },
                next,
                NativeActionButton(String(localized: "Quit Docky")) { NSApp.terminate(nil) }
            ], orientation: .horizontal)
        stack.addArrangedSubview(navigation)
    }
    private func refresh() {
        guard steps.indices.contains(index) else { return }
        let granted = PermissionsService.shared.status(for: steps[index]) == .granted
        continueButton?.isEnabled = granted
        if granted { advance() }
    }
    private func advance() {
        request?.cancel()
        index += 1
        if index == steps.count { onComplete?() } else { renderStep() }
    }
}

private final class NativeLoopingPlayerView: NSView {
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    override func makeBackingLayer() -> CALayer {
        AVPlayerLayer()
    }

    private var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            fatalError("Expected AVPlayerLayer backing layer")
        }
        return layer
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspectFill
    }

    override func layout() {
        super.layout()
        updateVideoRect()
    }

    func configure(url: URL?) {
        guard currentURL != url else { return }
        currentURL = url

        guard let url else {
            playerLayer.player = nil
            queuePlayer = nil
            looper = nil
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: item)
        queuePlayer = player
        playerLayer.player = player
        player.play()
    }

    private func updateVideoRect() {
        guard let presentationSize = playerLayer.player?.currentItem?.presentationSize,
            presentationSize.width > 0,
            presentationSize.height > 0,
            bounds.width > 0,
            bounds.height > 0
        else {
            playerLayer.frame = bounds
            return
        }

        let scale = max(bounds.width / presentationSize.width, bounds.height / presentationSize.height)
        let size = CGSize(width: presentationSize.width * scale, height: presentationSize.height * scale)
        let origin = CGPoint(x: (bounds.width - size.width) / 2, y: 0)
        playerLayer.frame = CGRect(origin: origin, size: size)
    }
}
