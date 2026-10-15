//
//  FileBrowser.swift
//  Docky
//
//  The app that folder, reveal and Trash actions go to. `FileBrowserService`
//  resolves the preference against what is installed and performs the actions.
//

import Foundation

enum FileBrowser: String, CaseIterable, Identifiable {
    case finder
    case betterFinder

    var id: String { rawValue }

    var bundleIdentifier: String {
        switch self {
        case .finder: "com.apple.finder"
        case .betterFinder: "com.gordonbyrnes.BetterFinder"
        }
    }

    /// The app's name. Brand names aren't localized.
    var displayName: String {
        switch self {
        case .finder: "Finder"
        case .betterFinder: "BetterFinder"
        }
    }

    // Each title is a literal per case so the existing Finder translations keep applying.

    var openInTitle: String {
        switch self {
        case .finder: String(localized: "Open in Finder")
        case .betterFinder: String(localized: "Open in BetterFinder")
        }
    }

    var revealInTitle: String {
        switch self {
        case .finder: String(localized: "Reveal in Finder")
        case .betterFinder: String(localized: "Reveal in BetterFinder")
        }
    }

    var showInTitle: String {
        switch self {
        case .finder: String(localized: "Show in Finder")
        case .betterFinder: String(localized: "Show in BetterFinder")
        }
    }

    var windowTitle: String {
        switch self {
        case .finder: String(localized: "Finder Window")
        case .betterFinder: String(localized: "BetterFinder Window")
        }
    }

    /// `betterfinder://reveal?path=<absolute path>`, which selects the item in its parent folder
    /// even when the item is a folder. Opening a folder's file URL would open the folder instead.
    ///
    /// The path is percent-encoded by hand, with `&`, `=`, `+` and `#` always escaped, because
    /// `URLComponents.queryItems` leaves `+` as is and some query parsers read it as a space.
    static func betterFinderRevealURL(for url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        let path = url.standardizedFileURL.path
        guard path.hasPrefix("/") else { return nil }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#")
        guard let encodedPath = path.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        var components = URLComponents()
        components.scheme = "betterfinder"
        components.host = "reveal"
        components.percentEncodedQueryItems = [URLQueryItem(name: "path", value: encodedPath)]
        return components.url
    }
}
