import AppKit
import Combine
import UniformTypeIdentifiers

extension NativeSettingsPaneController {
    func themeRows() {
        let manager = ThemeManager.shared
        add(
            nativeStack(
                [
                    NativeActionButton(String(localized: "Import Theme…")) { [weak self] in
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        if panel.runModal() == .OK, let url = panel.url {
                            do { _ = try manager.importTheme(from: url) } catch { self?.show(error) }
                        }
                    },
                    NativeActionButton(String(localized: "Export to Theme…")) { [weak self] in
                        let panel = NSSavePanel()
                        panel.nameFieldStringValue = "My Theme.dockytheme"
                        if panel.runModal() == .OK, let url = panel.url {
                            do {
                                _ = try manager.exportCurrentAppearance(
                                    name: url.deletingPathExtension().lastPathComponent, to: url)
                            } catch { self?.show(error) }
                        }
                    }
                ], orientation: .horizontal))
        add(
            nativeStack(
                [
                    NativeActionButton(String(localized: "Reveal Themes Folder")) {
                        Task { await FileBrowserService.shared.openFolder(manager.themesDirectoryURL) }
                    },
                    NativeActionButton(String(localized: "Refresh")) { manager.refreshInstalled() },
                    NativeActionButton(String(localized: "Clear Overrides")) {
                        DockyPreferences.shared.clearAllAppearanceOverrides()
                    },
                    NativeActionButton(String(localized: "Use Default Theme")) { manager.clearActive() }
                ], orientation: .horizontal))
        for theme in manager.installedThemes.values.sorted(by: { $0.manifest.name < $1.manifest.name }) {
            add(
                nativeStack(
                    [
                        NativeActionButton(theme.manifest.name) { manager.setActive(theme.manifest.id) },
                        NativeActionButton(String(localized: "Delete")) { [weak self] in
                            self?.confirmDelete(String(localized: "Delete Theme?")) {
                                do { try manager.deleteTheme(id: theme.manifest.id) } catch { self?.show(error) }
                            }
                        }
                    ], orientation: .horizontal))
        }
    }
}
