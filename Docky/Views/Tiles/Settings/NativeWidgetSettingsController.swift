import AppKit
import Combine
import MapKit

final class NativeWidgetSettingsController: NSViewController, NSSearchFieldDelegate {
    private let tileID: String
    private let widget: WidgetTile
    private let stack = NSStackView()
    private let resultStack = NSStackView()
    private let locationLabel = nativeLabel("")
    private let calendarSection = NSStackView()
    private let mediaPicker = NSPopUpButton()
    private var mediaChoices: [MediaAppChoice] = []
    private let scroll = NSScrollView()
    private let document = NativeScrollDocumentView()
    private var searchTask: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()
    /// Targets for the calendar checkboxes, which are rebuilt when access changes.
    private var calendarTargets: [NativeControlAction] = []
    var onDone: (() -> Void)?
    init(tileID: String, widget: WidgetTile) {
        self.tileID = tileID
        self.widget = widget
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }
    override func loadView() {
        let material = NSVisualEffectView()
        material.material = .popover
        view = material
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = document
        document.addSubview(stack)
        view.addSubview(scroll)
        stack.addArrangedSubview(
            nativeStack(
                [
                    nativeLabel(widget.kind.title, size: 17, weight: .semibold),
                    NativeActionButton(String(localized: "Done")) { [weak self] in self?.onDone?() }
                ], orientation: .horizontal))
        switch widget.kind {
        case .calendar:
            calendarSection.orientation = .vertical
            calendarSection.alignment = .leading
            stack.addArrangedSubview(calendarSection)
            calendarControls()
        case .weather: weatherControls()
        case .nowPlaying: mediaControls()
        default: break
        }
        if widget.kind == .nowPlaying {
            MediaPlaybackService.shared.objectWillChange.sink { [weak self] in
                DispatchQueue.main.async { self?.updateMediaChoices() }
            }.store(in: &subscriptions)
        }
        preferredContentSize = CGSize(width: 380, height: min(440, max(160, stack.fittingSize.height)))
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        scroll.frame = view.bounds
        let height = max(scroll.contentSize.height, stack.fittingSize.height)
        document.frame = CGRect(x: 0, y: 0, width: scroll.contentSize.width, height: height)
        stack.frame = document.bounds
    }
    override func viewDidDisappear() {
        super.viewDidDisappear()
        searchTask?.cancel()
    }
    private func set(_ key: String, _ value: WidgetSettingValue?) {
        TileStore.shared.setWidgetSetting(tileID: tileID, key: key, value: value)
    }
    private func calendarControls() {
        for view in calendarSection.arrangedSubviews {
            calendarSection.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        calendarTargets = []
        defer { self.view.needsLayout = true }
        let service = CalendarService.shared
        if service.permissionStatus != .granted {
            calendarSection.addArrangedSubview(
                NativeActionButton(String(localized: "Enable Calendar Access")) { [weak self] in
                    Task {
                        _ = await service.requestAccess()
                        self?.calendarControls()
                    }
                })
            return
        }
        calendarSection.addArrangedSubview(nativeLabel(String(localized: "Show events from")))
        for choice in service.availableCalendars() {
            let selected = Set(
                TileStore.shared.widgetSettings(tileID: tileID)?.stringList("calendar.calendarIDs") ?? [])
            let button = NSButton(checkboxWithTitle: choice.title, target: nil, action: nil)
            button.state = selected.contains(choice.identifier) ? .on : .off
            let target = NativeControlAction { [weak self, weak button] in
                guard let self, let button else { return }
                var ids = Set(
                    TileStore.shared.widgetSettings(tileID: self.tileID)?.stringList("calendar.calendarIDs") ?? [])
                if button.state == .on { ids.insert(choice.identifier) } else { ids.remove(choice.identifier) }
                self.set("calendar.calendarIDs", ids.isEmpty ? nil : .stringList(ids.sorted()))
            }
            calendarTargets.append(target)
            button.target = target
            button.action = #selector(NativeControlAction.invoke(_:))
            calendarSection.addArrangedSubview(button)
        }
        calendarSection.addArrangedSubview(
            nativeLabel(
                String(localized: "All calendars are shown when none are selected."), size: 11,
                color: .secondaryLabelColor))
    }
    private func mediaControls() {
        let row = NativeFormRow(title: String(localized: "Media App"), control: mediaPicker)
        row.bind(mediaPicker) { [weak self] in
            guard let self else { return }
            let index = self.mediaPicker.indexOfSelectedItem - 1
            self.set("nowPlaying.appBundleIdentifier",
                self.mediaChoices.indices.contains(index) ? .string(self.mediaChoices[index].bundleIdentifier) : nil)
        }
        stack.addArrangedSubview(row)
        updateMediaChoices()
    }
    private func updateMediaChoices() {
        var apps = MediaPlaybackService.shared.availableMediaApps()
        let stored = TileStore.shared.widgetSettings(tileID: tileID)?.string("nowPlaying.appBundleIdentifier")
        if let stored, !apps.contains(where: { $0.bundleIdentifier == stored }) {
            apps.insert(MediaAppChoice(bundleIdentifier: stored, displayName: stored), at: 0)
        }
        guard apps != mediaChoices || mediaPicker.numberOfItems == 0 else { return }
        mediaChoices = apps
        mediaPicker.removeAllItems()
        mediaPicker.addItems(withTitles: [String(localized: "Automatic")] + apps.map(\.displayName))
        mediaPicker.selectItem(
            at: stored.flatMap { value in apps.firstIndex(where: { $0.bundleIdentifier == value }).map { $0 + 1 } } ?? 0
        )
    }
    private func weatherControls() {
        locationLabel.stringValue =
            WeatherWidgetSettingsKey.configuredLocation(from: widget.settings)?.name
            ?? String(localized: "Current Location")
        stack.addArrangedSubview(locationLabel)
        stack.addArrangedSubview(
            NativeActionButton(String(localized: "Use Current Location")) { [weak self] in
                guard let self else { return }
                var settings = TileStore.shared.widgetSettings(tileID: self.tileID) ?? [:]
                for key in [
                    WeatherWidgetSettingsKey.latitude, WeatherWidgetSettingsKey.longitude,
                    WeatherWidgetSettingsKey.locationName
                ] { settings.removeValue(forKey: key) }
                TileStore.shared.setWidgetSettings(tileID: self.tileID, settings: settings)
                self.locationLabel.stringValue = String(localized: "Current Location")
            })
        let search = NSSearchField()
        search.placeholderString = String(localized: "Search City")
        search.delegate = self
        stack.addArrangedSubview(search)
        resultStack.orientation = .vertical
        resultStack.alignment = .leading
        stack.addArrangedSubview(resultStack)
        let picker = NSPopUpButton()
        picker.addItems(withTitles: [String(localized: "Automatic"), "°C", "°F"])
        let units: [WeatherTemperatureUnitSelection] = [.automatic, .celsius, .fahrenheit]
        picker.selectItem(
            at: units.firstIndex(of: WeatherWidgetSettingsKey.temperatureUnitSelection(from: widget.settings)) ?? 0)
        let row = NativeFormRow(title: String(localized: "Temperature"), control: picker)
        row.bind(picker) { [weak self] in
            self?.set(
                WeatherWidgetSettingsKey.temperatureUnit,
                picker.indexOfSelectedItem == 0 ? nil : .string(units[picker.indexOfSelectedItem].rawValue))
        }
        stack.addArrangedSubview(row)
    }
    func controlTextDidChange(_ notification: Notification) {
        guard let search = notification.object as? NSSearchField else { return }
        searchTask?.cancel()
        let query = search.stringValue
        searchTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            let results = await WeatherLocationSearch.search(query: query)
            guard let self, !Task.isCancelled, search.stringValue == query else { return }
            for view in self.resultStack.arrangedSubviews {
                self.resultStack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            for result in results {
                let title = [result.name, result.subtitle].compactMap { $0 }.joined(separator: " — ")
                self.resultStack.addArrangedSubview(
                    NativeActionButton(title) { [weak self] in
                        guard let self else { return }
                        var settings = TileStore.shared.widgetSettings(tileID: self.tileID) ?? [:]
                        settings[WeatherWidgetSettingsKey.locationName] = .string(result.name)
                        settings[WeatherWidgetSettingsKey.latitude] = .number(result.latitude)
                        settings[WeatherWidgetSettingsKey.longitude] = .number(result.longitude)
                        TileStore.shared.setWidgetSettings(tileID: self.tileID, settings: settings)
                        self.locationLabel.stringValue = result.name
                    })
            }
            self.view.needsLayout = true
        }
    }
}
