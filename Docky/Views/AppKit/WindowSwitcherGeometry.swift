//
//  WindowSwitcherGeometry.swift
//  Docky
//
//  Pure layout for the Windows 11–style window switcher. Every thumbnail
//  shares one height and takes its width from its window's aspect ratio;
//  cards wrap into centered rows like Windows Alt+Tab. Frames are in a
//  flipped coordinate space whose origin is the panel's top-left corner.
//

import CoreGraphics

struct WindowSwitcherGeometry: Equatable {
    enum Metrics {
        static let cardPadding: CGFloat = 6
        /// The header's height at the default icon and font sizes, and its minimum.
        static let headerHeight: CGFloat = 24
        /// Space above and below the header's icon or title when they outgrow `headerHeight`.
        static let headerInset: CGFloat = 4
        static let defaultIconSize: CGFloat = 16
        static let iconSizeRange: ClosedRange<CGFloat> = 12...48
        static let defaultFontSize: CGFloat = 12
        static let fontSizeRange: ClosedRange<CGFloat> = 9...24
        static let headerGap: CGFloat = 6
        static let cardSpacing: CGFloat = 8
        static let panelPadding: CGFloat = 12
        static let minimumCardWidth: CGFloat = 160
        static let maximumAspectRatio: CGFloat = 2.4
        static let defaultAspectRatio: CGFloat = 16.0 / 10.0
        static let thumbnailHeightFraction: CGFloat = 0.15
        static let thumbnailHeightRange: ClosedRange<CGFloat> = 96...160
        static let screenFraction: CGFloat = 0.85
    }

    let thumbnailHeight: CGFloat
    /// Height of each card's icon-and-title header.
    let headerHeight: CGFloat
    let cardFrames: [CGRect]
    /// Card indices for each row, top to bottom.
    let rows: [[Int]]
    /// Size of everything inside the panel, including padding.
    let contentSize: CGSize
    /// Size of the panel on screen. Shorter than `contentSize` when the cards
    /// need more than the allowed height and the panel scrolls.
    let panelSize: CGSize

    var cardHeight: CGFloat {
        Self.cardHeight(thumbnailHeight: thumbnailHeight, headerHeight: headerHeight)
    }

    init(aspectRatios: [CGFloat], screenSize: CGSize, headerHeight: CGFloat) {
        let thumbnailHeight = Self.thumbnailHeight(screenHeight: screenSize.height)
        let cardHeight = Self.cardHeight(thumbnailHeight: thumbnailHeight, headerHeight: headerHeight)
        let maximumRowWidth = max(
            Metrics.minimumCardWidth,
            screenSize.width * Metrics.screenFraction - Metrics.panelPadding * 2
        )
        let cardWidths = aspectRatios.map {
            min(maximumRowWidth, Self.cardWidth(aspectRatio: $0, thumbnailHeight: thumbnailHeight))
        }

        var rows: [[Int]] = []
        var rowWidths: [CGFloat] = []
        for (index, width) in cardWidths.enumerated() {
            if let last = rowWidths.last, last + Metrics.cardSpacing + width <= maximumRowWidth {
                rows[rows.count - 1].append(index)
                rowWidths[rowWidths.count - 1] = last + Metrics.cardSpacing + width
            } else {
                rows.append([index])
                rowWidths.append(width)
            }
        }

        let widestRow = rowWidths.max() ?? 0
        var frames = Array(repeating: CGRect.zero, count: cardWidths.count)
        for (rowIndex, row) in rows.enumerated() {
            var x = Metrics.panelPadding + (widestRow - rowWidths[rowIndex]) / 2
            let y = Metrics.panelPadding + CGFloat(rowIndex) * (cardHeight + Metrics.cardSpacing)
            for index in row {
                frames[index] = CGRect(x: x, y: y, width: cardWidths[index], height: cardHeight)
                x += cardWidths[index] + Metrics.cardSpacing
            }
        }

        let rowCount = CGFloat(rows.count)
        let contentSize = CGSize(
            width: widestRow + Metrics.panelPadding * 2,
            height: rows.isEmpty
                ? Metrics.panelPadding * 2
                : Metrics.panelPadding * 2 + rowCount * cardHeight + (rowCount - 1) * Metrics.cardSpacing
        )

        self.thumbnailHeight = thumbnailHeight
        self.headerHeight = headerHeight
        self.cardFrames = frames
        self.rows = rows
        self.contentSize = contentSize
        self.panelSize = CGSize(
            width: contentSize.width,
            height: min(contentSize.height, screenSize.height * Metrics.screenFraction)
        )
    }

