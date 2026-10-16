import AppKit

/// Measurements for Settings' grouped form, matched to macOS's grouped `Form`.
@MainActor
enum NativeSettingsMetrics {
    /// The Settings window uses `regular`; the Launchpad inspector and sheets use `compact`.
    enum Style {
        case regular
        case compact

        var margins: NSEdgeInsets {
            switch self {
            case .regular: NSEdgeInsets(top: 20, left: 40, bottom: 24, right: 40)
            case .compact: NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
            }
        }

        var sectionSpacing: CGFloat {
            switch self {
            case .regular: 20
            case .compact: 16
            }
        }
    }

    static let headerSpacing: CGFloat = 6
    static let footerSpacing: CGFloat = 6
    static let headerInset: CGFloat = 10
    static let boxCornerRadius: CGFloat = 10
    static let rowHorizontalPadding: CGFloat = 10
    static let rowVerticalPadding: CGFloat = 7
    static let rowMinimumHeight: CGFloat = 36
    static let titleSpacing: CGFloat = 16
    static let controlSpacing: CGFloat = 8
    static let listIconSize: CGFloat = 24
    static let listSeparatorInset: CGFloat = rowHorizontalPadding + listIconSize + controlSpacing
    static let sliderWidth: CGFloat = 160
    static let numberFieldWidth: CGFloat = 52
    static let switchControlSize: NSControl.ControlSize = .mini

    static var headerFont: NSFont { .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold) }
    static var titleFont: NSFont { .systemFont(ofSize: NSFont.systemFontSize) }
    static var detailFont: NSFont { .systemFont(ofSize: NSFont.smallSystemFontSize) }
    static var valueFont: NSFont { .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular) }
    static var boxFill: NSColor { .quinarySystemFill }
    static var boxBorder: NSColor { .separatorColor.withAlphaComponent(0.5) }
}
