import AppKit

final class NativeActionButton: NSButton {
    var handler: (() -> Void)?
    init(_ title: String, symbol: String? = nil, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        self.title = NSLocalizedString(title, comment: "")
        bezelStyle = .rounded
        target = self
        action = #selector(invoke)
        if let symbol {
            let label =
                title.isEmpty ? Self.symbolLabels[symbol] ?? symbol.replacingOccurrences(of: ".", with: " ") : title
            setAccessibilityLabel(NSLocalizedString(label, comment: ""))
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        }
    }
    private static let symbolLabels = [
        "chevron.left": "Back", "chevron.right": "Forward", "power": "Power Options",
        "backward.end.fill": "Previous Track", "forward.end.fill": "Next Track",
        "play.fill": "Play", "pause.fill": "Pause", "slider.horizontal.3": "Launchpad Settings",
        "folder": "Open in Finder"
    ]
    required init?(coder: NSCoder) { nil }
    @objc private func invoke() { handler?() }
}

final class NativeSearchField: NSSearchField {
    override func mouseDown(with event: NSEvent) {
        if let panel = window as? any DockSearchFocusWindow { panel.setSearchFocus(true) }
        super.mouseDown(with: event)
    }
}

@MainActor
func nativeLabel(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor)
    -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: NSLocalizedString(text, comment: ""))
    label.font = .systemFont(ofSize: size, weight: weight)
    label.textColor = color
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return label
}

@MainActor
func nativeStack(_ views: [NSView], orientation: NSUserInterfaceLayoutOrientation = .vertical, spacing: CGFloat = 8)
    -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = orientation
    stack.alignment = orientation == .vertical ? .leading : .centerY
    stack.spacing = spacing
    stack.distribution = .fill
    return stack
}

final class NativeScrollDocumentView: NSView { override var isFlipped: Bool { true } }

final class NativeHoverMaterialView: NSVisualEffectView {
    var onHover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(
            rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self)
        if let tracking { addTrackingArea(tracking) }
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
