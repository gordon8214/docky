import AppKit

final class NativeCalendarEventButton: NSButton {
    private let event: CalendarEventSnapshot
    init(event: CalendarEventSnapshot) {
        self.event = event
        super.init(frame: .zero)
        title = event.title
        bezelStyle = .inline
        alignment = .left
        target = self
        action = #selector(openEvent)
    }
    required init?(coder: NSCoder) { nil }
    @objc private func openEvent() {
        var components = URLComponents()
        components.scheme = "ical"
        components.host = "ekevent"
        components.path = "/" + event.eventIdentifier
        components.queryItems = [
            URLQueryItem(name: "method", value: "show"), URLQueryItem(name: "options", value: "more")
        ]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }
    override func rightMouseDown(with event: NSEvent) {
        var actions: [ContextAction] = [
            .action(String(localized: "Open in Calendar")) { [weak self] in self?.openEvent() },
            copyAction(String(localized: "Copy Title"), value: self.event.title)
        ]
        if !self.event.location.isEmpty {
            actions.append(copyAction(String(localized: "Copy Location"), value: self.event.location))
        }
        if let url = self.event.quickJoinURL {
            actions.append(.action(String(localized: "Join Meeting")) { NSWorkspace.shared.open(url) })
            actions.append(copyAction(String(localized: "Copy Meeting Link"), value: url.absoluteString))
        }
        ContextActionMenuPresenter.popUpMenu(actions: actions, from: self)
    }
    private func copyAction(_ title: String, value: String) -> ContextAction {
        .action(title) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        }
    }
}
