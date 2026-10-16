import AppKit
import UniformTypeIdentifiers

extension NativeSettingsContent {
    static func hiddenAppSections(_ context: NativeSettingsContext) -> [NativeSettingsSection] {
        let hide = NativeActionButton(String(localized: "Hide App…")) {
            Task {
                guard
                    let url = await context.sheets.chooseFile(
                        [.application], directoryURL: URL(fileURLWithPath: "/Applications")),
                    let identifier = Bundle(url: url)?.bundleIdentifier
                else { return }
                DockyPreferences.shared.setAppHiddenInDocky(bundleIdentifier: identifier, isHidden: true)
            }
        }
        let list = NativeSettingsListSection(
            footer: String(
                localized: "Apps hidden with “Hide in Docky” stay off the taskbar until you show them again."),
            emptyText: String(localized: "No apps are hidden."), actions: [hide])
        list.observe(of: { DockyPreferences.shared.hiddenAppBundleIdentifiers }) { [weak list] identifiers in
            list?.reconcile(identifiers, id: { $0 }, make: hiddenAppRow, update: { _, _ in })
        }
        return [list]
    }

    private static func hiddenAppRow(_ identifier: String) -> NativeFormRowView {
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier).map {
            FileManager.default.displayName(atPath: $0.path)
        }
        let show = NativeActionButton(String(localized: "Show")) {
            DockyPreferences.shared.setAppHiddenInDocky(bundleIdentifier: identifier, isHidden: false)
        }
        show.setAccessibilityLabel(String(localized: "Show \(name ?? identifier) on the taskbar"))
        return NativeFormListRow(
            id: identifier, icon: listIcon(IconCacheService.shared.icon(forBundleIdentifier: identifier)),
            title: name ?? identifier, subtitle: name == nil ? nil : identifier, accessories: [show])
    }

    /// A copy of `image` sized for a list row, so resizing it doesn't affect the shared cache.
    static func listIcon(_ image: NSImage) -> NSImage? {
        let icon = image.copy() as? NSImage
        icon?.size = CGSize(width: NativeSettingsMetrics.listIconSize, height: NativeSettingsMetrics.listIconSize)
        return icon
    }
}
