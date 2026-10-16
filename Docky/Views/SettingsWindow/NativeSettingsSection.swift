import AppKit
import Combine

/// A grouped-form section: an optional header, a rounded box of rows, and an
/// optional footer with buttons beside it.
class NativeSettingsSection: NSView {
    var header: String? {
        didSet { showHeader() }
    }
    var footer: String? {
        didSet { showFooter() }
    }
    private(set) var rows: [NativeFormRowView] = []
    /// Whether the section enables its rows; see `enablingRows(when:)`. Rows added
    /// later follow it too.
    var rowsEnabled = true {
        didSet { for row in rows { row.isSectionEnabled = rowsEnabled } }
    }
    var targets: [NativeControlAction] = []
    var subscriptions = Set<AnyCancellable>()
    let box = NativeFormGroupBox()
    private let stack = NSStackView()
    private let headerLabel = NativeWrappingLabel(font: NativeSettingsMetrics.headerFont)
    private let rowStack = NSStackView()
    /// The footer at the leading edge, and the action buttons at the trailing edge.
    private let below = NSView()
    private let footerLabel = NativeWrappingLabel(
        font: NativeSettingsMetrics.detailFont, color: .secondaryLabelColor)
    private let actionStack = NSStackView()
    private var footerToActions: NSLayoutConstraint?
    private var footerToEdge: NSLayoutConstraint?

    init(_ header: String? = nil, footer: String? = nil, rows: [NativeFormRowView] = [], actions: [NSView] = []) {
        self.header = header
        self.footer = footer
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = NativeSettingsMetrics.headerSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.orientation = .vertical
        rowStack.alignment = .leading
        rowStack.spacing = 0
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(rowStack)
        below.translatesAutoresizingMaskIntoConstraints = false
        actionStack.orientation = .horizontal
        actionStack.spacing = NativeSettingsMetrics.controlSpacing
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        below.addSubview(footerLabel)
        below.addSubview(actionStack)
        let fit = below.heightAnchor.constraint(equalToConstant: 0)
        fit.priority = .init(1)
        footerToActions = footerLabel.trailingAnchor.constraint(
            equalTo: actionStack.leadingAnchor, constant: -NativeSettingsMetrics.titleSpacing)
        footerToEdge = footerLabel.trailingAnchor.constraint(equalTo: below.trailingAnchor)
        NSLayoutConstraint.activate([
            footerLabel.leadingAnchor.constraint(equalTo: below.leadingAnchor),
            footerLabel.topAnchor.constraint(equalTo: below.topAnchor),
            below.bottomAnchor.constraint(greaterThanOrEqualTo: footerLabel.bottomAnchor),
            actionStack.trailingAnchor.constraint(equalTo: below.trailingAnchor),
            actionStack.topAnchor.constraint(equalTo: below.topAnchor),
            below.bottomAnchor.constraint(greaterThanOrEqualTo: actionStack.bottomAnchor),
            fit
        ])
        for view in [headerLabel, box, below] { stack.addArrangedSubview(view) }
        stack.setCustomSpacing(NativeSettingsMetrics.footerSpacing, after: box)
        addSubview(stack)
        let inset = NativeSettingsMetrics.headerInset
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            headerLabel.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: inset),
            headerLabel.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -inset),
            box.widthAnchor.constraint(equalTo: stack.widthAnchor),
            below.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: inset),
            below.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: box.topAnchor),
            rowStack.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            rowStack.bottomAnchor.constraint(equalTo: box.bottomAnchor)
        ])
        showHeader()
        showFooter()
        setActions(actions)
        setRows(rows)
    }

    required init?(coder: NSCoder) { nil }

    /// Replaces the rows, keeping any row that stays so its focus and state survive.
    func setRows(_ newRows: [NativeFormRowView]) {
        for row in rows where !newRows.contains(where: { $0 === row }) {
            rowStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        for (index, row) in newRows.enumerated() where rowStack.arrangedSubviews.firstIndex(of: row) != index {
            let isNew = row.superview !== rowStack
            rowStack.insertArrangedSubview(row, at: index)
            if isNew { row.widthAnchor.constraint(equalTo: rowStack.widthAnchor).isActive = true }
            row.onVisibilityChange = { [weak self] in self?.updateSeparators() }
            row.isSectionEnabled = rowsEnabled
        }
        rows = newRows
        updateSeparators()
    }

    func setActions(_ actions: [NSView]) {
        for view in actionStack.arrangedSubviews {
            actionStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for view in actions { actionStack.addArrangedSubview(view) }
        actionStack.isHidden = actions.isEmpty
        // Deactivate first, so the two trailing constraints are never both active.
        if actions.isEmpty {
            footerToActions?.isActive = false
            footerToEdge?.isActive = true
        } else {
            footerToEdge?.isActive = false
            footerToActions?.isActive = true
        }
        updateBelow()
    }

    /// Each visible row but the first gets a separator, and a section with no
    /// visible rows hides its box.
    func updateSeparators() {
        var isFirst = true
        for row in rows where !row.isHidden {
            row.showsSeparator = !isFirst
            isFirst = false
        }
        box.isHidden = isFirst
    }

    /// Targets an action button below the box, like a row's `bind`.
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

    private func showHeader() {
        headerLabel.stringValue = header ?? ""
        headerLabel.isHidden = header?.isEmpty ?? true
    }

    private func showFooter() {
        footerLabel.stringValue = footer ?? ""
        updateBelow()
    }

    private func updateBelow() {
        let hasFooter = !(footer?.isEmpty ?? true)
        footerLabel.isHidden = !hasFooter
        below.isHidden = !hasFooter && actionStack.isHidden
    }
}

/// The rounded, filled box behind a section's rows.
final class NativeFormGroupBox: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = NativeSettingsMetrics.boxCornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        layer.backgroundColor = NativeSettingsMetrics.boxFill.cgColor
        layer.borderColor = NativeSettingsMetrics.boxBorder.cgColor
        layer.borderWidth = 1 / (window?.backingScaleFactor ?? 2)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsDisplay = true
    }
}
