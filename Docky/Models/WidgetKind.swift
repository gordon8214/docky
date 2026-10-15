import Foundation

enum WidgetKind: Codable, Identifiable, Hashable {
    case calendar
    case calendarDate
    case reminders
    case batteries
    case systemStatus
    case nowPlaying
    case weather
    case search
    case photoFrame
    /// Stable identifier for a saved, unsupported community widget.
    case external(String)

    nonisolated static let builtInCases: [WidgetKind] = [
        .calendar,
        .calendarDate,
        .reminders,
        .batteries,
        .systemStatus,
        .nowPlaying,
        .weather,
        .search,
        .photoFrame
    ]

    /// Round-trips through DockyPreferences / persistence as a single
    /// string. External widgets use an `external:<identifier>` prefix
    /// so existing values stay valid and unknown values can be
    /// detected by inspecting the prefix.
    nonisolated var rawValue: String {
        switch self {
        case .calendar: "calendar"
        case .calendarDate: "calendarDate"
        case .reminders: "reminders"
        case .batteries: "batteries"
        case .systemStatus: "systemStatus"
        case .nowPlaying: "nowPlaying"
        case .weather: "weather"
        case .search: "search"
        case .photoFrame: "photoFrame"
        case .external(let identifier): "external:\(identifier)"
        }
    }

    nonisolated init?(rawValue: String) {
        if rawValue.hasPrefix("external:") {
            let identifier = String(rawValue.dropFirst("external:".count))
            guard !identifier.isEmpty else { return nil }
            self = .external(identifier)
            return
        }
        guard let kind = Self.builtInCases.first(where: { $0.rawValue == rawValue }) else { return nil }
        self = kind
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let kind = WidgetKind(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown WidgetKind rawValue: \(raw)"
            )
        }
        self = kind
    }

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .calendar:
            String(localized: "Calendar")
        case .calendarDate:
            String(localized: "Date")
        case .reminders:
            String(localized: "Reminders")
        case .batteries:
            String(localized: "Batteries")
        case .systemStatus:
            String(localized: "System Status")
        case .nowPlaying:
            String(localized: "Now Playing")
        case .weather:
            String(localized: "Weather")
        case .search:
            String(localized: "Search")
        case .photoFrame:
            String(localized: "Photo Frame")
        case .external(let identifier):
            String(localized: "Unsupported community widget") + ": " + identifier
        }
    }

    @MainActor var supportedSpans: [TileSpan] {
        switch self {
        case .calendarDate:
            [.one]
        case .calendar, .reminders, .batteries, .systemStatus, .nowPlaying, .weather, .search, .photoFrame:
            TileSpan.allCases
        case .external:
            TileSpan.allCases
        }
    }

    @MainActor var expansionExtent: WidgetExpansionExtent {
        switch self {
        case .nowPlaying:
            WidgetExpansionExtent(widthTiles: 5, heightTiles: 2)
        case .calendar, .calendarDate, .reminders, .batteries, .systemStatus, .weather, .search, .photoFrame:
            .standard
        case .external:
            .standard
        }
    }

    /// Whether hovering this widget triggers the larger preview window
    /// after the dwell delay. Defaults to `true` for widgets that have
    /// genuine extra content at expanded size. Widgets whose 1x/2x/3x
    /// representation IS the full thing (search field, calendar date)
    /// stay inline.
    @MainActor var isExpandable: Bool {
        switch self {
        case .calendar, .reminders, .batteries, .systemStatus, .nowPlaying, .weather, .photoFrame:
            true
        case .calendarDate, .search:
            false
        case .external:
            false
        }
    }
}

struct WidgetExpansionExtent: Equatable {
    let widthTiles: Int
    let heightTiles: Int

    static let standard = WidgetExpansionExtent(widthTiles: 3, heightTiles: 3)
}

enum TileSpan: Int, CaseIterable, Codable, Identifiable {
    case one = 1
    case two = 2
    case three = 3
    /// Not offered in the widget palette or "Span" submenu. The widget
    /// expansion window uses it, and saved tiles may still carry it.
    case four = 4

    var id: Int { rawValue }
}
