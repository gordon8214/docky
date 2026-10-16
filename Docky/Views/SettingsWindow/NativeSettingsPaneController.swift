import AppKit

/// One settings pane: a scrolling grouped form built once from
/// `NativeSettingsContent`. Its rows observe preferences themselves, so the
/// pane never rebuilds.
final class NativeSettingsPaneController: NSViewController {
    let pane: SettingsPane
    let placement: NativeSettingsContext.Placement
    private(set) lazy var context = NativeSettingsContext(placement: placement, owner: self)
    private(set) lazy var scrollView = NativeSettingsScrollView(style: context.style)
    var form: NativeSettingsForm { scrollView.form }

    init(pane: SettingsPane, placement: NativeSettingsContext.Placement = .settingsWindow) {
        self.pane = pane
        self.placement = placement
        super.init(nibName: nil, bundle: nil)
        title = pane.title
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView(frame: CGRect(x: 0, y: 0, width: 600, height: 480))
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        form.setSections(NativeSettingsContent.sections(for: pane, context: context))
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        for handler in context.appearHandlers { handler() }
    }
}
