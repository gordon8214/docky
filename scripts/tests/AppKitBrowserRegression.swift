import AppKit
import Combine
import Foundation

@main
struct AppKitBrowserRegression {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        testGeometry()
        testWindowSwitcherGeometry()
        testDropTargets()
        testPresentationGeometry()
        testLauncherPages()
        testSearchAndSelection()
        testSelectionFeedback()
        testPreviewCaptureBounds()
        testPreviewRefreshQueue()
        testWindowServerRules()
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

    private static func testWindowSwitcherGeometry() {
        let screen = CGSize(width: 1440, height: 900)
        let widescreen = 16.0 / 10.0
        let six = WindowSwitcherGeometry(aspectRatios: Array(repeating: widescreen, count: 6), screenSize: screen)
        expect(six.thumbnailHeight == 135, "Thumbnails are 15% of the screen height")
        expect(six.cardHeight == 177, "Cards add padding and a header to the thumbnail")
        expect(six.rows == [[0, 1, 2, 3, 4], [5]], "Cards wrap at 85% of the screen width")
        expect(six.cardFrames[0] == CGRect(x: 12, y: 12, width: 228, height: 177), "First card sits inside the panel padding")
        expect(six.cardFrames[5] == CGRect(x: 484, y: 197, width: 228, height: 177), "A short last row is centered")
        expect(six.contentSize == CGSize(width: 1196, height: 386), "The panel hugs its widest row")
        expect(six.panelSize == six.contentSize, "Short content doesn't scroll")
        expect(six.neighbor(of: 5, direction: -1) == 2, "Up moves to the nearest card above")
        expect(six.neighbor(of: 0, direction: 1) == 5, "Down moves to the nearest card below")
        expect(six.neighbor(of: 5, direction: 1) == nil, "Down stops at the last row")
        expect(six.neighbor(of: 3, direction: -1) == nil, "Up stops at the first row")

        let wide = WindowSwitcherGeometry.cardWidth(aspectRatio: 4, thumbnailHeight: 135)
        expect(wide == 336, "Very wide windows are capped at 2.4:1")
        let portrait = WindowSwitcherGeometry.cardWidth(aspectRatio: 0.5, thumbnailHeight: 135)
        expect(portrait == 160, "Narrow windows keep room for the title")
        let invalid = WindowSwitcherGeometry.cardWidth(aspectRatio: .nan, thumbnailHeight: 135)
        expect(invalid == 228, "Unknown aspect ratios fall back to 16:10")
        expect(WindowSwitcherGeometry.thumbnailHeight(screenHeight: 400) == 96, "Thumbnails have a minimum height")
        expect(WindowSwitcherGeometry.thumbnailHeight(screenHeight: 2000) == 160, "Thumbnails have a maximum height")
        expect(
            WindowSwitcherGeometry.thumbnailFrame(inCardOfSize: CGSize(width: 228, height: 177))
                == CGRect(x: 6, y: 36, width: 216, height: 135),
            "The thumbnail sits below the header")

        let many = WindowSwitcherGeometry(aspectRatios: Array(repeating: widescreen, count: 40), screenSize: screen)
        expect(many.rows.count == 8, "Many windows wrap into many rows")
        expect(many.panelSize.height == 765 && many.contentSize.height == 1496, "Tall content scrolls inside a capped panel")

        let narrow = WindowSwitcherGeometry(aspectRatios: [4, widescreen], screenSize: CGSize(width: 300, height: 900))
        expect(narrow.rows == [[0], [1]], "Each card gets its own row on a narrow screen")
        expect(narrow.cardFrames[0].width == 231, "A card never exceeds the row width")

        let empty = WindowSwitcherGeometry(aspectRatios: [], screenSize: screen)
        expect(empty.rows.isEmpty && empty.cardFrames.isEmpty, "No windows means no cards")
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
        let context = CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        let source = context.makeImage()!
        let scaled = WindowPreviewCaptureSizing.downscaled(source, toFit: CGSize(width: 100, height: 100))
        expect(scaled?.width == 100 && scaled?.height == 50, "Captures scale down to fit, keeping their aspect ratio")
        expect(WindowPreviewCaptureSizing.downscaled(source, toFit: limit) === source,
               "Captures that already fit aren't redrawn")
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

    private static func testPreviewRefreshQueue() {
        var queue = WindowPreviewRefreshQueue(staleInterval: .milliseconds(500), minimumRecaptureInterval: .seconds(5))
        let start = ContinuousClock.now
        let order = ["front", "middle", "back", "elsewhere"]
        queue.enqueue("back", .stale)
        queue.enqueue("middle", .invalidated)
        queue.enqueue("front", .stale)
        queue.enqueue("elsewhere", .missing)
        queue.enqueue("middle", .stale)
        expect(queue.queued["middle"] == .invalidated, "Queuing keeps the more urgent priority")
        expect(queue.next(in: order, now: start) == .capture("elsewhere", .missing), "Missing thumbnails come first")
        expect(queue.next(in: order, now: start) == .capture("middle", .invalidated), "Invalidated thumbnails come next")
        expect(queue.next(in: order, now: start) == .capture("front", .stale), "Stale thumbnails follow the given order")
        expect(queue.next(in: order, now: start + .milliseconds(100)) == .wait(until: start + .milliseconds(500)),
               "Stale refreshes are paced")
        expect(queue.next(in: order, now: start + .milliseconds(500)) == .capture("back", .stale),
               "The next stale refresh starts once the pace allows")

        queue.enqueue("front", .stale)
        expect(queue.next(in: order, now: start + .seconds(1)) == .wait(until: start + .seconds(5)),
               "One window's stale thumbnail refreshes at most every 5 seconds")
        queue.enqueue("middle", .missing)
        expect(queue.next(in: order, now: start + .seconds(1)) == .capture("middle", .missing),
               "Backoff doesn't delay a window without a thumbnail")
        expect(queue.next(in: order, now: start + .seconds(5)) == .capture("front", .stale),
               "A stale window refreshes again after its backoff")

        queue.enqueue("hidden", .missing)
        expect(queue.next(in: order, now: start + .seconds(6)) == .idle, "Windows that can't be captured now wait")
        expect(queue.hasUrgentWork, "Waiting windows stay queued")
        queue.retain(["front"])
        expect(queue.queued.isEmpty && !queue.hasUrgentWork, "Closed windows leave the queue")
    }

    /// Tag, attribute and packet values recorded from macOS 27.0.1 (26A434).
    private static func testWindowServerRules() {
        let visible: UInt64 = 0x0300_0001_0048_2001
        let minimized: UInt64 = 0x1300_0001_0048_0001
        let hiddenApp: UInt64 = 0x0300_0081_0048_0001
        expect(WindowServerWindowRules.isUserWindow(tags: visible, attributes: 0x3), "A visible document window is listed")
        expect(WindowServerWindowRules.isUserWindow(tags: minimized, attributes: 0x1), "A minimized document window is listed")
        expect(WindowServerWindowRules.isUserWindow(tags: hiddenApp, attributes: 0x1), "A hidden app's window stays a user window")
        expect(WindowServerWindowRules.isMinimized(tags: minimized), "The minimized tag is recognized")
        expect(!WindowServerWindowRules.isMinimized(tags: visible) && !WindowServerWindowRules.isMinimized(tags: hiddenApp),
               "Visible and hidden windows aren't minimized")
        expect(!WindowServerWindowRules.isUserWindow(tags: 0x0400_0000_0000_0000, attributes: 0x2),
               "Windows without a document tag are utility surfaces")
        expect(WindowServerWindowRules.isUserWindow(tags: 0x2 | 0x8000_0000, attributes: 0x2),
               "A document panel is listed")
        expect(!WindowServerWindowRules.isUserWindow(tags: 0x2, attributes: 0x2),
               "A panel without the document bit isn't listed")
        expect(WindowServerWindowRules.isUserWindow(tags: 0x0400_0000_0000_0001, attributes: 0),
               "The visible tag alone lists a document window")
        expect(!WindowServerWindowRules.isUserWindow(tags: 0x1000_0000_0000_0001, attributes: 0x4),
               "Off-screen tags only count with attributes 0 or 1")
        expect(!WindowServerWindowRules.isUserWindow(tags: 0x1, attributes: 0),
               "A document window with no state tags isn't listed")
        expect(WindowServerWindowRules.hasOrderedInAttribute(0x3) && !WindowServerWindowRules.hasOrderedInAttribute(0x1),
               "The ordered-in attribute is bit 0x2")
        expect(CGRect(x: 10, y: 20, width: 300, height: 200).isApproximately(CGRect(x: 11.5, y: 20, width: 300, height: 201)),
               "Frames within 2 points match")
        expect(!CGRect(x: 10, y: 20, width: 300, height: 200).isApproximately(CGRect(x: 12, y: 20, width: 300, height: 200)),
               "Frames 2 points apart don't match")

        func info(orderedIn: Bool, tags: UInt64) -> WindowServerWindowInfo {
            WindowServerWindowInfo(id: 7, processIdentifier: 1, bounds: .zero, tags: tags, attributes: 0x1,
                                   isOrderedIn: orderedIn, spaceIDs: [4])
        }
        expect(info(orderedIn: true, tags: visible).isListed, "Ordered-in windows are listed")
        expect(info(orderedIn: false, tags: minimized).isListed, "Minimized windows are listed")
        expect(!info(orderedIn: false, tags: visible).isListed, "Closed windows an app keeps aren't listed")

        var spacePacket = [UInt8](repeating: 0, count: 12)
        spacePacket.withUnsafeMutableBytes {
            $0.storeBytes(of: UInt64(10055), toByteOffset: 0, as: UInt64.self)
            $0.storeBytes(of: UInt32(95622), toByteOffset: 8, as: UInt32.self)
        }
        spacePacket.withUnsafeBytes { packet in
            expect(WindowServerEvent.windowRemovedFromSpace.windowID(in: packet) == 95622,
                   "Space events carry the window after the Space ID")
            expect(WindowServerEvent.windowAddedToSpace.windowID(in: UnsafeRawBufferPointer(rebasing: packet[0..<8])) == nil,
                   "A truncated Space packet names no window")
        }
        var windowPacket = [UInt8](repeating: 0, count: 4)
        windowPacket.withUnsafeMutableBytes { $0.storeBytes(of: UInt32(95624), toByteOffset: 0, as: UInt32.self) }
        windowPacket.withUnsafeBytes { packet in
            expect(WindowServerEvent.windowMoved.windowID(in: packet) == 95624, "Window events carry the window first")
        }
        [UInt8](repeating: 0, count: 4).withUnsafeBytes { packet in
            expect(WindowServerEvent.windowDestroyed.windowID(in: packet) == nil, "Window ID 0 names no window")
        }
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
