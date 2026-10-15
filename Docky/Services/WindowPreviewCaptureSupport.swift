import CoreGraphics
import Foundation
import ScreenCaptureKit
import Synchronization

/// Shares shareable-content metadata across live focus-preview streams.
/// Concurrent callers join one lookup instead of each enumerating every window
/// on the desktop.
@MainActor
final class WindowPreviewContentCache {
    @MainActor
    private final class Snapshot {
        let content: SCShareableContent
        init(_ content: SCShareableContent) { self.content = content }
    }
    private var content: SCShareableContent?
    private var capturedAt: ContinuousClock.Instant?
    private var pending: Task<Snapshot, Error>?

    func invalidate() {
        content = nil
        capturedAt = nil
    }

    func current() async throws -> SCShareableContent {
        try Task.checkCancellation()
        if let content, let capturedAt, capturedAt.duration(to: .now) < .seconds(2) {
            return content
        }
        if let pending {
            let result = try await pending.value
            try Task.checkCancellation()
            return result.content
        }
        let task = Task { @MainActor in
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            return Snapshot(content)
        }
        pending = task
        defer { pending = nil }
        let result = try await task.value
        content = result.content
        capturedAt = .now
        try Task.checkCancellation()
        return result.content
    }
}

enum WindowPreviewCaptureSizing {
    static func size(for source: CGSize, scale: CGFloat = 1, maximum: CGSize) -> CGSize {
        guard source.width.isFinite, source.height.isFinite, scale.isFinite,
              source.width > 0, source.height > 0, scale > 0 else {
            return CGSize(width: 1, height: 1)
        }
        let factor = min(scale, maximum.width / source.width, maximum.height / source.height)
        return CGSize(width: max(1, floor(source.width * factor)), height: max(1, floor(source.height * factor)))
    }

    /// Scales `image` down to fit `maximum` pixels, keeping its aspect ratio.
    /// Returns the image itself when it already fits.
    static func downscaled(_ image: CGImage, toFit maximum: CGSize) -> CGImage? {
        let source = CGSize(width: image.width, height: image.height)
        let target = size(for: source, maximum: maximum)
        guard target.width < source.width || target.height < source.height else { return image }
        let colorSpace = image.colorSpace.flatMap { $0.supportsOutput ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
                data: nil,
                width: Int(target.width),
                height: Int(target.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(origin: .zero, size: target))
        return context.makeImage()
    }
}

/// Hold at most one converted frame while the main actor is busy. SCStream's
/// queueDepth bounds capture buffers, but not Tasks holding converted CGImages.
final class WindowPreviewFrameGate: Sendable {
    private struct State {
        var pending = false
        var stopped = false
    }
    private let state = Mutex(State())

    func beginFrame() -> Bool {
        state.withLock { state in
            guard !state.stopped, !state.pending else { return false }
            state.pending = true
            return true
        }
    }

    func endFrame() {
        state.withLock { $0.pending = false }
    }

    func stop() {
        state.withLock { $0.stopped = true }
    }
}

/// Orders thumbnail captures without ever evicting a cached image: windows
/// with no thumbnail first, then thumbnails invalidated by a resize or focus
/// change, then stale ones (expired or retitled). Within each group, windows
/// go in the order given. Stale refreshes start at most every `staleInterval`,
/// and each window's stale thumbnail is recaptured at most every
/// `minimumRecaptureInterval`, so a window retitling itself constantly can't
/// monopolize captures.
struct WindowPreviewRefreshQueue {
    enum Priority: Int, Comparable {
        case missing
        case invalidated
        case stale

        static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Step: Equatable {
        case capture(String, Priority)
        case wait(until: ContinuousClock.Instant)
        case idle
    }

    let staleInterval: Duration
    let minimumRecaptureInterval: Duration
    private(set) var queued: [String: Priority] = [:]
    private var lastAttempt: [String: ContinuousClock.Instant] = [:]
    private var lastStaleCapture: ContinuousClock.Instant?

    init(staleInterval: Duration, minimumRecaptureInterval: Duration) {
        self.staleInterval = staleInterval
        self.minimumRecaptureInterval = minimumRecaptureInterval
    }

    var hasUrgentWork: Bool { queued.values.contains { $0 < .stale } }

    /// Queues `identifier`, keeping the more urgent priority when it's queued.
    mutating func enqueue(_ identifier: String, _ priority: Priority) {
        if let existing = queued[identifier], existing <= priority { return }
        queued[identifier] = priority
    }

    mutating func remove(_ identifier: String) {
        queued.removeValue(forKey: identifier)
    }

    /// Forgets windows that no longer exist.
    mutating func retain(_ identifiers: Set<String>) {
        queued = queued.filter { identifiers.contains($0.key) }
        lastAttempt = lastAttempt.filter { identifiers.contains($0.key) }
    }

    mutating func removeAll() {
        queued.removeAll()
        lastAttempt.removeAll()
        lastStaleCapture = nil
    }

    /// The next capture among `order`, which lists the windows that may be
    /// captured now. Dequeues and records the capture it returns. Queued
    /// windows missing from `order` wait for a later call.
    mutating func next(in order: [String], now: ContinuousClock.Instant) -> Step {
        var best: (identifier: String, priority: Priority)?
        var earliestEligible: ContinuousClock.Instant?
        for identifier in order {
            guard let priority = queued[identifier] else { continue }
            if priority == .stale, let last = lastAttempt[identifier], now < last + minimumRecaptureInterval {
                let eligible = last + minimumRecaptureInterval
                earliestEligible = min(earliestEligible ?? eligible, eligible)
                continue
            }
            if best == nil || priority < best!.priority {
                best = (identifier, priority)
                if priority == .missing { break }
            }
        }
        guard let best else {
            return earliestEligible.map { .wait(until: $0) } ?? .idle
        }
        if best.priority == .stale, let lastStaleCapture, now < lastStaleCapture + staleInterval {
            return .wait(until: lastStaleCapture + staleInterval)
        }
        queued.removeValue(forKey: best.identifier)
        lastAttempt[best.identifier] = now
        if best.priority == .stale { lastStaleCapture = now }
        return .capture(best.identifier, best.priority)
    }
}
