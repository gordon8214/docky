//
//  DockPlistReader.swift
//  Docky
//
//  Shared read path for the com.apple.dock preferences. Stateless helper used
//  by DockSettingsService and TileStore so the key list lives in exactly one
//  place.
//

import Foundation

enum DockPlistReader {
    private static let domain = "com.apple.dock"
    private static let keys: [String] = [
        "orientation", "tilesize", "largesize", "magnification",
        "autohide", "autohide-delay", "autohide-time-modifier",
        "mineffect", "minimize-to-application",
        "show-recents", "show-process-indicators",
        "persistent-apps", "persistent-others"
    ]

    /// Full dock settings dictionary. Nil when the domain can't be read.
    static func read() -> [String: Any]? {
        let domain = domain as CFString
        CFPreferencesAppSynchronize(domain)
        guard let values = CFPreferencesCopyMultiple(
            keys.map { $0 as CFString } as CFArray,
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? [String: Any] else {
            return nil
        }
        return values.isEmpty ? nil : values
    }
}
