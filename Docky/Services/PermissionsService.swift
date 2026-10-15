//
//  PermissionsService.swift
//  Docky
//
//  Tracks the remaining macOS permissions Docky needs:
//    - .userFolders       → Full Disk Access for pinned folder previews
//    - .finderAutomation       → Finder Apple Events for Finder-backed actions
//    - .accessibility          → inspect and restore minimized windows
//    - .systemEventsAutomation → System Events Apple Events for menu-click actions
//    - .screenCapture     → minimized window previews
//
//  Required file-system access is granted through Full Disk Access (FDA),
//  probed via an attempted read of a TCC-protected directory
//  (inket/FullDiskAccess approach).
//

import AppKit
import ApplicationServices
import Combine
import CoreLocation

@MainActor
final class PermissionsService: ObservableObject {
    static let shared = PermissionsService()

    @Published private(set) var userFolders: PermissionStatus = .notDetermined
    @Published private(set) var userFoldersGrantMethod: GrantMethod?

    @Published private(set) var finderAutomation: PermissionStatus = .notDetermined
    @Published private(set) var finderAutomationGrantMethod: GrantMethod?

    @Published private(set) var accessibility: PermissionStatus = .notDetermined
    @Published private(set) var accessibilityGrantMethod: GrantMethod?

    @Published private(set) var systemEventsAutomation: PermissionStatus = .notDetermined
    @Published private(set) var systemEventsAutomationGrantMethod: GrantMethod?

    @Published private(set) var screenCapture: PermissionStatus = .notDetermined
    @Published private(set) var screenCaptureGrantMethod: GrantMethod?

    @Published private(set) var location: PermissionStatus = .notDetermined
    @Published private(set) var locationGrantMethod: GrantMethod?

    @Published private(set) var calendar: PermissionStatus = .notDetermined
    @Published private(set) var reminders: PermissionStatus = .notDetermined

    private let dockBookmarkKey = "docky.dockPlistBookmark"
    private let userFoldersBookmarkKey = "docky.userFoldersBookmark"
    private let finderAutomationStatusKey = "docky.finderAutomationStatus"
    private let systemEventsAutomationStatusKey = "docky.systemEventsAutomationStatus"
    private let initialOnboardingCompletedKey = "docky.initialOnboardingCompleted"
    private let skippedPermissionsKey = "docky.skippedPermissions"

    private init() {
        clearLegacyBookmarks()
        refresh()
    }

    // MARK: - Status

    func status(for permission: Permission) -> PermissionStatus {
        switch permission {
        case .userFolders: return userFolders
        case .finderAutomation: return finderAutomation
        case .accessibility: return accessibility
        case .systemEventsAutomation: return systemEventsAutomation
        case .screenCapture: return screenCapture
        case .location: return location
        case .calendar: return calendar
        case .reminders: return reminders
        }
    }

    var missingPermissions: [Permission] {
        Permission.allCases.filter { status(for: $0) != .granted }
    }

    var missingRequiredPermissions: [Permission] {
        Permission.allCases.filter { $0.isRequiredAtLaunch && status(for: $0) != .granted }
    }

    var setupPermissions: [Permission] {
        Permission.allCases.filter {
            guard $0.appearsInOnboarding else {
                return false
            }

            if hasSkippedPermission($0) {
                return false
            }

            if $0.isRequiredAtLaunch {
                return status(for: $0) != .granted
            }

            if hasCompletedInitialOnboarding {
                return false
            }

            return status(for: $0) == .notDetermined
        }
    }

    var allGranted: Bool { missingPermissions.isEmpty }

    var allRequiredGranted: Bool { missingRequiredPermissions.isEmpty }

    var setupComplete: Bool { setupPermissions.isEmpty }

    var hasCompletedInitialOnboarding: Bool {
        UserDefaults.standard.bool(forKey: initialOnboardingCompletedKey)
    }

    func refresh() {
        let fdaGranted = checkFullDiskAccess()
        refreshUserFolders(fdaGranted: fdaGranted)
        refreshFinderAutomation()
        refreshAccessibility()
        refreshSystemEventsAutomation()
        refreshScreenCapture()
        refreshLocation()
        refreshCalendar()
        refreshReminders()
    }

    func markInitialOnboardingCompleted() {
        UserDefaults.standard.set(true, forKey: initialOnboardingCompletedKey)
    }

    func markPermissionSkipped(_ permission: Permission) {
        var skippedPermissions = skippedPermissionIDs
        skippedPermissions.insert(permission.rawValue)
        UserDefaults.standard.set(Array(skippedPermissions), forKey: skippedPermissionsKey)
    }

    func hasSkippedPermission(_ permission: Permission) -> Bool {
        skippedPermissionIDs.contains(permission.rawValue)
    }

    // MARK: - Grant actions

