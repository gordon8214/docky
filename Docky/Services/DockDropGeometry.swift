import CoreGraphics
import Foundation

/// The first visible tile owns the hit; unsupported tiles block targets beneath them.
enum DockDropGeometry {
    struct Candidate {
        let identifier: String
        let frame: CGRect
        let acceptsDrop: Bool
    }
    static func target(at location: CGPoint, candidates: [Candidate]) -> String? {
        guard let candidate = candidates.reversed().first(where: { $0.frame.contains(location) }) else { return nil }
        return candidate.acceptsDrop ? candidate.identifier : nil
    }
}
