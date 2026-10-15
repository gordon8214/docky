import AppKit
import Combine
import Foundation

@main
struct AppKitBrowserRegression {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        testGeometry()
        testDropTargets()
        testPresentationGeometry()
        testLauncherPages()
        testSearchAndSelection()
        testSelectionFeedback()
        testPreviewCaptureBounds()
        testControllerRelease()
        testObservationLifecycle()
        print("AppKit browser and geometry regressions passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    private static func testGeometry() {
        let canvas = CGSize(width: 400, height: 180)
        let size = CGSize(width: 60, height: 80)
        expect(DockAxisGeometry.frame(size: size, offset: 20, canvas: canvas, edge: .bottom) == CGRect(x: 20, y: 100, width: 60, height: 80), "Bottom edge must grow inward")
        expect(DockAxisGeometry.frame(size: size, offset: 20, canvas: canvas, edge: .top).minY == 0, "Top edge must stay anchored")
        expect(DockAxisGeometry.frame(size: size, offset: 20, canvas: canvas, edge: .right).minX == 340, "Right edge must stay anchored")
        expect(DockAxisGeometry.frame(size: size, offset: 20, canvas: canvas, edge: .left).minX == 0, "Left edge must stay anchored")
        let frame = CGRect(x: 14, y: 20, width: 60, height: 40)
        expect(DockAxisGeometry.topLeftFrame(frame, containerHeight: 180).origin == CGPoint(x: 14, y: 120), "Window coordinates must convert once")
        let frames = [CGRect(x: 20, y: 0, width: 40, height: 50), CGRect(x: 70, y: 0, width: 40, height: 50)]
        expect(DockAxisGeometry.insertionIndex(at: 35, frames: frames, vertical: false) == 0, "Drop before first tile")
        expect(DockAxisGeometry.insertionIndex(at: 41, frames: frames, vertical: false) == 1, "Drop after first midpoint")
        expect(DockAxisGeometry.insertionIndex(at: 100, frames: frames, vertical: false) == 2, "Drop after final tile")
        let scrolled = frames.map { $0.offsetBy(dx: -60, dy: 0) }
        expect(DockAxisGeometry.insertionIndex(at: 10, frames: scrolled, vertical: false) == 1, "Scrolling changes insertion coordinates")
    }

