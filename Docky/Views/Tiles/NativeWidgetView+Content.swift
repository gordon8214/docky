import AppKit

extension NativeWidgetView {
    func calendarDateContent() {
        label(Date().formatted(.dateTime.weekday(.abbreviated)), color: .systemRed)
        label(Date().formatted(.dateTime.day()), large: true)
    }

    func calendarContent() {
        let service = CalendarService.shared
        guard service.permissionStatus == .granted else {
            permission(String(localized: "Calendar"), for: .calendar, status: service.permissionStatus) {
                await service.requestAccess()
            }
            return
        }
        let selected = Set(tile.settings.stringList("calendar.calendarIDs") ?? [])
        let events = service.upcomingEvents.filter { selected.isEmpty || selected.contains($0.calendarIdentifier) }
        calendarEventsContent(events)
    }
    func calendarEventsContent(_ events: [CalendarEventSnapshot], now: Date = Date()) {
        if events.isEmpty {
            label(String(localized: "No upcoming events"))
            return
        }
        let visibleEvents =
            !expanded && span == .one
            ? [events.first(where: { !$0.isAllDay }) ?? events[0]] : Array(events.prefix(expanded ? 12 : 2))
        var previousDay: Date?
        for event in visibleEvents {
            let day = Calendar.autoupdatingCurrent.startOfDay(for: event.startDate)
            if expanded, day != previousDay {
                label(calendarDayTitle(day, now: now), large: true)
                previousDay = day
            }
            let time = calendarSchedule(event, now: now)
            label(time, color: event.color)
            if expanded {
                add(NativeCalendarEventButton(event: event))
            } else {
                label(event.title, large: span != .one)
            }
            if expanded {
                if !event.location.isEmpty { label(event.location, color: .secondaryLabelColor) }
                if let url = event.quickJoinURL {
                    add(NativeActionButton(String(localized: "Quick Join")) { NSWorkspace.shared.open(url) })
                }
            }
        }
    }
    func calendarDayTitle(_ date: Date, now: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
            calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "Tomorrow")
        }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
    func calendarSchedule(_ event: CalendarEventSnapshot, now: Date) -> String {
        var text = event.isAllDay
            ? String(localized: "All Day") : event.startDate.formatted(date: .omitted, time: .shortened)
        if expanded, !event.isAllDay {
            let sameDay = Calendar.autoupdatingCurrent.isDate(event.startDate, inSameDayAs: event.endDate)
            text += " – " + event.endDate.formatted(date: sameDay ? .omitted : .abbreviated, time: .shortened)
        } else if !expanded, !Calendar.autoupdatingCurrent.isDate(event.startDate, inSameDayAs: now) {
            text = calendarDayTitle(event.startDate, now: now) + " · " + text
        }
        return text
    }

    func remindersContent() {
        let service = RemindersService.shared
        guard service.permissionStatus == .granted else {
            permission(String(localized: "Reminders"), for: .reminders, status: service.permissionStatus) {
                await service.requestAccess()
            }
            return
        }
        if let snapshot = service.snapshot, !snapshot.isEmpty {
            if span == .one && !expanded {
                label(String(snapshot.totalCount), large: true)
            } else {
                for item in snapshot.items.prefix(expanded ? 20 : 2) {
                    let button = NativeActionButton(item.title) {
                        Task { _ = await service.completeReminder(identifier: item.identifier) }
                    }
                    button.bezelStyle = .inline
                    add(button)
                    if expanded, let due = item.dueDate { label(due.formatted(), color: .secondaryLabelColor) }
                }
            }
        } else {
            label(String(localized: "No reminders"))
        }
    }

    func batteriesContent() {
        let devices = BatteriesService.shared.snapshot?.devices ?? []
        if devices.isEmpty { label(String(localized: "No batteries")) }
        if !expanded, span != .one {
            let columns = devices.prefix(span == .two ? 2 : 4).map { device in
                nativeStack([
                    nativeLabel(batteryPercentage(device), size: 15, weight: .semibold),
                    nativeLabel(device.name, size: 10)
                ], spacing: 3)
            }
            let row = nativeStack(columns, orientation: .horizontal, spacing: 4)
            row.distribution = .fillEqually
            add(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            return
        }
        for device in devices.prefix(expanded ? 12 : 1) {
            label(
                batteryPercentage(device), large: true)
            if expanded || span != .one { label(device.name) }
        }
    }
    func batteryPercentage(_ device: BatteryDeviceSnapshot) -> String {
        "\(device.primaryPercentage.map { "\($0)%" } ?? "—")\(device.isCharging ? " ⚡" : "")"
    }

    func systemStatusContent() {
        if let snapshot = SystemStatusService.shared.snapshot {
            label("CPU \(Int(snapshot.cpuUsagePercent.rounded()))%", large: true)
            if expanded || span != .one { label("Memory \(Int(snapshot.memoryUsagePercent.rounded()))%") }
            if expanded || span == .three || span == .four {
                let received = ByteCountFormatter.string(
                    fromByteCount: Int64(snapshot.receivedBytesPerSecond), countStyle: .binary)
                let sent = ByteCountFormatter.string(
                    fromByteCount: Int64(snapshot.sentBytesPerSecond), countStyle: .binary)
                if expanded {
                    label("↓ \(received)/s")
                    label("↑ \(sent)/s")
                } else {
                    label("↓ \(received)/s  ↑ \(sent)/s")
                }
            }
        } else {
            label(String(localized: "Loading…"))
        }
    }

    func weatherContent() {
        let service = WeatherService.shared
        if configuredWeather == nil && service.permissionStatus != .granted {
            permission(String(localized: "Weather"), for: .location, status: service.permissionStatus) {
                await service.requestAccess()
            }
            return
        }
        let unit = WeatherWidgetSettingsKey.temperatureUnitSelection(from: tile.settings).resolved(
            baseline: WeatherService.baselineTemperatureUnit)
        if let snapshot = (configuredWeather?.snapshot ?? (configuredWeather == nil ? service.snapshot : nil))?
            .converted(from: WeatherService.baselineTemperatureUnit, to: unit) {
            label(snapshot.roundedTemperatureText, large: true)
            if expanded || span != .one {
                label(snapshot.locationName)
                label(snapshot.conditionDescription)
                label(snapshot.highLowText, color: .secondaryLabelColor)
            }
            if expanded {
                for day in snapshot.forecast {
                    let high = day.highTemperature.map { "\(Int($0.rounded()))°" } ?? "—"
                    let low = day.lowTemperature.map { "\(Int($0.rounded()))°" } ?? "—"
                    label("\(day.weekdayShortText)  \(high) / \(low)")
                }
            }
        } else {
            label(
                configuredWeather?.lastErrorDescription ?? service.lastErrorDescription
                    ?? String(localized: "Loading…"))
        }
    }

    func photoFrameContent() {
        if let image = PhotoFrameService.shared.currentImage {
            let view = NSImageView()
            view.image = image
            view.imageScaling = .scaleProportionallyUpOrDown
            add(view)
        } else {
            add(
                NativeActionButton(String(localized: "Add Photos"), symbol: "photo.badge.plus") {
                    PhotoFrameService.shared.choosePhotos()
                })
        }
    }

    func searchContent() {
        if span == .one {
            let view = NSImageView(
                image: NSImage(
                    systemSymbolName: "magnifyingglass", accessibilityDescription: String(localized: "Search"))
                    ?? NSImage())
            add(view)
        } else {
            let field = NativeSearchField()
            field.placeholderString = String(localized: "Search Google")
            field.target = self
            field.action = #selector(submitSearch)
            field.delegate = self
            search = field
            add(field)
        }
    }

    func externalContent() {
        label(String(localized: "Unsupported community widget"))
    }

    func mediaContent() {
        let service = MediaPlaybackService.shared
        let state = service.state(for: mediaBundleIdentifier)
        guard let state, state.hasContent else {
            label(String(localized: "Nothing playing"))
            return
        }
        let artwork =
            state.artworkData.flatMap(NSImage.init(data:))
            ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: String(localized: "Now Playing"))
        if let artwork {
            let imageView = NSImageView(image: artwork)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.heightAnchor.constraint(equalToConstant: expanded ? 70 : span == .one ? 44 : 24).isActive = true
            add(imageView)
        }
        if expanded || span != .one {
            label(state.title, large: true)
            label(state.artist, color: .secondaryLabelColor)
        }
        if expanded || span != .one {
            add(
                nativeStack(
                    [
                        NativeActionButton("", symbol: "backward.end.fill") {
                            Task { await service.skipToPrevious(for: state.bundleIdentifier) }
                        },
                        NativeActionButton("", symbol: state.isPlaying ? "pause.fill" : "play.fill") {
                            Task { await service.togglePlayPause(for: state.bundleIdentifier) }
                        },
                        NativeActionButton("", symbol: "forward.end.fill") {
                            Task { await service.skipToNext(for: state.bundleIdentifier) }
                        }
                    ], orientation: .horizontal, spacing: 2))
        }
        if expanded { expandedMediaContent(state) }
    }
    var mediaBundleIdentifier: String {
        if let configured = tile.settings.string("nowPlaying.appBundleIdentifier"), !configured.isEmpty {
            return configured
        }
        return tile.ownerBundleIdentifier
    }
    func expandedMediaContent(_ state: MediaPlaybackState) {
        let service = MediaPlaybackService.shared
        add(NativeMediaPlaybackTimeline(state: state))
        if state.supportsFavorite {
            add(
                NativeActionButton(String(localized: "Favorite"), symbol: state.isFavorite ? "heart.fill" : "heart") {
                    Task { await service.setFavorite(!state.isFavorite, for: state.bundleIdentifier) }
                })
        }
        if service.supportsLyrics(for: state.bundleIdentifier) {
            add(
                NativeActionButton(String(localized: "Lyrics")) { [weak self] in
                    self?.showsLyrics.toggle()
                    service.requestLyrics(for: state.bundleIdentifier)
                    self?.refresh()
                })
            if showsLyrics {
                switch service.lyricsState(for: state.bundleIdentifier) {
                case .loaded(let lyrics):
                    add(NativeMediaPlaybackTimeline(state: state, lyrics: lyrics))
                case .loading: label(String(localized: "Loading…"))
                default: label(String(localized: "Lyrics unavailable"))
                }
            }
        }
    }
    static func playbackTime(_ seconds: TimeInterval) -> String {
        let seconds = Int(max(0, seconds))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

}
