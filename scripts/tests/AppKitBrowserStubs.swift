// ContextActionPopover.swift dismisses the Windows taskbar tooltip before it
// shows a menu. The real type lives with the taskbar popups, which pull in the
// theme and preference stack, so this harness compiles a stand-in instead.
@MainActor
final class WindowsTaskbarTooltip {
    static let shared = WindowsTaskbarTooltip()
    func dismiss() {}
}
