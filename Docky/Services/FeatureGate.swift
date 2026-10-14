//
//  FeatureGate.swift
//  Docky
//
//  Centralizes "is this OS-gated feature available?" checks. Each
//  `DockyFeature` declares its minimum macOS version; `FeatureGate`
//  compares against either the running OS or, in DEBUG builds, a
//  user-supplied "preferred" version so we can see how the app looks
//  on an older macOS without booting one — e.g. running on macOS 26
//  but rendering as if we were on 13.5.
//
//  Usage pattern at call sites that invoke version-gated APIs:
//
//      if FeatureGate.shared.isAvailable(.liquidGlass), #available(macOS 26.0, *) {
//          content.glassEffect(.regular, in: shape)
//      } else {
//          content.background(SkyLightGlassFallback(...))
//      }
//
//  Both checks are required: Swift's `#available` is a *syntactic*
//  check the compiler uses to permit calls to gated symbols, so a
//  value-returning function can't replace it. The first half handles
//  the simulated-version override; the second satisfies the compiler.
//  When `isAvailable` returns false (because the simulated version
//  doesn't meet the feature minimum), the `#available` half is moot
//  — control flows into the fallback regardless.
//
//  Setting the simulated version from a shell:
//
//      defaults write gt.quintero.Docky DebugPreferredOSVersion 13.5
//      # then relaunch Docky to re-evaluate
//
//  Clearing it:
//
//      defaults delete gt.quintero.Docky DebugPreferredOSVersion
//

import Foundation

enum DockyFeature: String, CaseIterable, Codable {
    // MARK: macOS 26+
    /// SwiftUI `.glassEffect(...)` Liquid Glass material.
    case liquidGlass
    /// FoundationModels-backed app-folder name suggester
    /// (`AppFolderNamingService.suggestInitialName`).
    case foundationModelsFolderNaming
    /// FoundationModels-backed smart pinned-dock organizer
    /// (`PinnedDockSmartOrganizerService.organize`).
    case foundationModelsSmartOrganize

    // MARK: macOS 15+
    /// `SCStreamConfiguration.captureMicrophone`.
    case streamMicrophoneCapture

    // (Previous macOS 14+ entries were removed when we lifted the
    // deployment target to 14.0 — those APIs are now always-available
    // and don't need a runtime gate.)

    /// Lowest macOS version that satisfies the gate. The
    /// `#available(macOS X.Y, *)` paired with each call site uses the
    /// same numbers — keep them in sync.
    var minimumMacOSVersion: OperatingSystemVersion {
        switch self {
        case .liquidGlass,
             .foundationModelsFolderNaming,
             .foundationModelsSmartOrganize:
            return OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)

        case .streamMicrophoneCapture:
            return OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
        }
    }
}

// Mutable version overrides are protected by `lock`.
final class FeatureGate: @unchecked Sendable {
    static let shared = FeatureGate()

    /// UserDefaults key for the DEBUG-only "pretend we're on version X"
    /// override. Stored as a string like "13.5" or "14.2.1".
    private static let preferredVersionKey = "DebugPreferredOSVersion"

    private let lock = NSLock()
    private var _preferredOSVersion: OperatingSystemVersion?

    private init() {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: Self.preferredVersionKey),
           let parsed = Self.parseVersion(raw) {
            _preferredOSVersion = parsed
        }
        #endif
    }

    /// The simulated macOS version, if one is set. `nil` means the gate
    /// uses the real running OS. Always `nil` in release builds.
    var preferredOSVersion: OperatingSystemVersion? {
        lock.lock()
        defer { lock.unlock() }
        return _preferredOSVersion
    }

    /// True iff the simulated version (or, lacking one, the running OS)
    /// is at least the feature's `minimumMacOSVersion`.
    func isAvailable(_ feature: DockyFeature) -> Bool {
        let target = effectiveOSVersion()
        return Self.compare(target, feature.minimumMacOSVersion) != .orderedAscending
    }

    #if DEBUG
    /// Override the OS version the gate compares against. Pass `nil`
    /// to fall back to the real running OS. Persists across launches
    /// via UserDefaults.
    func setPreferredOSVersion(_ version: OperatingSystemVersion?) {
        lock.lock()
        _preferredOSVersion = version
        lock.unlock()
        if let version {
            UserDefaults.standard.set(Self.formatVersion(version), forKey: Self.preferredVersionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.preferredVersionKey)
        }
    }
    #endif

    private func effectiveOSVersion() -> OperatingSystemVersion {
        lock.lock()
        let preferred = _preferredOSVersion
        lock.unlock()
        return preferred ?? ProcessInfo.processInfo.operatingSystemVersion
    }

    private static func compare(_ lhs: OperatingSystemVersion, _ rhs: OperatingSystemVersion) -> ComparisonResult {
        if lhs.majorVersion != rhs.majorVersion {
            return lhs.majorVersion < rhs.majorVersion ? .orderedAscending : .orderedDescending
        }
        if lhs.minorVersion != rhs.minorVersion {
            return lhs.minorVersion < rhs.minorVersion ? .orderedAscending : .orderedDescending
        }
        if lhs.patchVersion != rhs.patchVersion {
            return lhs.patchVersion < rhs.patchVersion ? .orderedAscending : .orderedDescending
        }
        return .orderedSame
    }

    private static func parseVersion(_ raw: String) -> OperatingSystemVersion? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ".").map(String.init)
        guard let major = parts.first.flatMap(Int.init) else { return nil }
        let minor = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        let patch = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
        return OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: patch)
    }

    private static func formatVersion(_ version: OperatingSystemVersion) -> String {
        if version.patchVersion > 0 {
            return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        }
        return "\(version.majorVersion).\(version.minorVersion)"
    }
}