    private var skippedPermissionIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: skippedPermissionsKey) ?? [])
    }

    func openSystemSettings(for permission: Permission) {
        guard let url = permission.systemSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    func requestPermission(for permission: Permission) async -> Bool {
        switch permission {
        case .finderAutomation:
            return await AppleScriptService.shared.requestFinderAutomationPermission()
        case .accessibility:
            return requestAccessibilityPermission(prompt: true)
        case .systemEventsAutomation:
            return await AppleScriptService.shared.requestSystemEventsAutomationPermission()
        case .screenCapture:
            return requestScreenCapturePermission()
        case .location:
            let granted = await WeatherService.shared.requestAccess()
            refreshLocation()
            return granted
        case .calendar:
            let granted = await CalendarService.shared.requestAccess()
            refreshCalendar()
            return granted
        case .reminders:
            let granted = await RemindersService.shared.requestAccess()
            refreshReminders()
            return granted
        case .userFolders:
            return false
        }
    }

    func clearAutomationStatus(for permission: Permission) {
        switch permission {
        case .finderAutomation:
            UserDefaults.standard.removeObject(forKey: finderAutomationStatusKey)
            refreshFinderAutomation()
        case .systemEventsAutomation:
            UserDefaults.standard.removeObject(forKey: systemEventsAutomationStatusKey)
            refreshSystemEventsAutomation()
        case .userFolders, .accessibility, .screenCapture, .location, .calendar, .reminders:
            break
        }
    }

    @discardableResult
    func requestAccessibilityPermission(prompt: Bool) -> Bool {
        // The SDK exposes this immutable key as a mutable C global.
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        refreshAccessibility()
        return granted
    }

    @discardableResult
    func requestScreenCapturePermission() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        refreshScreenCapture()
        return granted
    }

    func presentPermissionAlert(for permission: Permission, actionTitle: String) {
        let alert = NSAlert()
        alert.messageText = permission.title + " is required"
        alert.informativeText = "Allow Docky in Privacy & Security so it can perform \(actionTitle.lowercased())."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            openSystemSettings(for: permission)
        }
    }

    // MARK: - User folders permission

}

extension PermissionsService {
    private func refreshUserFolders(fdaGranted: Bool) {
        if fdaGranted {
            userFoldersGrantMethod = .fullDiskAccess
            userFolders = .granted
            return
        }
        userFoldersGrantMethod = nil
        userFolders = .denied
    }

    // MARK: - Finder automation permission

    func updateFinderAutomation(status: PermissionStatus) {
        switch status {
        case .granted:
            UserDefaults.standard.set("granted", forKey: finderAutomationStatusKey)
            finderAutomationGrantMethod = .automation
        case .denied:
            UserDefaults.standard.set("denied", forKey: finderAutomationStatusKey)
            finderAutomationGrantMethod = nil
        case .notDetermined:
            UserDefaults.standard.removeObject(forKey: finderAutomationStatusKey)
            finderAutomationGrantMethod = nil
        }
        finderAutomation = status
    }

    private func refreshFinderAutomation() {
        switch UserDefaults.standard.string(forKey: finderAutomationStatusKey) {
        case "granted":
            finderAutomation = .granted
            finderAutomationGrantMethod = .automation
        case "denied":
            finderAutomation = .denied
            finderAutomationGrantMethod = nil
        default:
            finderAutomation = .notDetermined
            finderAutomationGrantMethod = nil
        }
    }

    func updateSystemEventsAutomation(status: PermissionStatus) {
        switch status {
        case .granted:
            UserDefaults.standard.set("granted", forKey: systemEventsAutomationStatusKey)
            systemEventsAutomationGrantMethod = .automation
        case .denied:
            UserDefaults.standard.set("denied", forKey: systemEventsAutomationStatusKey)
            systemEventsAutomationGrantMethod = nil
        case .notDetermined:
            UserDefaults.standard.removeObject(forKey: systemEventsAutomationStatusKey)
            systemEventsAutomationGrantMethod = nil
        }
        systemEventsAutomation = status
    }

    private func refreshSystemEventsAutomation() {
        switch UserDefaults.standard.string(forKey: systemEventsAutomationStatusKey) {
        case "granted":
            systemEventsAutomation = .granted
            systemEventsAutomationGrantMethod = .automation
        case "denied":
            systemEventsAutomation = .denied
            systemEventsAutomationGrantMethod = nil
        default:
            systemEventsAutomation = .notDetermined
            systemEventsAutomationGrantMethod = nil
        }
    }

    private func refreshAccessibility() {
        let granted = AXIsProcessTrusted()
        accessibility = granted ? .granted : .denied
        accessibilityGrantMethod = granted ? .accessibility : nil
    }

    private func refreshScreenCapture() {
        let granted = CGPreflightScreenCaptureAccess()
        screenCapture = granted ? .granted : .denied
        screenCaptureGrantMethod = granted ? .screenCapture : nil
    }

    private func refreshLocation() {
        WeatherService.shared.refreshAuthorizationStatus()

        if WeatherService.shared.hasLocationAuthorization {
            location = .granted
            locationGrantMethod = .location
            return
        }

        switch WeatherService.shared.authorizationStatus {
        case .notDetermined:
            location = .notDetermined
            locationGrantMethod = nil
        case .denied, .restricted:
            location = .denied
            locationGrantMethod = nil
        case .authorizedAlways:
            location = .granted
            locationGrantMethod = .location
        @unknown default:
            location = .denied
            locationGrantMethod = nil
        }
    }

    private func refreshCalendar() {
        CalendarService.shared.refreshAuthorizationStatus()
        calendar = CalendarService.shared.permissionStatus
    }

    private func refreshReminders() {
        RemindersService.shared.refreshAuthorizationStatus()
        reminders = RemindersService.shared.permissionStatus
    }

    // MARK: - Full Disk Access probe

    private func checkFullDiskAccess() -> Bool {
        let probePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.apple.stocks")
            .path
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: probePath)
            return true
        } catch {
            return false
        }
    }

    private func clearLegacyBookmarks() {
        UserDefaults.standard.removeObject(forKey: dockBookmarkKey)
        UserDefaults.standard.removeObject(forKey: userFoldersBookmarkKey)
    }
}
