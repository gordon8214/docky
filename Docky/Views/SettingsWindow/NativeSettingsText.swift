import AppKit

/// A label that wraps to whatever width Auto Layout gives it.
final class NativeWrappingLabel: NSTextField {
    private var relayoutPending = false

    init(
        _ text: String = "", font: NSFont = NativeSettingsMetrics.titleFont, color: NSColor = .labelColor,
        selectable: Bool = false
    ) {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = selectable
        isBezeled = false
        isBordered = false
        drawsBackground = false
        lineBreakMode = .byWordWrapping
        maximumNumberOfLines = 0
        cell?.wraps = true
        cell?.isScrollable = false
        stringValue = text
        self.font = font
        textColor = color
        translatesAutoresizingMaskIntoConstraints = false
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // Below a stack's own spacing priority, so a label takes free width rather than tying with the gap.
        setContentHuggingPriority(.init(100), for: .horizontal)
        setContentHuggingPriority(.defaultHigh, for: .vertical)
    }

    required init?(coder: NSCoder) { nil }

    /// The height the text needs at the label's current width, measured the way
    /// the cell draws it. `preferredMaxLayoutWidth` alone can round to one line
    /// fewer than the cell draws when the text nearly fits.
    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        guard bounds.width > 0, let cell else { return size }
        let bounds = NSRect(x: 0, y: 0, width: bounds.width, height: .greatestFiniteMagnitude)
        return NSSize(width: size.width, height: ceil(cell.cellSize(forBounds: bounds).height))
    }

    /// A leaf view isn't sent `layout()` when only its width changes, so this
    /// follows the frame to keep the wrapped height current.
    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(frame.width - newSize.width) > 0.5
        super.setFrameSize(newSize)
        guard widthChanged else { return }
        preferredMaxLayoutWidth = newSize.width
        // AppKit sets frames partway through a layout pass, so the new height
        // wouldn't apply until something else changed. Ask for another pass, once
        // per turn however many times the width changes, as during a live resize.
        guard !relayoutPending else { return }
        relayoutPending = true
        DispatchQueue.main.async { [weak self] in
            self?.relayoutPending = false
            self?.invalidateIntrinsicContentSize()
            self?.superview?.needsLayout = true
        }
    }
}

/// A single-line secondary label for a row's value, like "0.50 s" or "Connected".
@MainActor
func nativeValueLabel(_ text: String = "") -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = NativeSettingsMetrics.valueFont
    label.textColor = .secondaryLabelColor
    label.lineBreakMode = .byTruncatingMiddle
    label.translatesAutoresizingMaskIntoConstraints = false
    // A value truncates before a row's title starts wrapping.
    label.setContentCompressionResistancePriority(.init(200), for: .horizontal)
    return label
}
