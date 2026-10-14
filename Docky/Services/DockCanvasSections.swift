import Foundation

struct DockCanvasSection: Identifiable {
    let index: Int
    let id: String
    let tiles: [Tile]
}

enum DockCanvasComponent: Identifiable {
    case section(DockCanvasSection)
    case divider(Tile)

    var id: String {
        switch self {
        case .section(let section):
            "section:\(section.id)"
        case .divider(let tile):
            tile.id
        }
    }

    var index: Int? {
        switch self {
        case .section(let section):
            return section.index
        default:
            return nil
        }
    }
}

struct DockCanvasScrollSection {
    let index: Int
    let id: String
    let axisLength: CGFloat
}
