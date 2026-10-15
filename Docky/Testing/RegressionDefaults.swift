#if DEBUG
    import Foundation

    /// Preferences for one regression check, kept out of ~/Library/Preferences.
    ///
    /// A suite named like a bundle identifier lives in ~/Library/Preferences.
    /// `removePersistentDomain(forName:)` only empties it, and cfprefsd writes
    /// an empty plist back whenever anything reads the suite later, so every
    /// run left a file behind. CFPreferences treats an absolute path as the
    /// plist's location, so these suites live in the temporary directory.
    struct RegressionDefaults {
        let defaults: UserDefaults
        private let path: String

        init(_ name: String) {
            path = FileManager.default.temporaryDirectory
                .appending(path: "\(name).\(UUID().uuidString)").path
            guard let defaults = UserDefaults(suiteName: path) else {
                preconditionFailure("Isolated defaults required")
            }
            self.defaults = defaults
        }

        func remove() {
            defaults.removePersistentDomain(forName: path)
            try? FileManager.default.removeItem(atPath: path + ".plist")
        }
    }
#endif
