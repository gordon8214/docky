import Foundation
import CoreGraphics

/// Pure geometry and Space classification, independent of AX permissions.
enum DockSystemGeometry {
    static func fullscreen(displayID: String, separateSpaces: Bool, displays: [[String: Any]]) -> Bool? {
        let display = displays.first {
            !separateSpaces || ($0["Display Identifier"] as? String) == displayID
        }
        guard let current = display?["Current Space"] as? [String: Any],
              let type = current["type"] as? NSNumber else { return nil }
        // Managed fullscreen Spaces include native Split View. System/user
        // Spaces (types 2/0) must not be mistaken for fullscreen (type 4).
        return type.intValue == 4
    }
    static func quartz(_ rect: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryMaxY - rect.maxY, width: rect.width, height: rect.height)
    }
    static func restingChrome(window: CGRect, size: CGSize, edge: ResolvedDockWindowPosition,
                              edgeGap: CGFloat = 0) -> CGRect {
        let width = min(size.width, window.width)
        let height = min(size.height, window.height)
        switch edge {
        case .bottom:
            return CGRect(x: window.midX - width / 2, y: window.minY + edgeGap, width: width, height: height)
        case .top:
            return CGRect(x: window.midX - width / 2, y: window.maxY - edgeGap - height, width: width, height: height)
        case .left:
            return CGRect(x: window.minX + edgeGap, y: window.midY - height / 2, width: width, height: height)
        case .right:
            return CGRect(x: window.maxX - edgeGap - width, y: window.midY - height / 2, width: width, height: height)
        }
    }
    static func strip(screen: CGRect, chrome: CGRect, edge: ResolvedDockWindowPosition) -> CGRect {
        switch edge {
        case .bottom:
            return CGRect(x: screen.minX, y: screen.minY, width: screen.width,
                          height: max(0, min(screen.height, chrome.maxY - screen.minY)))
        case .top:
            return CGRect(x: screen.minX, y: max(screen.minY, chrome.minY), width: screen.width,
                          height: max(0, min(screen.height, screen.maxY - chrome.minY)))
        case .left:
            return CGRect(x: screen.minX, y: screen.minY,
                          width: max(0, min(screen.width, chrome.maxX - screen.minX)), height: screen.height)
        case .right:
            return CGRect(x: max(screen.minX, chrome.minX), y: screen.minY,
                          width: max(0, min(screen.width, screen.maxX - chrome.minX)), height: screen.height)
        }
    }
    static func orientation(_ edge: ResolvedDockWindowPosition) -> Int32 {
        switch edge {
        case .top: 1
        case .bottom: 2
        case .left: 3
        case .right: 4
        }
    }
    static func usableFrame(screen: CGRect, strip: CGRect, edge: ResolvedDockWindowPosition) -> CGRect {
        switch edge {
        case .bottom:
            return CGRect(x: screen.minX, y: max(screen.minY, strip.maxY), width: screen.width,
                          height: max(0, screen.maxY - max(screen.minY, strip.maxY)))
        case .top:
            return CGRect(x: screen.minX, y: screen.minY, width: screen.width,
                          height: max(0, screen.height - strip.height))
        case .left:
            return CGRect(x: max(screen.minX, strip.maxX), y: screen.minY,
                          width: max(0, screen.maxX - max(screen.minX, strip.maxX)), height: screen.height)
        case .right:
            return CGRect(x: screen.minX, y: screen.minY,
                          width: max(0, min(screen.maxX, strip.minX) - screen.minX), height: screen.height)
        }
    }
}
