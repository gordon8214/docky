import AppKit

/// Explicit page geometry retains row-major order for both scroll directions.
final class NativeLaunchpadGridLayout: NSCollectionViewLayout {
    var viewport: CGSize = .zero
    var columns = 6
    var rows = 4
    var horizontal = false
    var iconSize: CGFloat = 80
    var spacing: CGFloat = 24
    var rowSpacing: CGFloat = 16
    private var attributes: [NSCollectionViewLayoutAttributes] = []
    private var contentSize: CGSize = .zero
    override var collectionViewContentSize: NSSize { contentSize }
    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        let count = collectionView.numberOfItems(inSection: 0)
        let columnCount = max(1, columns)
        let rowCount = max(1, rows)
        let pageCapacity = columnCount * rowCount
        let pageCount = max(1, Int(ceil(Double(count) / Double(pageCapacity))))
        let cellWidth = max(1, (viewport.width - 32 - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount))
        let cellHeight =
            horizontal
            ? max(iconSize + 44, (viewport.height - 32 - CGFloat(rowCount - 1) * rowSpacing) / CGFloat(rowCount))
            : iconSize + 48
        attributes = (0..<count).map { index in
            let local = horizontal ? index % pageCapacity : index
            let column = local % columnCount
            let row = local / columnCount
            let pageOffset = horizontal ? CGFloat(index / pageCapacity) * viewport.width : 0
            let attribute = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: index, section: 0))
            attribute.frame = CGRect(
                x: pageOffset + 16 + CGFloat(column) * (cellWidth + spacing),
                y: 16 + CGFloat(row) * (cellHeight + rowSpacing), width: cellWidth, height: cellHeight)
            return attribute
        }
        let height =
            horizontal
            ? max(viewport.height, attributes.map { $0.frame.maxY + 16 }.max() ?? 0)
            : max(
                viewport.height,
                CGFloat(Int(ceil(Double(count) / Double(columnCount)))) * (cellHeight + rowSpacing) + 32)
        contentSize = CGSize(width: horizontal ? viewport.width * CGFloat(pageCount) : viewport.width, height: height)
    }
    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        attributes.filter { $0.frame.intersects(rect) }
    }
    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        attributes.indices.contains(indexPath.item) ? attributes[indexPath.item] : nil
    }
    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        newBounds.size != collectionView?.bounds.size
    }
}
