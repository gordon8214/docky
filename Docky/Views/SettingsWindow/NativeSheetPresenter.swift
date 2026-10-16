import AppKit
import UniformTypeIdentifiers

/// Shows alerts, prompts, and open panels as sheets on the window that holds
/// a settings pane.
@MainActor
final class NativeSheetPresenter {
    weak var owner: NSViewController?

    init(owner: NSViewController?) {
        self.owner = owner
    }

    private var window: NSWindow? { owner?.view.window }

    /// Runs `alert` as a sheet. Returns `.cancel` while another sheet is open.
    func run(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        guard let window else { return alert.runModal() }
        guard window.attachedSheet == nil else { return .cancel }
        prepare(window)
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
    }

    func confirm(
        _ message: String, informativeText: String? = nil, confirmTitle: String, destructive: Bool = false
    ) async -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informativeText ?? ""
        let confirm = alert.addButton(withTitle: confirmTitle)
        confirm.hasDestructiveAction = destructive
        alert.addButton(withTitle: String(localized: "Cancel"))
        return await run(alert) == .alertFirstButtonReturn
    }

    func prompt(_ message: String, value: String = "", confirmTitle: String = String(localized: "Save")) async
        -> String? {
        let alert = NSAlert()
        alert.messageText = message
        let field = NSTextField(string: value)
        field.frame = CGRect(x: 0, y: 0, width: 260, height: 22)
        alert.accessoryView = field
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.layout()
        alert.window.initialFirstResponder = field
        return await run(alert) == .alertFirstButtonReturn ? field.stringValue : nil
    }

    func chooseFile(_ types: [UTType], directoryURL: URL? = nil) async -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.directoryURL = directoryURL
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard let window else { return panel.runModal() == .OK ? panel.url : nil }
        guard window.attachedSheet == nil else { return nil }
        prepare(window)
        let response = await withCheckedContinuation { continuation in
            panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
        return response == .OK ? panel.url : nil
    }

    /// Presents a form sheet and waits until it closes. Returns whether it was saved.
    func present(_ sheet: NativeFormSheetController) async -> Bool {
        guard let owner, let window, window.attachedSheet == nil else { return false }
        prepare(window)
        return await withCheckedContinuation { continuation in
            sheet.onFinish = { continuation.resume(returning: $0) }
            owner.presentAsSheet(sheet)
        }
    }

    /// The Launchpad inspector is a nonactivating panel, which can't take a
    /// sheet's keystrokes until Docky is active.
    private func prepare(_ window: NSWindow) {
        if window.styleMask.contains(.nonactivatingPanel) { NSApp.activate() }
    }
}
