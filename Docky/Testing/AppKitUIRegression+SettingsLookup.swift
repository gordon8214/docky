#if DEBUG
    import AppKit

    extension NSView {
        /// Every descendant of type `V`, breadth first.
        func regressionDescendants<V: NSView>(_ type: V.Type = V.self) -> [V] {
            var found: [V] = []
            var queue = subviews
            while !queue.isEmpty {
                let view = queue.removeFirst()
                if let match = view as? V { found.append(match) }
                queue += view.subviews
            }
            return found
        }
    }

    /// Finds Settings rows and controls by what VoiceOver reads, so checks don't
    /// depend on how sections nest their rows.
    @MainActor
    enum SettingsLookup {
        static func row(_ label: String, in root: NSView) -> NativeFormRow? {
            root.regressionDescendants(NativeFormRow.self).first { $0.accessibilityLabel() == label }
        }

        /// The first control of type `C` in the row titled `label`.
        static func control<C: NSView>(_ type: C.Type, inRow label: String, in root: NSView) -> C? {
            row(label, in: root)?.accessoryStack.regressionDescendants(C.self).first
        }

        /// The control whose accessibility label is `label`.
        static func control<C: NSView>(_ type: C.Type, labeled label: String, in root: NSView) -> C? {
            root.regressionDescendants(C.self).first { $0.accessibilityLabel() == label }
        }

        static func control<C: NSView>(_ type: C.Type, identifier: String, in root: NSView) -> C? {
            root.regressionDescendants(C.self).first { $0.identifier?.rawValue == identifier }
        }

        static func editableField(inRow label: String, in root: NSView) -> NSTextField? {
            row(label, in: root)?.accessoryStack.regressionDescendants(NSTextField.self).first(where: \.isEditable)
        }

        /// Fails when a visible view in `root` has an ambiguous layout.
        static func assertUnambiguous(_ root: NSView, _ context: String) {
            for view in [root] + root.regressionDescendants() where !view.isHiddenOrHasHiddenAncestor {
                guard view.hasAmbiguousLayout else { continue }
                var ancestry: [String] = []
                var ancestor = view.superview
                while let current = ancestor, ancestry.count < 5 {
                    ancestry.append("\(type(of: current))")
                    ancestor = current.superview
                }
                let contents = ((view as? NSStackView)?.arrangedSubviews ?? view.subviews).map { "\(type(of: $0))" }
                // Moving within the ambiguity shows which axis is underdetermined.
                let before = view.frame
                view.exerciseAmbiguityInLayout()
                view.superview?.layoutSubtreeIfNeeded()
                preconditionFailure(
                    "\(context): \(type(of: view)) has an ambiguous layout, in \(ancestry), holding \(contents), "
                        + "frame \(before) moves to \(view.frame)")
            }
        }
    }
#endif
