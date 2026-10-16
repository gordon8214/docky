import AppKit

/// Text that spans the whole row, such as an explanation or a diagnostic.
final class NativeFormTextRow: NativeFormRowView {
    let label: NativeWrappingLabel
    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    init(_ text: String, secondary: Bool = false, selectable: Bool = false) {
        label = NativeWrappingLabel(
            text, font: secondary ? NativeSettingsMetrics.detailFont : NativeSettingsMetrics.titleFont,
            color: secondary ? .secondaryLabelColor : .labelColor, selectable: selectable)
        super.init(frame: .zero)
        addSubview(label)
        pin(label, to: self)
    }

    required init?(coder: NSCoder) { nil }
}

/// A row holding any view, such as a search field, across its full width.
final class NativeFormContentRow: NativeFormRowView {
    let content: NSView

    init(_ content: NSView) {
        self.content = content
        super.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        pin(content, to: self)
    }

    required init?(coder: NSCoder) { nil }
}

/// A row in a list: an icon, a title with an optional subtitle, and trailing buttons.
final class NativeFormListRow: NativeFormRowView {
    let itemID: String
    let iconView = NSImageView()
    let titleLabel = NativeWrappingLabel()
    let subtitleLabel = NativeWrappingLabel(font: NativeSettingsMetrics.detailFont, color: .secondaryLabelColor)
    private let accessoryStack = NSStackView()
    private var textAfterIcon: NSLayoutConstraint?
    private var textAtEdge: NSLayoutConstraint?

    init(id: String, icon: NSImage?, title: String, subtitle: String? = nil, accessories: [NSView] = []) {
        itemID = id
        super.init(frame: .zero)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        let text = NSStackView(views: [titleLabel, subtitleLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        text.translatesAutoresizingMaskIntoConstraints = false
        text.setHuggingPriority(.defaultHigh, for: .vertical)
        for label in [titleLabel, subtitleLabel] {
            label.setContentHuggingPriority(.init(100), for: .horizontal)
        }
        accessoryStack.orientation = .horizontal
        accessoryStack.alignment = .centerY
        accessoryStack.spacing = NativeSettingsMetrics.controlSpacing
        accessoryStack.translatesAutoresizingMaskIntoConstraints = false
        accessoryStack.setHuggingPriority(.defaultHigh, for: .horizontal)
        for view in [iconView, text, accessoryStack] { addSubview(view) }
        let metrics = NativeSettingsMetrics.self
        let height = heightAnchor.constraint(equalToConstant: metrics.rowMinimumHeight)
        height.priority = .init(200)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: metrics.rowHorizontalPadding),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: metrics.listIconSize),
            iconView.heightAnchor.constraint(equalToConstant: metrics.listIconSize),
            text.trailingAnchor.constraint(equalTo: accessoryStack.leadingAnchor, constant: -metrics.titleSpacing),
            accessoryStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -metrics.rowHorizontalPadding),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            accessoryStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: metrics.rowVerticalPadding),
            iconView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: metrics.rowVerticalPadding),
            heightAnchor.constraint(greaterThanOrEqualToConstant: metrics.rowMinimumHeight),
            height
        ])
        textAfterIcon = text.leadingAnchor.constraint(
            equalTo: iconView.trailingAnchor, constant: metrics.controlSpacing)
        textAtEdge = text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: metrics.rowHorizontalPadding)
        setAccessibilityLabel(title)
        update(icon: icon, title: title, subtitle: subtitle)
        setAccessories(accessories)
    }

    required init?(coder: NSCoder) { nil }

    func update(icon: NSImage?, title: String, subtitle: String?) {
        iconView.image = icon
        iconView.isHidden = icon == nil
        // Deactivate first, so the two leading constraints are never both active.
        if icon == nil {
            textAfterIcon?.isActive = false
            textAtEdge?.isActive = true
        } else {
            textAtEdge?.isActive = false
            textAfterIcon?.isActive = true
        }
        separatorLeadingInset =
            icon == nil ? NativeSettingsMetrics.rowHorizontalPadding : NativeSettingsMetrics.listSeparatorInset
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle ?? ""
        subtitleLabel.isHidden = subtitle?.isEmpty ?? true
        setAccessibilityLabel(title)
    }

    func setAccessories(_ views: [NSView]) {
        for view in accessoryStack.arrangedSubviews where !views.contains(view) {
            accessoryStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (index, view) in views.enumerated() where accessoryStack.arrangedSubviews.firstIndex(of: view) != index {
            view.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            accessoryStack.insertArrangedSubview(view, at: index)
        }
        // New buttons in a disabled row start disabled too.
        if !effectiveEnabled { applyEnabled(false) }
    }
}

@MainActor
private func pin(_ content: NSView, to row: NSView) {
    let metrics = NativeSettingsMetrics.self
    NSLayoutConstraint.activate([
        content.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: metrics.rowHorizontalPadding),
        content.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -metrics.rowHorizontalPadding),
        content.topAnchor.constraint(equalTo: row.topAnchor, constant: metrics.rowVerticalPadding + 2),
        content.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -(metrics.rowVerticalPadding + 2))
    ])
}
