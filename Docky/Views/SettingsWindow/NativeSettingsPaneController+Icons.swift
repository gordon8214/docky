import AppKit
import Combine
import UniformTypeIdentifiers

extension NativeSettingsPaneController {
    func hiddenAppRows() {
        for bundleID in DockyPreferences.shared.hiddenAppBundleIdentifiers {
            add(
                nativeStack(
                    [
                        nativeLabel(bundleID),
                        NativeActionButton(String(localized: "Show in Dock")) { [weak self] in
                            DockyPreferences.shared.setAppHiddenInDocky(bundleIdentifier: bundleID, isHidden: false)
                            self?.rebuild()
                        }
                    ], orientation: .horizontal))
        }
        add(
            NativeActionButton(String(localized: "Hide App…")) { [weak self] in
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.application]
                if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier {
                    DockyPreferences.shared.setAppHiddenInDocky(bundleIdentifier: id, isHidden: true)
                    self?.rebuild()
                }
            })
    }
}
