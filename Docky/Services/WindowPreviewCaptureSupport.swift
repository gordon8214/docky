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
