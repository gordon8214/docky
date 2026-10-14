import AppKit
import Combine
import UniformTypeIdentifiers

extension NativeSettingsPaneController {
    func actionRows() {
        let service = MenuCatalogService.shared
        for package in service.packageSummaries {
            add(nativeLabel("\(package.title) \(package.version) — \(package.actionCount) actions"))
        }
        for diagnostic in service.diagnostics { add(nativeLabel(diagnostic, color: .secondaryLabelColor)) }
        add(
            NativeActionButton(String(localized: "Reload Catalog")) { [weak self] in
                service.reload()
                self?.rebuild()
            })
    }
    func feedbackRows() {
        let editor = NSTextView()
        editor.isRichText = false
        let editorScroll = NSScrollView()
        editorScroll.documentView = editor
        editorScroll.hasVerticalScroller = true
        editorScroll.widthAnchor.constraint(equalToConstant: 420).isActive = true
        editorScroll.heightAnchor.constraint(equalToConstant: 160).isActive = true
        add(editorScroll)
        add(
            NativeActionButton(String(localized: "Attach File…")) { [weak self] in
                let panel = NSOpenPanel()
                if panel.runModal() == .OK { self?.attachment = panel.url }
            })
        add(
            NativeActionButton(String(localized: "Prepare Feedback")) { [weak self] in
                guard let self else { return }
                do {
                    let url = try FeedbackBundle.build(feedbackText: editor.string, attachmentURL: self.attachment)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    let items: [Any] = [editor.string, url]
                    if let mail = NSSharingService(named: .composeEmail), mail.canPerform(withItems: items) {
                        mail.recipients = ["hello@quintero.gt"]
                        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                        mail.subject = "Docky Feedback (v\(version))"
                        mail.perform(withItems: items)
                    } else {
                        let picker = NSSharingServicePicker(items: items)
                        picker.show(relativeTo: self.view.bounds, of: self.view, preferredEdge: .minY)
                    }
                } catch { self.show(error) }
            })
    }
}
