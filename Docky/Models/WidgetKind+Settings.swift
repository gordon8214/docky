extension WidgetKind {
    /// Supported built-ins with per-placement native settings.
    @MainActor var hasConfigurableSettings: Bool {
        switch self {
        case .weather, .calendar, .nowPlaying:
            true
        case .calendarDate, .reminders, .batteries, .systemStatus, .search, .photoFrame:
            false
        case .external:
            false
        }
    }
}
