import AppKit
import Combine

final class NativeSettingsPaneController: NSViewController {
    let id: String
    let scroll = NSScrollView()
    let document = NativeFormDocument()
    let stack = NSStackView()
    var subscriptions = Set<AnyCancellable>()
    init(id: String) {
        self.id = id
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }
    override func loadView() {
        view = NSView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = document
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        document.addSubview(stack)
        view.addSubview(scroll)
        rebuild()
        if id == "profiles" {
            observeChanges { [weak self] in
                _ = ProfileService.shared.profiles
                _ = ProfileService.shared.activeProfileID
                self?.rebuild()
            }.store(in: &subscriptions)
        } else if id == "hiddenApps" {
            observeChanges { [weak self] in
                _ = DockyPreferences.shared.hiddenAppBundleIdentifiers
                self?.rebuild()
            }.store(in: &subscriptions)
        }
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        scroll.frame = view.bounds
        let height = max(scroll.contentSize.height, stack.fittingSize.height + 40)
        document.frame = CGRect(x: 0, y: 0, width: scroll.contentSize.width, height: height)
        stack.frame = CGRect(
            x: 20, y: 20, width: max(0, scroll.contentSize.width - 40), height: stack.fittingSize.height)
    }
    func add(_ view: NSView) { stack.addArrangedSubview(view) }
    func rebuild() {
        for child in stack.arrangedSubviews {
            stack.removeArrangedSubview(child)
            child.removeFromSuperview()
        }
        add(
            nativeLabel(
                NativeSettingsController.panes.first(where: { $0.id == id })?.title ?? id, size: 22, weight: .semibold))
        for row in NativeSettingsFields.rows(for: id) { add(row) }
        let builders: [String: () -> Void] = [
            "appearanceGeneral": appearanceResetRows, "behaviorGeneral": behaviorResetRows,
            "behaviorWidgets": widgetPreviewRows, "profiles": profileRows, "hiddenApps": hiddenAppRows,
            "permissions": permissionRows, "updates": updateRows, "actions": actionRows
        ]
        builders[id]?()
        view.needsLayout = true
    }
    func appearanceResetRows() {
        add(
            NativeActionButton(String(localized: "Reset Appearance")) { [weak self] in
                self?.confirmReset { DockyPreferences.shared.resetAppearanceToDefaults() }
            })
    }
    func behaviorResetRows() {
        add(
            NativeActionButton(String(localized: "Reset Behavior")) { [weak self] in
                self?.confirmReset { DockyPreferences.shared.resetBehaviorToDefaults() }
            })
    }
    func widgetPreviewRows() {
        for span in TileSpan.allCases.filter({ $0 != .four }) {
            let button = NSButton(checkboxWithTitle: "Preview \(span.rawValue) Tile Widgets", target: nil, action: nil)
            let row = NativeFormRow(title: "", control: button)
            row.bind(button) {
                if button.state == .on {
                    DockyPreferences.shared.widgetHoverPreviewSpans.insert(span)
                } else {
                    DockyPreferences.shared.widgetHoverPreviewSpans.remove(span)
                }
            }
            row.observe { [weak button] in
                button?.state = DockyPreferences.shared.widgetHoverPreviewSpans.contains(span) ? .on : .off
            }
            add(row)
        }
    }
    func confirmDelete(_ title: String, action: () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: String(localized: "Delete"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn { action() }
    }
    func confirmReset(_ action: () -> Void) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Reset these settings to defaults?")
        alert.addButton(withTitle: String(localized: "Reset"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn { action() }
    }
    func prompt(_ title: String, value: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(string: value)
        field.frame = CGRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
}

final class NativeFormDocument: NSView { override var isFlipped: Bool { true } }
