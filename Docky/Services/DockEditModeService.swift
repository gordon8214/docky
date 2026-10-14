//
//  DockEditModeService.swift
//  Docky
//

import Combine
import Foundation
import CoreGraphics

enum DockEditPaletteItem: Equatable, Identifiable {
    case launchpad
    case startMenu
    case spacer
    case flexibleSpacer
    case divider
    case widget(ownerBundleIdentifier: String, kind: WidgetKind)
    case smartStack

    var id: String {
        switch self {
        case .launchpad:
            "launchpad"
        case .startMenu:
            "start-menu"
        case .spacer:
            "spacer"
        case .flexibleSpacer:
            "flexible-spacer"
        case .divider:
            "divider"
        case .widget(let ownerBundleIdentifier, let kind):
            "widget:\(ownerBundleIdentifier):\(kind.rawValue)"
        case .smartStack:
            "smart-stack"
        }
    }
}

struct DockEditPaletteDrag: Equatable {
    let item: DockEditPaletteItem
    let widgetSpan: TileSpan?
    let location: CGPoint
}

enum DockEditDropSection: Equatable {
    case pinned
    case trailing
}

struct DockEditDropDestination: Equatable {
    let section: DockEditDropSection
    let index: Int
}

@MainActor
final class DockEditModeService: ObservableObject {
    static let shared = DockEditModeService()

    @Published private(set) var isActive = false
    @Published private(set) var paletteDrag: DockEditPaletteDrag?
    @Published var paletteDropDestination: DockEditDropDestination?

    private init() {}

    func enter() {
        isActive = true
    }

    func exit() {
        isActive = false
        endPaletteDrag()
    }

    func toggle() {
        isActive ? exit() : enter()
    }

    func updatePaletteDrag(item: DockEditPaletteItem, location: CGPoint, widgetSpan: TileSpan? = nil) {
        isActive = true
        paletteDrag = DockEditPaletteDrag(item: item, widgetSpan: widgetSpan, location: location)
    }

    func beginPaletteDrag(item: DockEditPaletteItem, widgetSpan: TileSpan? = nil) {
        isActive = true
        paletteDrag = DockEditPaletteDrag(item: item, widgetSpan: widgetSpan, location: .zero)
    }

    func endPaletteDrag() {
        paletteDrag = nil
        paletteDropDestination = nil
    }
}
