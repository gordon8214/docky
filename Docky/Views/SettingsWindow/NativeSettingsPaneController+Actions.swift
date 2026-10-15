import AppKit

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
}
