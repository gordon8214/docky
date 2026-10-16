import AppKit
import Combine

extension NativeSettingsContent {
    static func actionSections() -> [NativeSettingsSection] {
        let service = MenuCatalogService.shared
        let reload = NativeActionButton(String(localized: "Reload Catalog")) { service.reload() }
        let packages = NativeSettingsListSection(
            String(localized: "Catalog Packages"),
            footer: String(
                localized:
                    "Actions are menu items Docky adds to each tile's right-click menu. Every action a loaded package defines is available on the matching tiles."),
            emptyText: String(localized: "No catalog packages loaded."), actions: [reload])
        let diagnostics = NativeSettingsListSection(String(localized: "Diagnostics"), emptyText: "")
        packages.observe(service.objectWillChange) { [weak packages, weak diagnostics] in
            packages?.reconcile(
                service.packageSummaries, id: \.id,
                make: { package in
                    NativeFormListRow(id: package.id, icon: nil, title: package.title, subtitle: packageSubtitle(package))
                },
                update: { row, package in
                    (row as? NativeFormListRow)?.update(icon: nil, title: package.title, subtitle: packageSubtitle(package))
                })
            diagnostics?.reconcile(
                Array(service.diagnostics.enumerated()), id: { "\($0.offset)" },
                make: { NativeFormTextRow($0.element, secondary: true, selectable: true) },
                update: { row, diagnostic in (row as? NativeFormTextRow)?.text = diagnostic.element })
            diagnostics?.isHidden = service.diagnostics.isEmpty
        }
        return [packages, diagnostics]
    }

    private static func packageSubtitle(_ package: CatalogPackageSummary) -> String {
        let version = String(localized: "Version \(package.version)", comment: "A catalog package's version")
        let count = String(
            localized: "\(package.actionCount) actions", comment: "How many actions a catalog package has")
        return "\(version) · \(count)"
    }
}
