import AppKit
import UniformTypeIdentifiers

extension NativeIconSettingsController {
    /// The selected item's preview, custom image, and padding.
    func editorSections(for item: Item) -> [NativeSettingsSection] {
        let preferences = DockyPreferences.shared
        let target = item.target
        let preview = NSImageView()
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            preview.widthAnchor.constraint(equalToConstant: 64), preview.heightAnchor.constraint(equalToConstant: 64)
        ])
        let name = NativeWrappingLabel(item.title, font: .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold))
        let status = NativeWrappingLabel(font: NativeSettingsMetrics.detailFont, color: .secondaryLabelColor)
        let text = NSStackView(views: [name, status])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        text.translatesAutoresizingMaskIntoConstraints = false
        text.setHuggingPriority(.defaultHigh, for: .vertical)
        // The labels sit together, centered beside the preview, which sets the height.
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(preview)
        header.addSubview(text)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            preview.topAnchor.constraint(equalTo: header.topAnchor),
            preview.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            text.leadingAnchor.constraint(equalTo: preview.trailingAnchor, constant: 12),
            text.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            text.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            text.topAnchor.constraint(greaterThanOrEqualTo: header.topAnchor)
        ])
        let headerRow = NativeFormContentRow(header)
        let choose = NativeActionButton(String(localized: "Choose Image…")) { [weak self] in
            Task {
                guard let path = await self?.sheets.chooseFile([.image])?.path else { return }
                switch target {
                case .app(let identifier): preferences.setAppIconOverride(bundleIdentifier: identifier, iconPath: path)
                case .folder(let folder): preferences.setFolderIconOverride(folderPath: folder, iconPath: path)
                case .trash(let state): preferences.setTrashIconOverride(state: state, iconPath: path)
                }
            }
        }
        let reset = NativeActionButton(String(localized: "Use Default")) {
            switch target {
            case .app(let identifier): preferences.removeAppIconOverride(bundleIdentifier: identifier)
            case .folder(let folder): preferences.removeFolderIconOverride(folderPath: folder)
            case .trash(let state): preferences.removeTrashIconOverride(state: state)
            }
        }
        let imageRow = NativeFormRow(title: String(localized: "Image"), control: choose, accessories: [reset])
        let padding = NativePreferenceField.slider(
            String(localized: "Padding"),
            get: { Double(Self.padding(for: target)) },
            set: { value in
                switch target {
                case .app(let identifier):
                    preferences.setAppIconPaddingFraction(bundleIdentifier: identifier, paddingFraction: CGFloat(value))
                case .folder(let folder):
                    preferences.setFolderIconPaddingFraction(folderPath: folder, paddingFraction: CGFloat(value))
                case .trash(let state):
                    preferences.setTrashIconPaddingFraction(state: state, paddingFraction: CGFloat(value))
                }
            }, range: 0...0.5, step: 0.01, format: .percent)
        headerRow.observe { [weak self, weak preview, weak status, weak reset, weak padding] in
            let path = Self.overridePath(for: target)
            preview?.image = self?.icon(for: target, size: 64)
            status?.stringValue =
                path.map {
                    String(localized: "Custom image: \(FileManager.default.displayName(atPath: $0))")
                } ?? String(localized: "Default icon")
            reset?.isEnabled = path != nil
            padding?.isEnabled = path != nil
            self?.refreshIcon(for: target)
        }
        return [
            NativeSettingsSection(rows: [headerRow]),
            NativeSettingsSection(
                String(localized: "Custom Image"),
                footer: String(localized: "Padding adds space around a custom image that fills its tile edge to edge."),
                rows: [imageRow, padding])
        ]
    }

    /// The icon the taskbar shows for `target`: its custom image, or the default.
    func icon(for target: IconTarget, size: CGFloat) -> NSImage? {
        let preferences = DockyPreferences.shared
        let icons = IconCacheService.shared
        let image: NSImage?
        switch target {
        case .app(let identifier):
            image =
                preferences.effectiveAppIconOverrideURL(forBundleIdentifier: identifier).flatMap(icons.image(forImageFileURL:))
                ?? icons.icon(forBundleIdentifier: identifier)
        case .folder(let folder):
            image =
                preferences.effectiveFolderIconOverrideURL(forPath: folder).flatMap(icons.image(forImageFileURL:))
                ?? icons.icon(forFileURL: URL(fileURLWithPath: folder))
        case .trash(let state):
            image =
                preferences.effectiveTrashIconOverrideURL(forState: state).flatMap(icons.image(forImageFileURL:))
                ?? NSImage(named: state.systemImageName)
        }
        let copy = image?.copy() as? NSImage
        copy?.size = CGSize(width: size, height: size)
        return copy
    }

    static func overridePath(for target: IconTarget) -> String? {
        let preferences = DockyPreferences.shared
        switch target {
        case .app(let identifier): return preferences.appIconOverride(forBundleIdentifier: identifier)?.iconPath
        case .folder(let folder): return preferences.folderIconOverride(forPath: folder)?.iconPath
        case .trash(let state): return preferences.trashIconOverride(forState: state)?.iconPath
        }
    }

    private static func padding(for target: IconTarget) -> CGFloat {
        let preferences = DockyPreferences.shared
        switch target {
        case .app(let identifier): return preferences.appIconOverridePadding(forBundleIdentifier: identifier)
        case .folder(let folder): return preferences.folderIconOverridePadding(forPath: folder)
        case .trash(let state): return preferences.trashIconOverridePadding(forState: state)
        }
    }
}