    static func thumbnailHeight(screenHeight: CGFloat) -> CGFloat {
        min(
            Metrics.thumbnailHeightRange.upperBound,
            max(Metrics.thumbnailHeightRange.lowerBound, screenHeight * Metrics.thumbnailHeightFraction)
        )
    }

    /// Whole points, so the icon stays sharp. A corrupt value gets the default.
    static func clampedIconSize(_ size: CGFloat) -> CGFloat {
        guard size.isFinite else { return Metrics.defaultIconSize }
        return min(Metrics.iconSizeRange.upperBound, max(Metrics.iconSizeRange.lowerBound, size.rounded()))
    }

    /// A corrupt value gets the default.
    static func clampedFontSize(_ size: CGFloat) -> CGFloat {
        guard size.isFinite else { return Metrics.defaultFontSize }
        return min(Metrics.fontSizeRange.upperBound, max(Metrics.fontSizeRange.lowerBound, size))
    }

    /// The header fits the taller of the icon and the title's line, and never
    /// shrinks below `Metrics.headerHeight`.
    static func headerHeight(iconSize: CGFloat, textHeight: CGFloat) -> CGFloat {
        max(Metrics.headerHeight, ceil(max(iconSize, textHeight)) + Metrics.headerInset * 2)
    }

    static func cardHeight(thumbnailHeight: CGFloat, headerHeight: CGFloat) -> CGFloat {
        Metrics.cardPadding * 2 + headerHeight + Metrics.headerGap + thumbnailHeight
    }

    static func cardWidth(aspectRatio: CGFloat, thumbnailHeight: CGFloat) -> CGFloat {
        let aspectRatio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : Metrics.defaultAspectRatio
        let thumbnailWidth = min(thumbnailHeight * aspectRatio, thumbnailHeight * Metrics.maximumAspectRatio)
        return max(Metrics.minimumCardWidth, thumbnailWidth + Metrics.cardPadding * 2)
    }

    /// The thumbnail's frame inside a card of the given size.
    static func thumbnailFrame(inCardOfSize size: CGSize, headerHeight: CGFloat) -> CGRect {
        let top = Metrics.cardPadding + headerHeight + Metrics.headerGap
        return CGRect(
            x: Metrics.cardPadding,
            y: top,
            width: max(0, size.width - Metrics.cardPadding * 2),
            height: max(0, size.height - top - Metrics.cardPadding)
        )
    }

    func row(of index: Int) -> Int? {
        rows.firstIndex { $0.contains(index) }
    }

    /// The card in the row above (`direction < 0`) or below (`direction > 0`)
    /// whose horizontal center is nearest to the given card's. Returns nil at
    /// the first or last row.
    func neighbor(of index: Int, direction: Int) -> Int? {
        guard direction != 0,
              cardFrames.indices.contains(index),
              let row = row(of: index) else {
            return nil
        }

        let targetRow = row + (direction < 0 ? -1 : 1)
        guard rows.indices.contains(targetRow) else { return nil }

        let center = cardFrames[index].midX
        return rows[targetRow].min { lhs, rhs in
            abs(cardFrames[lhs].midX - center) < abs(cardFrames[rhs].midX - center)
        }
    }
}
