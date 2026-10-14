import AppKit
import Combine

/// Native widget controls share the same services and per-placement settings as the Dock.
final class NativeWidgetView: NSView, NSSearchFieldDelegate {
    var tile: WidgetTile
    let expanded: Bool
    let span: TileSpan
    let stack = NSStackView()
    let scroll = NSScrollView()
    let document = NativeScrollDocumentView()
    var subscriptions = Set<AnyCancellable>()
    var configuredWeather: ConfiguredWeatherModel?
    var search: NativeSearchField?
    var showsLyrics = false
    override var isFlipped: Bool { true }
    init(tile: WidgetTile, cornerRadius: CGFloat, span: TileSpan, expanded: Bool = false) {
        self.tile = tile
        self.span = span
        self.expanded = expanded
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.secondarySystemFill.cgColor
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = expanded ? 8 : 3
        if expanded {
            scroll.documentView = document
            scroll.hasVerticalScroller = true
            scroll.drawsBackground = false
            document.addSubview(stack)
            addSubview(scroll)
        } else {
            addSubview(stack)
        }
        startObserving()
        refresh()
    }
    required init?(coder: NSCoder) { nil }
    func startObserving() {
        subscriptions.removeAll()
        let publisher: AnyPublisher<Void, Never>?
        switch tile.kind {
        case .calendar, .calendarDate:
            CalendarService.shared.ensureFreshEvent()
            publisher = CalendarService.shared.objectWillChange.eraseToAnyPublisher()
            Timer.publish(every: 60, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.refresh() }
                .store(in: &subscriptions)
        case .reminders:
            RemindersService.shared.ensureFreshReminders()
            publisher = RemindersService.shared.objectWillChange.eraseToAnyPublisher()
        case .batteries:
            BatteriesService.shared.ensureFreshBatteries()
            publisher = BatteriesService.shared.objectWillChange.eraseToAnyPublisher()
        case .systemStatus:
            SystemStatusService.shared.ensureFreshStatus()
            publisher = SystemStatusService.shared.objectWillChange.eraseToAnyPublisher()
        case .nowPlaying: publisher = MediaPlaybackService.shared.objectWillChange.eraseToAnyPublisher()
        case .weather:
            if let location = WeatherWidgetSettingsKey.configuredLocation(from: tile.settings) {
                let model = LocationWeatherStore.shared.model(for: location)
                configuredWeather = model
                model.ensureFreshWeather()
                publisher = model.objectWillChange.eraseToAnyPublisher()
            } else {
                WeatherService.shared.ensureFreshWeather()
                publisher = WeatherService.shared.objectWillChange.eraseToAnyPublisher()
            }
        case .photoFrame: publisher = PhotoFrameService.shared.objectWillChange.eraseToAnyPublisher()
        case .search, .external: publisher = nil
        }
        publisher?.sink { [weak self] in DispatchQueue.main.async { self?.refresh() } }.store(in: &subscriptions)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            subscriptions.removeAll()
        } else {
            startObserving()
            refresh()
        }
    }
    override func layout() {
        super.layout()
        if expanded {
            scroll.frame = bounds.insetBy(dx: 10, dy: 10)
            let width = max(0, scroll.contentSize.width - 8)
            for case let label as NSTextField in stack.arrangedSubviews { label.preferredMaxLayoutWidth = width }
            let height = max(scroll.contentSize.height, stack.fittingSize.height)
            document.frame = CGRect(x: 0, y: 0, width: scroll.contentSize.width, height: height)
            stack.frame = CGRect(x: 4, y: 0, width: width, height: height)
        } else {
            stack.frame = bounds.insetBy(dx: 5, dy: 4)
        }
        for view in stack.arrangedSubviews {
            if let image = view as? NSImageView {
                image.setContentHuggingPriority(.defaultLow, for: .vertical)
            }
        }
    }
    func clear() {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
    func add(_ view: NSView) {
        stack.addArrangedSubview(view)
        if view is NativeMediaPlaybackTimeline {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.secondarySystemFill.cgColor
        refresh()
    }
    func label(_ text: String, large: Bool = false, color: NSColor = .labelColor) {
        add(
            nativeLabel(
                text, size: large ? (expanded ? 24 : 15) : (expanded ? 13 : 10), weight: large ? .semibold : .regular,
                color: color))
    }
    func permission(
        _ title: String, for permission: Permission, status: PermissionStatus, action: @escaping () async -> Bool
    ) {
        label(title)
        let buttonTitle = status == .denied ? String(localized: "Open Settings") : String(localized: "Allow Access")
        add(NativeActionButton(buttonTitle) {
            if status == .denied {
                PermissionsService.shared.openSystemSettings(for: permission)
            } else {
                Task { _ = await action() }
            }
        })
    }
    func refresh() {
        if tile.kind == .search, search != nil { return }
        clear()
        let renderers: [String: () -> Void] = [
            "calendarDate": calendarDateContent,
            "calendar": calendarContent,
            "reminders": remindersContent,
            "batteries": batteriesContent,
            "systemStatus": systemStatusContent,
            "weather": weatherContent,
            "nowPlaying": mediaContent,
            "photoFrame": photoFrameContent,
            "search": searchContent
        ]
        (renderers[tile.kind.rawValue] ?? externalContent)()
        needsLayout = true
    }
    @objc func submitSearch() {
        guard let search else { return }
        guard var components = URLComponents(string: "https://www.google.com/search") else { return }
        components.queryItems = [URLQueryItem(name: "q", value: search.stringValue)]
        if let url = components.url { NSWorkspace.shared.open(url) }
        window?.makeFirstResponder(nil)
        (window as? any DockSearchFocusWindow)?.setSearchFocus(false)
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        (window as? any DockSearchFocusWindow)?.setSearchFocus(false)
    }
}
