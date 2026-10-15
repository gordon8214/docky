//
//  DockLayoutService.swift
//  Docky
//

import Combine
import CoreGraphics
import Foundation

@MainActor
final class DockLayoutService: ObservableObject {
    static let shared = DockLayoutService()

    @Published private(set) var chromeSize: CGSize = .zero

    private init() {}

    func setChromeSize(_ size: CGSize) {
        guard abs(chromeSize.width - size.width) > 0.0001 || abs(chromeSize.height - size.height) > 0.0001 else {
            return
        }
        chromeSize = size
    }
}
