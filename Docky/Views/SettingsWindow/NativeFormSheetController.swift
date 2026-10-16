import AppKit

/// A sheet holding a compact settings form above Cancel and a confirm button.
/// An optional leading button, such as Delete, sits at the other end of the bar.
final class NativeFormSheetController: NSViewController {
    /// Called once when the sheet closes, with whether it was confirmed.
    var onFinish: ((Bool) -> Void)?
    /// Called before the sheet closes on confirm; returning false keeps it open.
    var onConfirm: (() -> Bool)?
    let scrollView = NativeSettingsScrollView(style: .compact)
    var form: NativeSettingsForm { scrollView.form }
    private let titleText: String
    private let confirmTitle: String
    private let leadingButton: NSButton?
    private let size: CGSize
    private var finished = false
    private var parentCloseObserver: NSObjectProtocol?

    /// The sheet is `size.width` wide and as tall as its form, up to `size.height`.
    init(
        title: String, confirmTitle: String, leadingButton: NSButton? = nil,
        size: CGSize = CGSize(width: 480, height: 560)
    ) {
        titleText = title
        self.confirmTitle = confirmTitle
        self.leadingButton = leadingButton
        self.size = size
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView(frame: CGRect(origin: .zero, size: size))
        let heading = NativeWrappingLabel(titleText, font: .boldSystemFont(ofSize: NSFont.systemFontSize))
        let cancel = NativeActionButton(String(localized: "Cancel")) { [weak self] in self?.close(confirmed: false) }
        cancel.keyEquivalent = "\u{1b}"
        let confirm = NativeActionButton(confirmTitle) { [weak self] in
            guard let self else { return }
            // Commit a field that is still being edited before reading the form.
            self.view.window?.makeFirstResponder(nil)
            guard self.onConfirm?() ?? true else { return }
            self.close(confirmed: true)
        }
        confirm.keyEquivalent = "\r"
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.translatesAutoresizingMaskIntoConstraints = false
        if let leadingButton { bar.setViews([leadingButton], in: .leading) }
        bar.setViews([cancel, confirm], in: .trailing)
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        scrollView.automaticallyAdjustsContentInsets = false
        for subview in [heading, scrollView, divider, bar] { view.addSubview(subview) }
        let margin = NativeSettingsMetrics.Style.compact.margins.left
        // Hug the form, so a short form makes a short sheet; a long one scrolls.
        let fitsForm = scrollView.heightAnchor.constraint(equalTo: form.heightAnchor)
        fitsForm.priority = .defaultHigh
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: size.width),
            view.heightAnchor.constraint(lessThanOrEqualToConstant: size.height),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            fitsForm,
            heading.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin + 10),
            heading.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            scrollView.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 12),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            bar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])
        // A sheet opens at its view's size, so start at the height the form needs.
        view.layoutSubtreeIfNeeded()
        let height = min(size.height, view.fittingSize.height)
        view.setFrameSize(NSSize(width: size.width, height: height))
        preferredContentSize = view.frame.size
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        finished = false
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // The sheet also closes with the window it's attached to. It disappears
        // without closing when that window is minimized or Docky is hidden, so
        // `viewDidDisappear` can't tell the two apart.
        guard parentCloseObserver == nil, let parent = view.window?.sheetParent else { return }
        parentCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: parent, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.report(false) }
        }
    }

    func close(confirmed: Bool) {
        view.window?.makeFirstResponder(nil)
        report(confirmed)
        dismiss(nil)
    }

    private func report(_ confirmed: Bool) {
        if let parentCloseObserver { NotificationCenter.default.removeObserver(parentCloseObserver) }
        parentCloseObserver = nil
        guard !finished else { return }
        finished = true
        onFinish?(confirmed)
    }
}
