import AppKit

/// The scrolling document of a settings pane: sections stacked top to bottom.
final class NativeSettingsForm: NSView {
    let style: NativeSettingsMetrics.Style
    private(set) var sections: [NativeSettingsSection] = []
    private let stack = NSStackView()

    init(style: NativeSettingsMetrics.Style = .regular) {
        self.style = style
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = style.sectionSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.required, for: .vertical)
        addSubview(stack)
        let margins = style.margins
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: margins.top),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margins.left),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margins.right),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -margins.bottom)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func setSections(_ newSections: [NativeSettingsSection]) {
        for section in sections {
            stack.removeArrangedSubview(section)
            section.removeFromSuperview()
        }
        sections = newSections
        for section in newSections {
            stack.addArrangedSubview(section)
            section.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }
}

/// A scroll view whose document is a settings form as wide as the visible area.
final class NativeSettingsScrollView: NSScrollView {
    let form: NativeSettingsForm

    init(style: NativeSettingsMetrics.Style = .regular) {
        form = NativeSettingsForm(style: style)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        hasVerticalScroller = true
        autohidesScrollers = true
        drawsBackground = false
        borderType = .noBorder
        automaticallyAdjustsContentInsets = true
        documentView = form
        // A form that can't get narrower than its content clips rather than
        // breaking the width constraint.
        let width = form.widthAnchor.constraint(equalTo: contentView.widthAnchor)
        width.priority = .init(999)
        NSLayoutConstraint.activate([
            form.topAnchor.constraint(equalTo: contentView.topAnchor),
            form.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            width
        ])
    }

    required init?(coder: NSCoder) { nil }
}