    @MainActor
    private static func testDropTargets() {
        let frame = CGRect(x: 30, y: 10, width: 60, height: 60)
        let app = DockDropGeometry.Candidate(identifier: "app", frame: frame, acceptsDrop: true)
        let widget = DockDropGeometry.Candidate(identifier: "widget", frame: frame, acceptsDrop: false)
        expect(DockDropGeometry.target(at: CGPoint(x: 40, y: 20), candidates: [app]) == "app", "Apps accept document drops")
        expect(DockDropGeometry.target(at: CGPoint(x: 40, y: 20), candidates: [app, widget]) == nil,
            "Widget-backed tiles must block open-with drops")
        expect(DockDropGeometry.target(at: CGPoint(x: 120, y: 20), candidates: [app]) == nil, "Outside coordinates reject drops")
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        let clip = NSClipView(frame: CGRect(x: 100, y: 0, width: 100, height: 100))
        let document = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 100))
        let offscreen = NSView(frame: CGRect(x: 0, y: 10, width: 60, height: 60))
        root.addSubview(clip)
        clip.documentView = document
        document.addSubview(offscreen)
        clip.scroll(to: CGPoint(x: 100, y: 0))
        let fullFrame = root.convert(offscreen.bounds, from: offscreen)
        expect(fullFrame.contains(CGPoint(x: 40, y: 20)), "Full offscreen bounds can overlap fixed tiles")
        let clipped = root.convert(offscreen.visibleRect, from: offscreen)
        let hiddenApp = DockDropGeometry.Candidate(identifier: "hidden", frame: clipped, acceptsDrop: true)
        expect(DockDropGeometry.target(at: CGPoint(x: 40, y: 20), candidates: [app, hiddenApp]) == "app",
            "Clipped scroll tiles must not intercept drops over fixed tiles")

    }

    private static func testPresentationGeometry() {
        let visible = CGRect(x: -1400, y: 100, width: 1400, height: 900)
        let source = CGRect(x: -900, y: 100, width: 60, height: 60)
        let size = CGSize(width: 400, height: 300)
        expect(DockPresentationGeometry.origin(for: .init(size: size, source: source, visible: visible, edge: .bottom)).y == 160,
            "Bottom dock previews open above the source on secondary displays")
        let top = source.offsetBy(dx: 0, dy: 840)
        expect(DockPresentationGeometry.origin(for: .init(size: size, source: top, visible: visible, edge: .top)).y == 640,
            "Top dock previews open below the source")
        let converted = DockPresentationGeometry.screenFrame(fromTopLeft: CGRect(x: 40, y: 10, width: 50, height: 50),
            windowFrame: CGRect(x: -1400, y: 100, width: 200, height: 900))
        expect(converted.origin == CGPoint(x: -1360, y: 940), "Tile anchors convert using their display origin")
    }

    @MainActor
    private static func testLauncherPages() {
        let browser = NativeBrowserController()
        browser.setItems((0..<13).map { index in NativeBrowserItem(id: String(index), title: String(index), activate: {}) })
        _ = browser.view
        let layout = NativeLaunchpadGridLayout()
        layout.viewport = CGSize(width: 600, height: 400)
        layout.columns = 3
        layout.rows = 2
        layout.horizontal = true
        layout.iconSize = 60
        layout.spacing = 12
        browser.collection.collectionViewLayout = layout
        browser.collection.reloadData()
        layout.prepare()
        expect(layout.collectionViewContentSize.width == 1800, "Thirteen items must occupy three six-item pages")
        let first = layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame
        let second = layout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))!.frame
        let nextRow = layout.layoutAttributesForItem(at: IndexPath(item: 3, section: 0))!.frame
        let nextPage = layout.layoutAttributesForItem(at: IndexPath(item: 6, section: 0))!.frame
        expect(second.minX > first.minX && second.minY == first.minY, "Pages preserve row-major order")
        expect(nextRow.minY > first.minY, "Configured rows are honored")
        expect(nextPage.minX - first.minX == 600, "Next page aligns with viewport")
        layout.horizontal = false
        layout.prepare()
        expect(layout.collectionViewContentSize.width == 600, "Vertical layout must not page horizontally")
        expect(layout.layoutAttributesForItem(at: IndexPath(item: 6, section: 0))!.frame.minY > nextRow.minY, "Vertical rows continue below viewport")
    }

    @MainActor
    private static func testSearchAndSelection() {
        var activations = 0
        var dismissed = false
        let browser = NativeBrowserController()
        _ = browser.view
        browser.setItems([
            NativeBrowserItem(id: "first", title: "Calendar", activate: { activations += 1 }),
            NativeBrowserItem(id: "second", title: "Weather", activate: { activations += 10 })
        ])
        browser.onEscape = { dismissed = true }
        browser.search.stringValue = "Weather"
        browser.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: browser.search))
        expect(browser.displayed.map(\.id) == ["second"], "Search must filter visible items")
        let editor = NSTextView()
        expect(browser.control(browser.search, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))), "Search Return must activate")
        expect(activations == 10, "Return activates filtered item")
        expect(browser.control(browser.search, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))), "Search Escape must dismiss")
        expect(dismissed, "Escape dismiss callback must fire")
        browser.search.stringValue = ""
        browser.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: browser.search))
        _ = browser.control(browser.search, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:)))
        expect(browser.selectionID == "first", "Down selects first result from search field")
        _ = browser.control(browser.search, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:)))
        expect(browser.selectionID == "second", "Down advances selection")
    }

    @MainActor
    private static func testSelectionFeedback() {
        let browser = NativeBrowserController()
        _ = browser.view
        let items = [
            NativeBrowserItem(id: "first", title: "First", activate: {}),
            NativeBrowserItem(id: "second", title: "Second", activate: {})
        ]
        browser.setItems(items)
        var selections: [String] = []
        browser.onSelection = { selections.append($0) }
        for usesList in [false, true] {
            browser.usesList = usesList
            browser.selectionID = "first"
            selections = []
            for _ in 0..<20 { browser.setItems(items) }
            expect(selections.isEmpty, "Restoring selection during reload must not feed back into the model")
            browser.setItems(items.reversed())
            expect(selections.isEmpty && browser.selectionID == "first", "Reordering must preserve selection without feedback")
            browser.setItems(items)
            browser.selectItem(at: 1)
            expect(selections == ["second"], "Keyboard selection must notify exactly once")
            browser.selectItem(at: 1)
            expect(selections == ["second"], "Selecting the current item must not restart its preview")
            browser.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            expect(selections == ["second", "first"], "A changed table selection must still reach the model")
            browser.collectionView(browser.collection, didSelectItemsAt: [IndexPath(item: 1, section: 0)])
            browser.collectionView(browser.collection, didSelectItemsAt: [IndexPath(item: 1, section: 0)])
            expect(selections == ["second", "first", "second"], "Repeated grid selection must notify once")
        }
    }

    @MainActor
    private static func testPreviewCaptureBounds() {
        let limit = CGSize(width: 4096, height: 2304)
        let oversized = WindowPreviewCaptureSizing.size(
            for: CGSize(width: 100_000, height: 50_000), scale: 2, maximum: limit)
        expect(oversized == CGSize(width: 4096, height: 2048), "Huge windows must keep a bounded capture size and aspect ratio")
        expect(WindowPreviewCaptureSizing.size(for: CGSize(width: 800, height: 600), scale: 2, maximum: limit)
            == CGSize(width: 1600, height: 1200), "Ordinary windows retain Retina resolution")
        expect(WindowPreviewCaptureSizing.size(for: CGSize(width: CGFloat.infinity, height: 100), maximum: limit)
            == CGSize(width: 1, height: 1), "Invalid window dimensions must not create oversized buffers")
        let gate = WindowPreviewFrameGate()
        expect(gate.beginFrame(), "The first frame may enter the main-actor queue")
        for _ in 0..<10_000 {
            expect(!gate.beginFrame(), "A busy UI must not accumulate captured frames")
        }
        gate.endFrame()
        expect(gate.beginFrame(), "Delivering a frame allows the next one")
        gate.stop()
        gate.endFrame()
        expect(!gate.beginFrame(), "A stopped preview must reject late frames")
    }

    @MainActor
    private static func testObservationLifecycle() {
        let updates = PassthroughSubject<Int, Never>()
        let session = NativeObservationSession()
        var count = 0
        session.add { updates.sink { count += $0 } }
        updates.send(1)
        session.stop()
        updates.send(10)
        expect(count == 1, "Closing a presentation cancels UI observers")
        session.start()
        updates.send(2)
        expect(count == 3, "Reopening reconnects UI observers once")
        session.start()
        updates.send(4)
        expect(count == 7, "Repeated appearance must not duplicate observers")
        session.stop()
    }

    @MainActor
    private static func testControllerRelease() {
        weak var released: NativeBrowserController?
        autoreleasepool {
            let controller = NativeBrowserController()
            _ = controller.view
            controller.setItems([NativeBrowserItem(id: "test", title: "Test", activate: {})])
            released = controller
        }
        expect(released == nil, "Browser delegate and controls must not retain controller")
    }
}
