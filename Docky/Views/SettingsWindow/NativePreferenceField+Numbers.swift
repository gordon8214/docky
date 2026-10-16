import AppKit

/// How a slider or stepper shows its value.
enum NativeValueFormat: Sendable {
    case seconds
    case percent
    case points
    case plain

    var fractionDigits: Int {
        switch self {
        case .seconds: 2
        case .percent, .points, .plain: 0
        }
    }

    /// The unit a stepper shows after its field.
    var unit: String? {
        switch self {
        case .points: String(localized: "pt", comment: "Abbreviation for points, a unit of size")
        case .seconds, .percent, .plain: nil
        }
    }

    func string(_ value: Double) -> String {
        switch self {
        case .seconds:
            let number = value.formatted(.number.precision(.fractionLength(2)))
            return String(localized: "\(number) s", comment: "A duration in seconds, like 0.50 s")
        case .percent:
            return value.formatted(.percent.precision(.fractionLength(0)))
        case .points:
            let number = value.formatted(.number.precision(.fractionLength(0)))
            return String(localized: "\(number) pt", comment: "A size in points, like 128 pt")
        case .plain:
            return value.formatted(.number.precision(.fractionLength(0)))
        }
    }
}

extension NativePreferenceField {
    static func slider<Value: BinaryFloatingPoint & Sendable>(
        _ title: String, description: String? = nil, _ key: ReferenceWritableKeyPath<DockyPreferences, Value>,
        range: ClosedRange<Double>, step: Double, format: NativeValueFormat
    ) -> NativeFormRow {
        slider(
            title, description: description, get: { Double(DockyPreferences.shared[keyPath: key]) },
            set: { DockyPreferences.shared[keyPath: key] = Value($0) }, range: range, step: step, format: format)
    }

    /// A slider with its value beside it. Values snap to `step`.
    static func slider(
        _ title: String, description: String? = nil, get: @escaping @MainActor () -> Double,
        set: @escaping @MainActor (Double) -> Void, range: ClosedRange<Double>, step: Double,
        format: NativeValueFormat
    ) -> NativeFormRow {
        let slider = NSSlider(
            value: get(), minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        let width = slider.widthAnchor.constraint(equalToConstant: NativeSettingsMetrics.sliderWidth)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([width, slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 100)])
        let value = nativeValueLabel()
        value.alignment = .right
        // Size the label for the widest value, so the slider doesn't shift while it moves.
        let widest = [range.lowerBound, range.upperBound].map {
            (format.string($0) as NSString).size(withAttributes: [.font: NativeSettingsMetrics.valueFont]).width
        }.max() ?? 0
        value.widthAnchor.constraint(equalToConstant: ceil(widest) + 4).isActive = true
        let row = NativeFormRow(title: title, description: description, control: slider, accessories: [value])
        let show: @MainActor (Double) -> Void = { [weak slider, weak value] number in
            value?.stringValue = format.string(number)
            slider?.setAccessibilityValueDescription(format.string(number))
        }
        row.bind(slider) {
            let snapped = min(range.upperBound, max(range.lowerBound, (slider.doubleValue / step).rounded() * step))
            set(snapped)
            show(snapped)
        }
        row.observe { [weak slider] in
            let number = get()
            slider?.doubleValue = number
            show(number)
        }
        return row
    }

    static func stepper<Value: BinaryFloatingPoint & Sendable>(
        _ title: String, description: String? = nil, _ key: ReferenceWritableKeyPath<DockyPreferences, Value>,
        range: ClosedRange<Double>, step: Double = 1, format: NativeValueFormat = .plain
    ) -> NativeFormRow {
        stepper(
            title, description: description, get: { Double(DockyPreferences.shared[keyPath: key]) },
            set: { DockyPreferences.shared[keyPath: key] = Value($0) }, range: range, step: step, format: format)
    }

    static func stepper<Value: BinaryInteger & Sendable>(
        _ title: String, description: String? = nil, _ key: ReferenceWritableKeyPath<DockyPreferences, Value>,
        range: ClosedRange<Double>, step: Double = 1, format: NativeValueFormat = .plain
    ) -> NativeFormRow {
        stepper(
            title, description: description, get: { Double(DockyPreferences.shared[keyPath: key]) },
            set: { DockyPreferences.shared[keyPath: key] = Value($0.rounded()) }, range: range, step: step,
            format: format)
    }

    /// A number field with a stepper. Typed values save when the field loses
    /// focus, not only on Return, snapped to `step` and clamped to `range`.
    static func stepper(
        _ title: String, description: String? = nil, get: @escaping @MainActor () -> Double,
        set: @escaping @MainActor (Double) -> Void, range: ClosedRange<Double>, step: Double = 1,
        format: NativeValueFormat = .plain
    ) -> NativeFormRow {
        precondition(format != .percent, "The field shows whole numbers; use a slider for a percentage")
        let field = NSTextField()
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = format.fractionDigits
        formatter.isLenient = true
        // No minimum or maximum: the formatter would refuse to end editing on
        // out-of-range input, so closing Settings couldn't save it. The action clamps instead.
        field.formatter = formatter
        field.alignment = .right
        field.cell?.sendsActionOnEndEditing = true
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: NativeSettingsMetrics.numberFieldWidth).isActive = true
        let stepper = NSStepper()
        stepper.minValue = range.lowerBound
        stepper.maxValue = range.upperBound
        stepper.increment = step
        stepper.valueWraps = false
        stepper.autorepeat = true
        var accessories: [NSView] = []
        if let unit = format.unit {
            let label = NSTextField(labelWithString: unit)
            label.textColor = .secondaryLabelColor
            accessories.append(label)
        }
        accessories.append(stepper)
        let row = NativeFormRow(title: title, description: description, control: field, accessories: accessories)
        stepper.setAccessibilityLabel(title)
        // What the field last showed. Ending an edit sends the field's action even
        // when nothing was typed, and while the field is being edited it doesn't
        // follow outside changes, so only a changed entry may save.
        let shown = NativeShownNumber()
        let show: @MainActor (Double) -> Void = { [weak field, weak stepper] number in
            field?.doubleValue = number
            stepper?.doubleValue = number
            shown.value = number
        }
        let commit: @MainActor (Double) -> Void = { number in
            set(min(range.upperBound, max(range.lowerBound, (number / step).rounded() * step)))
            // The stored value may not change (an out-of-range entry clamps to the
            // current value), and then no observation fires, so re-sync here.
            show(get())
        }
        row.bind(field) {
            // An empty, unreadable, or unchanged entry puts back the stored value.
            guard let typed = (field.objectValue as? NSNumber)?.doubleValue, typed != shown.value else {
                show(get())
                return
            }
            commit(typed)
        }
        row.bind(stepper) { commit(stepper.doubleValue) }
        row.observe { [weak field, weak stepper] in
            let number = get()
            if field?.currentEditor() == nil {
                field?.doubleValue = number
                shown.value = number
            }
            stepper?.doubleValue = number
        }
        return row
    }
}

/// The number a stepper row's field last showed.
@MainActor
private final class NativeShownNumber {
    var value = Double.nan
}
