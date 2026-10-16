import AppKit

extension NativeSettingsContent {
    static func widgetSections() -> [NativeSettingsSection] {
        let preferences = { DockyPreferences.shared }
        let previews: @MainActor () -> Bool = { preferences().enablesWidgetHoverPreview }
        let sizes = TileSpan.allCases.filter { $0 != .four }.map { span in
            NativePreferenceField.toggle(
                widgetSizeTitle(span),
                get: { preferences().widgetHoverPreviewSpans.contains(span) },
                set: { isOn in
                    if isOn {
                        preferences().widgetHoverPreviewSpans.insert(span)
                    } else {
                        preferences().widgetHoverPreviewSpans.remove(span)
                    }
                }
            ).enabled(when: previews)
        }
        return [
            NativeSettingsSection(
                String(localized: "Expanded Preview"),
                rows: [
                    NativePreferenceField.toggle(
                        String(localized: "Show Expanded Preview on Hover"),
                        description: String(
                            localized:
                                "When enabled, hovering an expandable widget tile shows a larger preview in a separate window. Turn this off to keep widgets at their pinned size."),
                        \.enablesWidgetHoverPreview),
                    NativePreferenceField.slider(
                        String(localized: "Hover Preview Delay"),
                        description: String(
                            localized:
                                "Time the cursor must rest on a widget before its expanded preview window appears. Set to zero for an immediate preview."),
                        \.widgetHoverPreviewDelay, range: 0...2, step: 0.05, format: .seconds
                    ).enabled(when: previews)
                ]),
            NativeSettingsSection(
                String(localized: "Apply To Sizes"),
                footer: String(
                    localized:
                        "Choose which tile sizes trigger the expanded preview. Widgets pinned at other sizes stay at their pinned size on hover."),
                rows: sizes)
        ]
    }

    private static func widgetSizeTitle(_ span: TileSpan) -> String {
        switch span {
        case .one: String(localized: "Small")
        case .two: String(localized: "Medium")
        case .three: String(localized: "Large")
        case .four: String(localized: "Extra Large")
        }
    }
}
