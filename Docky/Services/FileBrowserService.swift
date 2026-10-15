//
//  FileBrowserService.swift
//  Docky
//
//  Sends folder, reveal and Trash actions to the file browser chosen in
//  Settings. Finder keeps its existing mechanisms: AppleScript for opening
//  folders and the Trash, and NSWorkspace for reveal. BetterFinder takes file
//  URLs through LaunchServices, so it needs no Automation permission. A file
//  URL opens a folder or selects a file in its parent; selecting a folder in
//  its parent needs the betterfinder://reveal URL.
//

import AppKit
import OSLog

private let fileBrowserLogger = Logger(subsystem: "gt.quintero.Docky", category: "FileBrowser")

@MainActor
final class FileBrowserService {
    static let shared = FileBrowserService()

    #if DEBUG
        /// Lets the UI regression check both the installed and the missing BetterFinder states.
        static var installedOverride: ((FileBrowser) -> Bool)?
    #endif

    private init() {}

    /// The chosen file browser, or Finder when the chosen app isn't installed.
    var current: FileBrowser {
        let preferred = DockyPreferences.shared.fileBrowser
        return isInstalled(preferred) ? preferred : .finder
    }

    func isInstalled(_ browser: FileBrowser) -> Bool {
        #if DEBUG
            if let installedOverride = Self.installedOverride { return installedOverride(browser) }
        #endif
        return browser == .finder || NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleIdentifier) != nil
    }

    /// Whether the URL leads to a folder to browse rather than a file or package to open with
    /// its app. Follows symbolic links, as the file browsers do when they open one.
    static func isFolder(_ url: URL) -> Bool {
        let values = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    @discardableResult
    func openFolder(_ url: URL) async -> Bool {
        switch current {
        case .finder:
            return await AppleScriptService.shared.openFinderWindow(for: url)
        case .betterFinder:
            return openInBetterFinder(url)
        }
    }

    /// Selects the item in its parent folder.
    @discardableResult
    func reveal(_ url: URL) -> Bool {
        switch current {
        case .finder:
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return true
        case .betterFinder:
            // BetterFinder opens a folder's file URL, and a link to a folder, instead of selecting it.
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey])
            let isFolderOrLink =
                values?.isSymbolicLink == true || (values?.isDirectory == true && values?.isPackage != true)
            guard isFolderOrLink else { return openInBetterFinder(url) }
            guard let revealURL = FileBrowser.betterFinderRevealURL(for: url) else {
                fileBrowserLogger.error("No BetterFinder reveal URL for \(url.path, privacy: .private)")
                return false
            }
            return openInBetterFinder(revealURL)
        }
    }

    @discardableResult
    func openTrash() async -> Bool {
        switch current {
        case .finder:
            return await AppleScriptService.shared.openTrash()
        case .betterFinder:
            do {
                let trashURL = try FileManager.default.url(
                    for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                return openInBetterFinder(trashURL)
            } catch {
                fileBrowserLogger.error("Couldn't locate the Trash: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
    }

    /// Hands the URL to BetterFinder and returns whether the request went out. A failure to open
    /// it is reported in an alert, as Finder's AppleScript failures are.
    private func openInBetterFinder(_ url: URL) -> Bool {
        let bundleIdentifier = FileBrowser.betterFinder.bundleIdentifier
        // The running copy, when there is one, rather than whichever copy LaunchServices ranks first.
        guard let appURL = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else {
            fileBrowserLogger.error("BetterFinder isn't installed")
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { _, error in
            guard let error else { return }
            fileBrowserLogger.error(
                "BetterFinder couldn't open \(url.absoluteString, privacy: .private): \(error.localizedDescription, privacy: .public)")
            let message = error.localizedDescription
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = String(localized: "BetterFinder action failed")
                alert.informativeText = message
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
        return true
    }
}
