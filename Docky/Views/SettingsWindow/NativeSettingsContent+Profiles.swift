import AppKit

extension NativeSettingsContent {
    static func profileSections(_ context: NativeSettingsContext) -> [NativeSettingsSection] {
        let service = ProfileService.shared
        let add = NativeActionButton(String(localized: "Add Profile…")) {
            Task { await NativeProfileEditor.present(profileID: nil, from: context.sheets) }
        }
        let list = NativeSettingsListSection(
            String(localized: "Profiles"),
            footer: String(
                localized:
                    "Each profile keeps its own pinned apps, widgets, and hidden apps. Triggers switch profiles automatically."),
            emptyText: "", actions: [add])
        list.observe(of: { service.profiles.map(\.id) }) { [weak list] identifiers in
            list?.reconcile(
                identifiers, id: { $0 }, make: { profileRow($0, context: context) }, update: { _, _ in })
        }
        return [
            NativeSettingsSection(rows: [
                NativePreferenceField.toggle(
                    String(localized: "Show Profile Switcher"),
                    description: String(
                        localized: "Shows a strip for switching profiles. It stays hidden while there's only one profile."),
                    get: { !DockyPreferences.shared.hidesProfileStrip },
                    set: { DockyPreferences.shared.hidesProfileStrip = !$0 })
            ]),
            list
        ]
    }

    private struct ProfileRowState: Equatable {
        var name: String
        var symbolName: String
        var triggerCount: Int
        var isActive: Bool
    }

    private static func profileRow(_ identifier: String, context: NativeSettingsContext) -> NativeFormRowView {
        let service = ProfileService.shared
        let row = NativeFormListRow(id: identifier, icon: nil, title: "")
        let makeActive = NativeActionButton(String(localized: "Make Active")) {
            service.setActiveProfile(id: identifier)
        }
        let edit = NativeActionButton("", symbol: "info.circle") {
            Task { await NativeProfileEditor.present(profileID: identifier, from: context.sheets) }
        }
        edit.isBordered = false
        row.setAccessories([makeActive, edit])
        row.observe(
            of: {
                service.profiles.first { $0.id == identifier }.map {
                    ProfileRowState(
                        name: $0.name, symbolName: $0.symbolName, triggerCount: $0.triggers.count,
                        isActive: $0.id == service.activeProfileID)
                }
            },
            perform: { [weak row, weak makeActive, weak edit] state in
                guard let row, let state else { return }
                let icon = NSImage(systemSymbolName: state.symbolName, accessibilityDescription: nil)
                var details: [String] = []
                if state.isActive { details.append(String(localized: "Active")) }
                if state.triggerCount > 0 {
                    details.append(
                        String(
                            localized: "\(state.triggerCount) triggers",
                            comment: "How many triggers switch to a profile automatically"))
                }
                row.update(icon: icon, title: state.name, subtitle: details.joined(separator: " · "))
                row.iconView.contentTintColor = state.isActive ? .controlAccentColor : .secondaryLabelColor
                makeActive?.isHidden = state.isActive
                edit?.setAccessibilityLabel(String(localized: "Edit \(state.name)"))
                edit?.toolTip = String(localized: "Edit Profile")
            })
        return row
    }
}
