import AppKit
import Combine

/// One row in a settings section. A row keeps its control targets and
/// observations alive for as long as it exists.
class NativeFormRowView: NSView {
    var targets: [NativeControlAction] = []
    var subscriptions = Set<AnyCancellable>()
    /// Set by the section, which draws a separator above every visible row but the first.
    var showsSeparator = false {
        didSet { separator.isHidden = !showsSeparator }
    }
    var separatorLeadingInset = NativeSettingsMetrics.rowHorizontalPadding {
        didSet { separatorLeading?.constant = separatorLeadingInset }
    }
    /// Called when the row is shown or hidden, so the section can update its separators.
    var onVisibilityChange: (() -> Void)?
    /// A disabled row dims its text and disables its controls.
    var isEnabled = true {
        didSet { refreshEnabled() }
    }
    /// Set by a section that disables all its rows. The row is enabled only
    /// while both this and `isEnabled` are true.
    var isSectionEnabled = true {
        didSet { refreshEnabled() }
    }
    /// Whether the row is enabled, combining `isEnabled` and `isSectionEnabled`.
    private(set) var effectiveEnabled = true
    /// Called after the row is enabled or disabled, for controls with their own
    /// enabled logic, like a Clear button that's off when there's nothing to clear.
    final var onEnabledChange: (@MainActor (Bool) -> Void)?
    private let separator = NSBox()
    private var separatorLeading: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.isHidden = true
        addSubview(separator)
        let leading = separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: separatorLeadingInset)
        separatorLeading = leading
        NSLayoutConstraint.activate([
            leading,
            separator.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -NativeSettingsMetrics.rowHorizontalPadding),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override var isHidden: Bool {
        didSet { if oldValue != isHidden { onVisibilityChange?() } }
    }

    final func bind(_ control: NSControl, action: @escaping @MainActor () -> Void) {
        let target = NativeControlAction(action)
        targets.append(target)
        control.target = target
        control.action = #selector(NativeControlAction.invoke(_:))
    }

    final func observe(_ update: @escaping @MainActor () -> Void) { observeChanges(update).store(in: &subscriptions) }

    final func observe<Value: Equatable>(
        of read: @escaping @MainActor () -> Value, perform: @escaping @MainActor (Value) -> Void
    ) {
        observeChanges(of: read, perform: perform).store(in: &subscriptions)
    }

    /// Runs `update` now and after an `ObservableObject` publishes. `objectWillChange`
    /// fires before the change lands, so updates wait a turn, and several changes in
    /// one turn (a refresh setting many properties) run `update` once.
    final func observe(_ publisher: ObservableObjectPublisher, _ update: @escaping @MainActor () -> Void) {
        update()
        publisher.debounce(for: .zero, scheduler: DispatchQueue.main)
            .sink { _ in MainActor.assumeIsolated { update() } }
            .store(in: &subscriptions)
    }

    private func refreshEnabled() {
        let enabled = isEnabled && isSectionEnabled
        guard enabled != effectiveEnabled else { return }
        effectiveEnabled = enabled
        applyEnabled(enabled)
        onEnabledChange?(enabled)
    }

    func applyEnabled(_ enabled: Bool) {
        Self.setEnabled(enabled, in: self)
    }

    static func setEnabled(_ enabled: Bool, in view: NSView) {
        for subview in view.subviews {
            if let label = subview as? NSTextField, !label.isEditable {
                label.alphaValue = enabled ? 1 : 0.5
            } else if let control = subview as? NSControl {
                control.isEnabled = enabled
            } else {
                setEnabled(enabled, in: subview)
            }
        }
    }
}

/// A row with a title (and an optional description below it) on the leading
/// side and its controls on the trailing side.
final class NativeFormRow: NativeFormRowView {
    let title: String
    let titleLabel: NativeWrappingLabel
    let descriptionLabel = NativeWrappingLabel(
        font: NativeSettingsMetrics.detailFont, color: .secondaryLabelColor)
    /// The control the row's title labels.
    let control: NSView
    let accessoryStack = NSStackView()
    var descriptionText: String? {
        didSet { showDescription() }
    }

    /// `title` is display text: callers pass `String(localized:)`.
    init(title: String, description: String? = nil, control: NSView, accessories: [NSView] = []) {
        self.title = title
        titleLabel = NativeWrappingLabel(title)
        self.control = control
        super.init(frame: .zero)
        let text = NSStackView(views: [titleLabel, descriptionLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        text.translatesAutoresizingMaskIntoConstraints = false
        text.setHuggingPriority(.defaultHigh, for: .vertical)
        for label in [titleLabel, descriptionLabel] {
            label.setContentHuggingPriority(.init(100), for: .horizontal)
        }
        accessoryStack.orientation = .horizontal
        accessoryStack.alignment = .centerY
        accessoryStack.spacing = NativeSettingsMetrics.controlSpacing
        accessoryStack.translatesAutoresizingMaskIntoConstraints = false
        for view in [control] + accessories {
            // Controls keep their natural width; the title column takes the rest.
            view.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            accessoryStack.addArrangedSubview(view)
        }
        addSubview(text)
        addSubview(accessoryStack)
        let padding = NativeSettingsMetrics.rowHorizontalPadding
        let vertical = NativeSettingsMetrics.rowVerticalPadding
        let height = heightAnchor.constraint(equalToConstant: NativeSettingsMetrics.rowMinimumHeight)
        height.priority = .init(200)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            accessoryStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            text.trailingAnchor.constraint(
                equalTo: accessoryStack.leadingAnchor, constant: -NativeSettingsMetrics.titleSpacing),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            accessoryStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: vertical),
            accessoryStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: vertical),
            heightAnchor.constraint(greaterThanOrEqualToConstant: NativeSettingsMetrics.rowMinimumHeight),
            height
        ])
        if !title.isEmpty { control.setAccessibilityLabel(title) }
        titleLabel.setAccessibilityElement(false)
        descriptionLabel.setAccessibilityElement(false)
        setAccessibilityLabel(title)
        descriptionText = description
        showDescription()
    }

    required init?(coder: NSCoder) { nil }

    private func showDescription() {
        descriptionLabel.stringValue = descriptionText ?? ""
        descriptionLabel.isHidden = descriptionText?.isEmpty ?? true
        control.setAccessibilityHelp(descriptionText)
    }

    override func applyEnabled(_ enabled: Bool) {
        titleLabel.textColor = enabled ? .labelColor : .disabledControlTextColor
        descriptionLabel.textColor = enabled ? .secondaryLabelColor : .disabledControlTextColor
        Self.setEnabled(enabled, in: accessoryStack)
    }

    /// Keeps the row enabled only while `condition` holds.
    @discardableResult
    func enabled(when condition: @escaping @MainActor () -> Bool) -> Self {
        observe { [weak self] in self?.isEnabled = condition() }
        return self
    }

    /// Keeps the description in step with observable state.
    @discardableResult
    func describing(_ description: @escaping @MainActor () -> String?) -> Self {
        observe { [weak self] in self?.descriptionText = description() }
        return self
    }
}
